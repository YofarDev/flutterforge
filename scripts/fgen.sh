#!/usr/bin/env bash

# Generate a new feature's boilerplate following the FlutterForge clean
# architecture.
#
# Contract (documented in template-README.md):
#   fgen.sh <feature_name>                            # lean default
#   fgen.sh <feature_name> --with-service             # + domain coordination seam
#   fgen.sh <feature_name> --with-dto                 # + transport/domain split
#   fgen.sh <feature_name> --with-service --with-dto  # full layout
#
#   - Must run inside a FlutterForge application. The app root is resolved by
#     walking up from the current directory until a pubspec.yaml + lib/ pair
#     is found; there is no fallback project name.
#   - <feature_name> is snake_case or camelCase. It is normalized to
#     snake_case, then validated as a Dart identifier (rejects empty values,
#     separators, '..', punctuation, invalid starting characters and Dart
#     reserved identifiers).
#   - The LEAN DEFAULT generates only the layers a simple feature needs: domain
#     model (no JSON serialization), repository interface, placeholder data
#     source (returning the domain model directly), repository implementation
#     with typed results, cubit depending on the repository interface, state,
#     a single screen widget, plus repository/cubit/screen tests. The data
#     source placeholder is NOT a real transport schema — introduce
#     --with-dto when a real transport representation exists.
#   - --with-dto additionally generates the transport DTO (with JSON
#     serialization), the DTO→domain conversion, and DTO mapping tests.
#   - --with-service additionally generates a PLACEHOLDER domain service
#     between the cubit and the repository, plus its tests. The placeholder
#     must gain actual rules/coordination or be removed — a forwarding service
#     is not mandatory architecture.
#   - All output paths are computed before writing. The script refuses to run
#     if the feature's lib/ or test/ directory already exists (symlinks
#     included) — it never partially overwrites an existing feature.
#   - Files are rendered into an owned temporary directory and published only
#     afterwards. If localization or build_runner then fails, the published
#     feature is kept, the incomplete state is reported, and the script exits
#     non-zero — user changes elsewhere in the app are never touched.
#   - Screen localization keys are added through scripts/fstr.sh. Key
#     collisions are refused BEFORE anything is written (the ARB files are
#     checked up front; fstr's own collision check remains as a backstop).

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

err() {
    echo -e "${RED}Error: $*${NC}" >&2
}

usage() {
    echo "Usage: $0 <feature_name> [--with-service] [--with-dto]"
    echo ""
    echo "  (default)      lean layout: model, repository interface + impl,"
    echo "                 placeholder data source, cubit, screen, tests"
    echo "  --with-service insert a placeholder domain service (remove it or"
    echo "                 grow it into real coordination logic)"
    echo "  --with-dto     add a transport DTO with serialization and mapping"
    echo ""
    echo "Example: $0 user_profile"
    echo "Example: $0 auth --with-service --with-dto"
}

# --- 1. Arguments ---------------------------------------------------------------

if [ $# -lt 1 ]; then
    err "Feature name is required."
    echo ""
    usage
    exit 1
fi

FEATURE_NAME="$1"
WITH_SERVICE=false
WITH_DTO=false

shift
while [ $# -gt 0 ]; do
    case "$1" in
        --with-service)
            WITH_SERVICE=true
            ;;
        --with-dto)
            WITH_DTO=true
            ;;
        *)
            err "Unknown option: '$1'."
            echo ""
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$FEATURE_NAME" ]; then
    err "Feature name cannot be empty."
    exit 1
fi

# --- 2. Resolve the application root ---------------------------------------------

APP_ROOT=""
dir="$PWD"
while [ "$dir" != "/" ]; do
    if [ -f "$dir/pubspec.yaml" ] && [ -d "$dir/lib" ]; then
        APP_ROOT="$dir"
        break
    fi
    dir="$(dirname "$dir")"
done

if [ -z "$APP_ROOT" ]; then
    err "No Flutter application found: looked for pubspec.yaml and lib/ in the"
    err "current directory and its ancestors."
    err "Run this script from inside a FlutterForge application."
    exit 1
fi

PROJECT_NAME="$(grep -E '^name:' "$APP_ROOT/pubspec.yaml" | head -n 1 | sed -E 's/^name:[[:space:]]*//' | tr -d "\"' " || true)"
if [ -z "$PROJECT_NAME" ]; then
    err "Could not read a package name from '$APP_ROOT/pubspec.yaml'."
    exit 1
fi

# --- 3. Normalize and validate the feature name -----------------------------------

# Helper to convert snake_case to PascalCase
to_pascal() {
    printf '%s' "$1" | awk -F_ '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1' OFS=""
}

# Helper to convert snake_case to camelCase
to_camel() {
    local pascal
    pascal="$(to_pascal "$1")"
    printf '%s%s' "$(printf '%s' "${pascal:0:1}" | tr '[:upper:]' '[:lower:]')" "${pascal:1}"
}

# Convert feature name to snake_case (preserves existing snake_case, normalizes camelCase)
FEATURE_SNAKE="$(printf '%s' "$FEATURE_NAME" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')"

if ! printf '%s' "$FEATURE_SNAKE" | grep -Eq '^[a-z][a-z0-9_]*$'; then
    err "'$FEATURE_NAME' is not a valid feature name (normalized: '$FEATURE_SNAKE')."
    err "Use snake_case or camelCase: lowercase letters, digits and underscores,"
    err "starting with a letter. Empty names, path separators, '..', punctuation"
    err "and invalid starting characters are rejected."
    exit 1
fi

DART_RESERVED_IDENTIFIERS="abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for get hide if implements import in interface is late library mixin new null on operator part required rethrow return sealed set show static super switch sync this throw true try typedef var void while with yield"
for reserved in $DART_RESERVED_IDENTIFIERS; do
    if [ "$FEATURE_SNAKE" = "$reserved" ]; then
        err "'$FEATURE_SNAKE' is a Dart reserved identifier and cannot be used as a feature name."
        exit 1
    fi
done

FEATURE_PASCAL="$(to_pascal "$FEATURE_SNAKE")"
FEATURE_CAMEL="$(to_camel "$FEATURE_SNAKE")"

# Localization keys for the generated screen. fstr.sh refuses keys that
# already exist (collision check happens before any write).
L10N_TITLE_KEY="${FEATURE_CAMEL}Title"
L10N_DATA_KEY="${FEATURE_CAMEL}Data"

# --- 4. Compute output paths; refuse existing targets ------------------------------

LIB_FEATURE_DIR="$APP_ROOT/lib/features/$FEATURE_SNAKE"
TEST_FEATURE_DIR="$APP_ROOT/test/features/$FEATURE_SNAKE"

for target in "$LIB_FEATURE_DIR" "$TEST_FEATURE_DIR"; do
    if [ -L "$target" ]; then
        err "Refusing to generate: '$target' exists and is a symlink."
        err "fgen never modifies an existing feature. Remove it or choose another name."
        exit 1
    fi
    if [ -e "$target" ]; then
        err "Refusing to generate: '$target' already exists."
        err "fgen never modifies an existing feature. Remove it or choose another name."
        exit 1
    fi
done

# --- 4b. Refuse localization key collisions BEFORE anything is written ------------
# The screen references '<feature>Title' and '<feature>Data'; fstr refuses to
# overwrite an existing key, but that refusal would only happen AFTER the
# feature files had been published. Checking the ARB files up front keeps a
# collision a clean refusal: nothing is staged, published, or generated.
for arb in "$APP_ROOT/lib/core/l10n/app_localizations_en.arb" \
           "$APP_ROOT/lib/core/l10n/app_localizations_fr.arb"; do
    for key in "$L10N_TITLE_KEY" "$L10N_DATA_KEY"; do
        if [ -f "$arb" ] && grep -Eq "\"${key}\"[[:space:]]*:" "$arb"; then
            err "Refusing to generate: localization key '$key' already exists in"
            err "$arb."
            err "fgen never overwrites localization keys. Choose another feature"
            err "name or rename the key, then re-run."
            exit 1
        fi
    done
done

echo -e "${BLUE}🚀 Generating boilerplate for feature: ${GREEN}$FEATURE_SNAKE${NC}"
echo -e "${BLUE}   Project: ${GREEN}$PROJECT_NAME${NC}"
echo -e "${BLUE}   App root: ${GREEN}$APP_ROOT${NC}"
echo -e "${BLUE}   Layout: ${GREEN}lean$( [ "$WITH_SERVICE" = true ] && printf ' + service' )$( [ "$WITH_DTO" = true ] && printf ' + dto' )${NC}"

# --- 5. Render into an owned temporary directory ------------------------------------

mkdir -p "$APP_ROOT/.dart_tool"
STAGE_ROOT="$(mktemp -d "$APP_ROOT/.dart_tool/flutterforge-fgen.XXXXXX")"
cleanup() {
    rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

STAGE_LIB="$STAGE_ROOT/lib/features/$FEATURE_SNAKE"
STAGE_TEST="$STAGE_ROOT/test/features/$FEATURE_SNAKE"

echo -e "${BLUE}📂 Rendering directories...${NC}"
# NOTE: every path is quoted and passed as a single argument. Do NOT collect
# the optional directories into an unquoted variable for word splitting — an
# app root containing spaces would silently create wrong directories and the
# later heredoc writes would fail with "No such file or directory".
mkdir -p \
    "$STAGE_LIB/data/datasources" \
    "$STAGE_LIB/data/repositories" \
    "$STAGE_LIB/domain/models" \
    "$STAGE_LIB/domain/repositories" \
    "$STAGE_LIB/presentation/bloc" \
    "$STAGE_LIB/presentation/screens" \
    "$STAGE_TEST/data/repositories" \
    "$STAGE_TEST/presentation/bloc" \
    "$STAGE_TEST/presentation/screens"
if [ "$WITH_DTO" = true ]; then
    mkdir -p "$STAGE_LIB/data/models" "$STAGE_TEST/data/models"
fi
if [ "$WITH_SERVICE" = true ]; then
    mkdir -p "$STAGE_LIB/domain/services" "$STAGE_TEST/domain/services"
fi

# --- 6. Domain Layer: Model (Freezed, lean: no JSON serialization) -------------------
# The domain model is the app's representation. Without --with-dto there is no
# transport schema to serialize against, so no fromJson/$...g.dart is emitted;
# add one only when the domain model itself must cross a persistence boundary.
cat > "$STAGE_LIB/domain/models/${FEATURE_SNAKE}.dart" <<EOF
import 'package:freezed_annotation/freezed_annotation.dart';

part '${FEATURE_SNAKE}.freezed.dart';

@freezed
sealed class ${FEATURE_PASCAL} with _\$${FEATURE_PASCAL} {
  const factory ${FEATURE_PASCAL}({
    required String id,
    @Default('') String name,
  }) = _${FEATURE_PASCAL};
}
EOF

# --- 7. Domain Layer: Repository Interface ---
cat > "$STAGE_LIB/domain/repositories/${FEATURE_SNAKE}_repository.dart" <<EOF
import 'package:fpdart/fpdart.dart';

import '../../../../core/models/failure.dart';
import '../models/${FEATURE_SNAKE}.dart';

abstract class I${FEATURE_PASCAL}Repository {
  Future<Either<Failure, ${FEATURE_PASCAL}>> getData();
}
EOF

# --- 8. Domain Layer: Service (only with --with-service) ------------------------------
if [ "$WITH_SERVICE" = true ]; then
    cat > "$STAGE_LIB/domain/services/${FEATURE_SNAKE}_service.dart" <<EOF
import 'package:fpdart/fpdart.dart';

import '../../../../core/models/failure.dart';
import '../models/${FEATURE_SNAKE}.dart';
import '../repositories/${FEATURE_SNAKE}_repository.dart';

/// PLACEHOLDER domain service.
///
/// A service earns its place by owning actual rules or coordination (see
/// CounterService in the template). Right now this class only forwards to the
/// repository: either grow it into real domain logic, or delete it and let
/// the cubit depend on I${FEATURE_PASCAL}Repository directly. A forwarding
/// service is NOT mandatory architecture.
class ${FEATURE_PASCAL}Service {
  final I${FEATURE_PASCAL}Repository _repository;

  ${FEATURE_PASCAL}Service(this._repository);

  Future<Either<Failure, ${FEATURE_PASCAL}>> getData() {
    return _repository.getData();
  }
}
EOF
fi

# --- 9. Data Layer: Data Source (interface + placeholder implementation) --------------
# The data source is the external-I/O seam. Without --with-dto the placeholder
# returns the DOMAIN model directly: there is no transport schema yet, so do
# not pretend this represents one. When a real transport appears, regenerate
# the layer with --with-dto or hand-write the DTO/conversion.
DATA_SOURCE_RETURN_TYPE="${FEATURE_PASCAL}"
DATA_SOURCE_CONSTRUCTION="const ${FEATURE_PASCAL}(id: '1', name: 'Placeholder')"
DATA_SOURCE_IMPORTS="import '../../domain/models/${FEATURE_SNAKE}.dart';"
DATA_SOURCE_RETURN_DOC="// Returns the domain model directly: the lean layout has no transport
    // representation. Replace this placeholder with real I/O (http, dio, a
    // database) when the feature gains an actual external dependency."
if [ "$WITH_DTO" = true ]; then
    DATA_SOURCE_RETURN_TYPE="${FEATURE_PASCAL}Dto"
    DATA_SOURCE_CONSTRUCTION="const ${FEATURE_PASCAL}Dto(id: '1', name: 'Placeholder')"
    DATA_SOURCE_IMPORTS="import '../models/${FEATURE_SNAKE}_dto.dart';"
    DATA_SOURCE_RETURN_DOC="// Returns the transport DTO; the repository maps it to the domain model
    // inside its guarded boundary."
fi
cat > "$STAGE_LIB/data/datasources/${FEATURE_SNAKE}_remote_datasource.dart" <<EOF
$DATA_SOURCE_IMPORTS

abstract class I${FEATURE_PASCAL}RemoteDataSource {
  Future<$DATA_SOURCE_RETURN_TYPE> getData();
}

class ${FEATURE_PASCAL}RemoteDataSource implements I${FEATURE_PASCAL}RemoteDataSource {
  @override
  Future<$DATA_SOURCE_RETURN_TYPE> getData() async {
    $DATA_SOURCE_RETURN_DOC
    // TODO: Implement the real remote call.
    return $DATA_SOURCE_CONSTRUCTION;
  }
}
EOF

# --- 10. Data Layer: DTO (only with --with-dto) ---------------------------------------
if [ "$WITH_DTO" = true ]; then
    cat > "$STAGE_LIB/data/models/${FEATURE_SNAKE}_dto.dart" <<EOF
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/models/${FEATURE_SNAKE}.dart';

part '${FEATURE_SNAKE}_dto.freezed.dart';
part '${FEATURE_SNAKE}_dto.g.dart';

/// Transport representation. The domain model does not know this class
/// exists: serialization and transport-specific shapes stay in the data
/// layer. Keep the conversion total and guarded — malformed payloads must
/// surface as typed failures at the repository boundary, never as exceptions
/// escaping into the domain.
@freezed
sealed class ${FEATURE_PASCAL}Dto with _\$${FEATURE_PASCAL}Dto {
  const factory ${FEATURE_PASCAL}Dto({
    required String id,
    required String name,
  }) = _${FEATURE_PASCAL}Dto;

  factory ${FEATURE_PASCAL}Dto.fromJson(Map<String, dynamic> json) =>
      _\$${FEATURE_PASCAL}DtoFromJson(json);

  const ${FEATURE_PASCAL}Dto._();

  ${FEATURE_PASCAL} toDomain() {
    return ${FEATURE_PASCAL}(
      id: id,
      name: name,
    );
  }
}
EOF
fi

# --- 11. Data Layer: Repository Implementation -----------------------------------------
# Always uses typed results and the shared exception mapper; the DTO→domain
# conversion (when present) stays inside the guarded boundary so malformed
# payloads become typed failures instead of escaping exceptions.
REPO_BODY_LINES="      final ${FEATURE_PASCAL} data = await _dataSource.getData();"
if [ "$WITH_DTO" = true ]; then
    REPO_BODY_LINES="      final ${FEATURE_PASCAL}Dto dto = await _dataSource.getData();
      // DTO conversion stays inside the guarded boundary: malformed payloads
      // become a typed failure instead of escaping as an exception.
      final ${FEATURE_PASCAL} data = dto.toDomain();"
fi
cat > "$STAGE_LIB/data/repositories/${FEATURE_SNAKE}_repository_impl.dart" <<EOF
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exception_mapper.dart';
import '../../../../core/models/failure.dart';
import '../../domain/repositories/${FEATURE_SNAKE}_repository.dart';
import '../../domain/models/${FEATURE_SNAKE}.dart';
import '../datasources/${FEATURE_SNAKE}_remote_datasource.dart';
EOF
if [ "$WITH_DTO" = true ]; then
    cat >> "$STAGE_LIB/data/repositories/${FEATURE_SNAKE}_repository_impl.dart" <<EOF
import '../models/${FEATURE_SNAKE}_dto.dart';
EOF
fi
cat >> "$STAGE_LIB/data/repositories/${FEATURE_SNAKE}_repository_impl.dart" <<EOF

class ${FEATURE_PASCAL}Repository implements I${FEATURE_PASCAL}Repository {
  final I${FEATURE_PASCAL}RemoteDataSource _dataSource;

  ${FEATURE_PASCAL}Repository(this._dataSource);

  @override
  Future<Either<Failure, ${FEATURE_PASCAL}>> getData() async {
    try {
$REPO_BODY_LINES
      return Right<Failure, ${FEATURE_PASCAL}>(data);
    } catch (e, st) {
      // Logs the error and stack trace once, at the mapping boundary.
      return Left<Failure, ${FEATURE_PASCAL}>(
        mapExceptionToFailure(e, stackTrace: st, tag: '${FEATURE_PASCAL}Repository'),
      );
    }
  }
}
EOF

# --- 12. Presentation Layer: State ---
cat > "$STAGE_LIB/presentation/bloc/${FEATURE_SNAKE}_state.dart" <<EOF
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/models/failure.dart';
import '../../domain/models/${FEATURE_SNAKE}.dart';

part '${FEATURE_SNAKE}_state.freezed.dart';

/// Union-state idiom for a load-lifecycle screen — see the
/// flutter-architecture skill for when to use this vs a flat state.
/// The error state carries the typed Failure, not a message: the UI derives
/// text at build time via core/l10n/failure_localization.dart.
@freezed
sealed class ${FEATURE_PASCAL}State with _\$${FEATURE_PASCAL}State {
  const factory ${FEATURE_PASCAL}State.initial() = _Initial;
  const factory ${FEATURE_PASCAL}State.loading() = _Loading;
  const factory ${FEATURE_PASCAL}State.loaded(${FEATURE_PASCAL} data) = _Loaded;
  const factory ${FEATURE_PASCAL}State.error({required Failure failure}) = _Error;
}
EOF

# --- 13. Presentation Layer: Cubit ------------------------------------------------------
# The cubit depends on the repository interface directly (lean default) or on
# the domain service (--with-service) — never on another cubit.
CUBIT_DEP_TYPE="I${FEATURE_PASCAL}Repository"
CUBIT_DEP_IMPORT="'../../domain/repositories/${FEATURE_SNAKE}_repository.dart'"
if [ "$WITH_SERVICE" = true ]; then
    CUBIT_DEP_TYPE="${FEATURE_PASCAL}Service"
    CUBIT_DEP_IMPORT="'../../domain/services/${FEATURE_SNAKE}_service.dart'"
fi
cat > "$STAGE_LIB/presentation/bloc/${FEATURE_SNAKE}_cubit.dart" <<EOF
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/models/failure.dart';
import '../../domain/models/${FEATURE_SNAKE}.dart';
import $CUBIT_DEP_IMPORT;
import '${FEATURE_SNAKE}_state.dart';

class ${FEATURE_PASCAL}Cubit extends Cubit<${FEATURE_PASCAL}State> {
  final $CUBIT_DEP_TYPE _source;

  /// Monotonically increasing identifier for read requests (latest-request-wins):
  /// each accepted request captures its identifier before awaiting, and after
  /// the await only the newest request may emit.
  int _requestId = 0;

  ${FEATURE_PASCAL}Cubit(this._source) : super(const ${FEATURE_PASCAL}State.initial());

  Future<void> loadData() async {
    // A request invoked after close must not emit (emit on a closed cubit
    // throws a StateError).
    if (isClosed) {
      return;
    }

    final int requestId = ++_requestId;
    emit(const ${FEATURE_PASCAL}State.loading());

    // Note: ignoring a stale result does not cancel its underlying network
    // request. Add transport-level cancellation only if a data source needs it.
    final Either<Failure, ${FEATURE_PASCAL}> result = await _source.getData();

    // Check before processing EITHER a success or a failure: after close,
    // emitting throws; and a stale (superseded) result must never overwrite a
    // newer request's state.
    if (isClosed || requestId != _requestId) {
      return;
    }

    result.fold(
      (Failure failure) => emit(${FEATURE_PASCAL}State.error(failure: failure)),
      (${FEATURE_PASCAL} data) => emit(${FEATURE_PASCAL}State.loaded(data)),
    );
  }
}
EOF

# --- 14. Presentation Layer: Screen ------------------------------------------------------
# A single screen widget: it has one responsibility (render the load
# lifecycle), so there is no Screen→View forwarding pair. The route provides
# the cubit; the screen is a pure consumer.
cat > "$STAGE_LIB/presentation/screens/${FEATURE_SNAKE}_screen.dart" <<EOF
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/l10n/failure_localization.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/models/failure.dart';
import '../../domain/models/${FEATURE_SNAKE}.dart';
import '../bloc/${FEATURE_SNAKE}_cubit.dart';
import '../bloc/${FEATURE_SNAKE}_state.dart';

/// Single-widget screen — it renders one load lifecycle and has no distinct
/// sub-responsibility, so there is no separate View widget to forward to.
class ${FEATURE_PASCAL}Screen extends StatelessWidget {
  const ${FEATURE_PASCAL}Screen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.$L10N_TITLE_KEY)),
      body: BlocBuilder<${FEATURE_PASCAL}Cubit, ${FEATURE_PASCAL}State>(
        builder: (BuildContext context, ${FEATURE_PASCAL}State state) {
          return state.when(
            initial: () => const Center(child: CircularProgressIndicator()),
            loading: () => const Center(child: CircularProgressIndicator()),
            loaded: (${FEATURE_PASCAL} data) =>
                Center(child: Text(l10n.$L10N_DATA_KEY(data.name))),
            // Localized at build time from the failure category; diagnostics
            // carried by the failure are never displayed.
            error: (Failure failure) => Center(
              child: Text(localizeFailure(AppLocalizations.of(context), failure)),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.read<${FEATURE_PASCAL}Cubit>().loadData(),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
EOF

# --- 15. Test Layer: Repository Implementation Test (failure + mapping) -------------------
cat > "$STAGE_TEST/data/repositories/${FEATURE_SNAKE}_repository_impl_test.dart" <<EOF
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:$PROJECT_NAME/core/models/failure.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/data/datasources/${FEATURE_SNAKE}_remote_datasource.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/data/repositories/${FEATURE_SNAKE}_repository_impl.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/models/${FEATURE_SNAKE}.dart';
EOF
if [ "$WITH_DTO" = true ]; then
    cat >> "$STAGE_TEST/data/repositories/${FEATURE_SNAKE}_repository_impl_test.dart" <<EOF
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/data/models/${FEATURE_SNAKE}_dto.dart';
EOF
fi
cat >> "$STAGE_TEST/data/repositories/${FEATURE_SNAKE}_repository_impl_test.dart" <<EOF

class Mock${FEATURE_PASCAL}RemoteDataSource extends Mock
    implements I${FEATURE_PASCAL}RemoteDataSource {}

/// Repository tests prove three things: the data source is called, the
/// result is mapped to the domain type, and failures are TRANSLATED to typed
/// [Failure] values instead of escaping as exceptions.
void main() {
  group('${FEATURE_PASCAL}Repository', () {
    late ${FEATURE_PASCAL}Repository repository;
    late Mock${FEATURE_PASCAL}RemoteDataSource mockDataSource;

    setUp(() {
      mockDataSource = Mock${FEATURE_PASCAL}RemoteDataSource();
      repository = ${FEATURE_PASCAL}Repository(mockDataSource);
    });

    test('returns the mapped domain data on success', () async {
EOF
if [ "$WITH_DTO" = true ]; then
    cat >> "$STAGE_TEST/data/repositories/${FEATURE_SNAKE}_repository_impl_test.dart" <<EOF
      when(() => mockDataSource.getData()).thenAnswer(
        (_) async => const ${FEATURE_PASCAL}Dto(id: '1', name: 'Test'),
      );
EOF
else
    cat >> "$STAGE_TEST/data/repositories/${FEATURE_SNAKE}_repository_impl_test.dart" <<EOF
      when(() => mockDataSource.getData()).thenAnswer(
        (_) async => const ${FEATURE_PASCAL}(id: '1', name: 'Test'),
      );
EOF
fi
cat >> "$STAGE_TEST/data/repositories/${FEATURE_SNAKE}_repository_impl_test.dart" <<EOF

      final Either<Failure, ${FEATURE_PASCAL}> result = await repository.getData();

      verify(() => mockDataSource.getData()).called(1);
      result.fold(
        (_) => fail('Expected Right(${FEATURE_PASCAL})'),
        (${FEATURE_PASCAL} data) {
          expect(data.id, '1');
          expect(data.name, 'Test');
        },
      );
    });

    test('translates an unexpected exception into Failure.unexpected', () async {
      when(() => mockDataSource.getData()).thenThrow(StateError('boom'));

      final Either<Failure, ${FEATURE_PASCAL}> result = await repository.getData();

      result.fold(
        (Failure failure) => expect(failure, const Failure.unexpected()),
        (_) => fail('Expected Left(Failure.unexpected)'),
      );
    });

    test('translates a timeout into Failure.networkError', () async {
      when(() => mockDataSource.getData())
          .thenThrow(TimeoutException('timed out'));

      final Either<Failure, ${FEATURE_PASCAL}> result = await repository.getData();

      result.fold(
        (Failure failure) => expect(failure, const Failure.networkError()),
        (_) => fail('Expected Left(Failure.networkError)'),
      );
    });
  });
}
EOF

# --- 16. Test Layer: DTO Mapping Test (only with --with-dto) -------------------------------
if [ "$WITH_DTO" = true ]; then
    cat > "$STAGE_TEST/data/models/${FEATURE_SNAKE}_dto_test.dart" <<EOF
import 'package:flutter_test/flutter_test.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/data/models/${FEATURE_SNAKE}_dto.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/models/${FEATURE_SNAKE}.dart';

/// DTO tests pin the transport contract: JSON round-trips and the
/// DTO→domain conversion stay correct when the schema evolves.
void main() {
  group('${FEATURE_PASCAL}Dto', () {
    const Map<String, dynamic> json = <String, dynamic>{
      'id': '1',
      'name': 'Test',
    };

    test('deserializes from JSON', () {
      final ${FEATURE_PASCAL}Dto dto = ${FEATURE_PASCAL}Dto.fromJson(json);
      expect(dto.id, '1');
      expect(dto.name, 'Test');
    });

    test('serializes to JSON (round trip)', () {
      final ${FEATURE_PASCAL}Dto dto = ${FEATURE_PASCAL}Dto.fromJson(json);
      expect(dto.toJson(), json);
    });

    test('toDomain maps every field', () {
      const ${FEATURE_PASCAL}Dto dto = ${FEATURE_PASCAL}Dto(id: '1', name: 'Test');
      final ${FEATURE_PASCAL} domain = dto.toDomain();
      expect(domain.id, '1');
      expect(domain.name, 'Test');
    });
  });
}
EOF
fi

# --- 16b. Test Layer: Service Test (only with --with-service) ---------------------------
if [ "$WITH_SERVICE" = true ]; then
    cat > "$STAGE_TEST/domain/services/${FEATURE_SNAKE}_service_test.dart" <<EOF
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:$PROJECT_NAME/core/models/failure.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/models/${FEATURE_SNAKE}.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/repositories/${FEATURE_SNAKE}_repository.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/services/${FEATURE_SNAKE}_service.dart';

class Mock${FEATURE_PASCAL}Repository extends Mock
    implements I${FEATURE_PASCAL}Repository {}

/// PLACEHOLDER service tests: they only pin the current forwarding behavior.
/// When the service gains actual rules/coordination, replace them with tests
/// of that logic; if the service is removed instead, delete this file with it.
void main() {
  group('${FEATURE_PASCAL}Service', () {
    late ${FEATURE_PASCAL}Service service;
    late Mock${FEATURE_PASCAL}Repository mockRepository;

    setUp(() {
      mockRepository = Mock${FEATURE_PASCAL}Repository();
      service = ${FEATURE_PASCAL}Service(mockRepository);
    });

    test('returns the repository result on success', () async {
      when(() => mockRepository.getData()).thenAnswer(
        (_) async => const Right<Failure, ${FEATURE_PASCAL}>(${FEATURE_PASCAL}(id: '1', name: 'Test')),
      );

      final Either<Failure, ${FEATURE_PASCAL}> result = await service.getData();

      verify(() => mockRepository.getData()).called(1);
      result.fold(
        (_) => fail('Expected Right(${FEATURE_PASCAL})'),
        (${FEATURE_PASCAL} data) => expect(data.id, '1'),
      );
    });

    test('forwards failures untouched', () async {
      when(() => mockRepository.getData()).thenAnswer(
        (_) async => const Left<Failure, ${FEATURE_PASCAL}>(Failure.networkError()),
      );

      final Either<Failure, ${FEATURE_PASCAL}> result = await service.getData();

      result.fold(
        (Failure failure) => expect(failure, const Failure.networkError()),
        (_) => fail('Expected Left(Failure.networkError)'),
      );
    });
  });
}
EOF
fi

# --- 17. Test Layer: Cubit Test -------------------------------------------------------------
CUBIT_TEST_MOCK_TYPE="I${FEATURE_PASCAL}Repository"
CUBIT_TEST_MOCK_IMPORT="package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/repositories/${FEATURE_SNAKE}_repository.dart"
if [ "$WITH_SERVICE" = true ]; then
    CUBIT_TEST_MOCK_TYPE="${FEATURE_PASCAL}Service"
    CUBIT_TEST_MOCK_IMPORT="package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/services/${FEATURE_SNAKE}_service.dart"
fi
cat > "$STAGE_TEST/presentation/bloc/${FEATURE_SNAKE}_cubit_test.dart" <<EOF
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:$PROJECT_NAME/core/models/failure.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/models/${FEATURE_SNAKE}.dart';
import '$CUBIT_TEST_MOCK_IMPORT';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/presentation/bloc/${FEATURE_SNAKE}_cubit.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/presentation/bloc/${FEATURE_SNAKE}_state.dart';

class Mock${CUBIT_TEST_MOCK_TYPE} extends Mock implements ${CUBIT_TEST_MOCK_TYPE} {}

/// Tests for the ${FEATURE_PASCAL}Cubit, including the deliberate async
/// lifecycle semantics: latest-request-wins reads, no emission after close,
/// and stale failures that cannot overwrite newer successes.
void main() {
  group('${FEATURE_PASCAL}Cubit', () {
    late ${FEATURE_PASCAL}Cubit cubit;
    late Mock${CUBIT_TEST_MOCK_TYPE} mockSource;

    setUp(() {
      mockSource = Mock${CUBIT_TEST_MOCK_TYPE}();
      cubit = ${FEATURE_PASCAL}Cubit(mockSource);
    });

    tearDown(() {
      cubit.close();
    });

    test('initial state is initial', () {
      expect(cubit.state, const ${FEATURE_PASCAL}State.initial());
    });

    blocTest<${FEATURE_PASCAL}Cubit, ${FEATURE_PASCAL}State>(
      'emits [loading, loaded] when loadData is successful',
      build: () {
        when(() => mockSource.getData()).thenAnswer(
          (_) async => const Right<Failure, ${FEATURE_PASCAL}>(${FEATURE_PASCAL}(id: '1', name: 'Test')),
        );
        return cubit;
      },
      act: (${FEATURE_PASCAL}Cubit cubit) => cubit.loadData(),
      expect: () => <${FEATURE_PASCAL}State>[
        const ${FEATURE_PASCAL}State.loading(),
        const ${FEATURE_PASCAL}State.loaded(${FEATURE_PASCAL}(id: '1', name: 'Test')),
      ],
    );

    blocTest<${FEATURE_PASCAL}Cubit, ${FEATURE_PASCAL}State>(
      'emits [loading, error] when loadData fails',
      build: () {
        when(() => mockSource.getData()).thenAnswer(
          (_) async => const Left<Failure, ${FEATURE_PASCAL}>(Failure.networkError()),
        );
        return cubit;
      },
      act: (${FEATURE_PASCAL}Cubit cubit) => cubit.loadData(),
      expect: () => <${FEATURE_PASCAL}State>[
        const ${FEATURE_PASCAL}State.loading(),
        const ${FEATURE_PASCAL}State.error(failure: Failure.networkError()),
      ],
    );

    test('a success completing after close does not emit or throw', () async {
      final Completer<Either<Failure, ${FEATURE_PASCAL}>> completer =
          Completer<Either<Failure, ${FEATURE_PASCAL}>>();
      when(() => mockSource.getData()).thenAnswer((_) => completer.future);

      final List<${FEATURE_PASCAL}State> emissions = <${FEATURE_PASCAL}State>[];
      final StreamSubscription<${FEATURE_PASCAL}State> subscription =
          cubit.stream.listen(emissions.add);

      final Future<void> load = cubit.loadData();
      await cubit.close();
      completer.complete(
        const Right<Failure, ${FEATURE_PASCAL}>(${FEATURE_PASCAL}(id: '1', name: 'Late')),
      );

      // Does not throw (emit on a closed cubit would).
      await load;
      // Flush the microtask queue so the broadcast state stream delivers
      // queued emissions before the subscription is cancelled.
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(emissions, <${FEATURE_PASCAL}State>[const ${FEATURE_PASCAL}State.loading()]);
    });

    test('a failure completing after close does not emit or throw', () async {
      final Completer<Either<Failure, ${FEATURE_PASCAL}>> completer =
          Completer<Either<Failure, ${FEATURE_PASCAL}>>();
      when(() => mockSource.getData()).thenAnswer((_) => completer.future);

      final List<${FEATURE_PASCAL}State> emissions = <${FEATURE_PASCAL}State>[];
      final StreamSubscription<${FEATURE_PASCAL}State> subscription =
          cubit.stream.listen(emissions.add);

      final Future<void> load = cubit.loadData();
      await cubit.close();
      completer.complete(
        const Left<Failure, ${FEATURE_PASCAL}>(Failure.unauthorized()),
      );

      await load;
      // Flush the microtask queue so the broadcast state stream delivers
      // queued emissions before the subscription is cancelled.
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(emissions, <${FEATURE_PASCAL}State>[const ${FEATURE_PASCAL}State.loading()]);
    });

    test('two reads completed in reverse order retain the newer result', () async {
      final Completer<Either<Failure, ${FEATURE_PASCAL}>> first =
          Completer<Either<Failure, ${FEATURE_PASCAL}>>();
      final Completer<Either<Failure, ${FEATURE_PASCAL}>> second =
          Completer<Either<Failure, ${FEATURE_PASCAL}>>();
      int call = 0;
      when(() => mockSource.getData()).thenAnswer((_) {
        call++;
        return call == 1 ? first.future : second.future;
      });

      final List<${FEATURE_PASCAL}State> emissions = <${FEATURE_PASCAL}State>[];
      final StreamSubscription<${FEATURE_PASCAL}State> subscription =
          cubit.stream.listen(emissions.add);

      final Future<void> firstLoad = cubit.loadData();
      final Future<void> secondLoad = cubit.loadData();

      // The newer request completes first; then the stale older one resolves.
      second.complete(
        const Right<Failure, ${FEATURE_PASCAL}>(${FEATURE_PASCAL}(id: '2', name: 'Newer')),
      );
      await secondLoad;
      first.complete(
        const Right<Failure, ${FEATURE_PASCAL}>(${FEATURE_PASCAL}(id: '1', name: 'Older')),
      );
      await firstLoad;

      // Flush the microtask queue so the broadcast state stream delivers
      // queued emissions before the subscription is cancelled.
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(emissions.last, const ${FEATURE_PASCAL}State.loaded(${FEATURE_PASCAL}(id: '2', name: 'Newer')));
    });

    test('a stale failure cannot overwrite a newer success', () async {
      final Completer<Either<Failure, ${FEATURE_PASCAL}>> first =
          Completer<Either<Failure, ${FEATURE_PASCAL}>>();
      final Completer<Either<Failure, ${FEATURE_PASCAL}>> second =
          Completer<Either<Failure, ${FEATURE_PASCAL}>>();
      int call = 0;
      when(() => mockSource.getData()).thenAnswer((_) {
        call++;
        return call == 1 ? first.future : second.future;
      });

      final List<${FEATURE_PASCAL}State> emissions = <${FEATURE_PASCAL}State>[];
      final StreamSubscription<${FEATURE_PASCAL}State> subscription =
          cubit.stream.listen(emissions.add);

      final Future<void> firstLoad = cubit.loadData();
      final Future<void> secondLoad = cubit.loadData();

      second.complete(
        const Right<Failure, ${FEATURE_PASCAL}>(${FEATURE_PASCAL}(id: '2', name: 'Newer')),
      );
      await secondLoad;
      first.complete(
        const Left<Failure, ${FEATURE_PASCAL}>(Failure.networkError()),
      );
      await firstLoad;

      // Flush the microtask queue so the broadcast state stream delivers
      // queued emissions before the subscription is cancelled.
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(
        emissions.last,
        isNot(const ${FEATURE_PASCAL}State.error(failure: Failure.networkError())),
      );
      expect(emissions.last, const ${FEATURE_PASCAL}State.loaded(${FEATURE_PASCAL}(id: '2', name: 'Newer')));
    });

    test('a failed current request is followed by a successful retry', () async {
      final Completer<Either<Failure, ${FEATURE_PASCAL}>> first =
          Completer<Either<Failure, ${FEATURE_PASCAL}>>();
      when(() => mockSource.getData()).thenAnswer((_) => first.future);

      final List<${FEATURE_PASCAL}State> emissions = <${FEATURE_PASCAL}State>[];
      final StreamSubscription<${FEATURE_PASCAL}State> subscription =
          cubit.stream.listen(emissions.add);

      final Future<void> failedLoad = cubit.loadData();
      first.complete(
        const Left<Failure, ${FEATURE_PASCAL}>(Failure.networkError()),
      );
      await failedLoad;

      when(() => mockSource.getData()).thenAnswer(
        (_) async => const Right<Failure, ${FEATURE_PASCAL}>(${FEATURE_PASCAL}(id: '2', name: 'Retry')),
      );
      await cubit.loadData();

      // Flush the microtask queue so the broadcast state stream delivers
      // queued emissions before the subscription is cancelled.
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(emissions, <${FEATURE_PASCAL}State>[
        const ${FEATURE_PASCAL}State.loading(),
        const ${FEATURE_PASCAL}State.error(failure: Failure.networkError()),
        const ${FEATURE_PASCAL}State.loading(),
        const ${FEATURE_PASCAL}State.loaded(${FEATURE_PASCAL}(id: '2', name: 'Retry')),
      ]);
    });
  });
}
EOF

# --- 18. Test Layer: Screen Widget Test ---------------------------------------------------
cat > "$STAGE_TEST/presentation/screens/${FEATURE_SNAKE}_screen_test.dart" <<EOF
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$PROJECT_NAME/core/l10n/generated/app_localizations.dart';
import 'package:$PROJECT_NAME/core/models/failure.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/models/${FEATURE_SNAKE}.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/presentation/bloc/${FEATURE_SNAKE}_cubit.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/presentation/bloc/${FEATURE_SNAKE}_state.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/presentation/screens/${FEATURE_SNAKE}_screen.dart';

/// Fake cubit so tests can push states without driving the real repository.
class Fake${FEATURE_PASCAL}Cubit extends Cubit<${FEATURE_PASCAL}State>
    implements ${FEATURE_PASCAL}Cubit {
  Fake${FEATURE_PASCAL}Cubit() : super(const ${FEATURE_PASCAL}State.initial());

  int loadCalls = 0;

  void pushState(${FEATURE_PASCAL}State nextState) => emit(nextState);

  @override
  Future<void> loadData() async {
    loadCalls++;
  }
}

/// Widget tests for the generated screen: each state branch renders, the
/// failure category is localized (never a raw exception string), and the
/// refresh action reaches the cubit.
void main() {
  Widget buildTestableWidget(
    Widget child, {
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: child,
    );
  }

  testWidgets('shows a spinner in the initial and loading states', (
    WidgetTester tester,
  ) async {
    final Fake${FEATURE_PASCAL}Cubit cubit = Fake${FEATURE_PASCAL}Cubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      buildTestableWidget(
        BlocProvider<${FEATURE_PASCAL}Cubit>.value(
          value: cubit,
          child: const ${FEATURE_PASCAL}Screen(),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    cubit.pushState(const ${FEATURE_PASCAL}State.loading());
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders the loaded data', (WidgetTester tester) async {
    final Fake${FEATURE_PASCAL}Cubit cubit = Fake${FEATURE_PASCAL}Cubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      buildTestableWidget(
        BlocProvider<${FEATURE_PASCAL}Cubit>.value(
          value: cubit,
          child: const ${FEATURE_PASCAL}Screen(),
        ),
      ),
    );

    cubit.pushState(
      const ${FEATURE_PASCAL}State.loaded(${FEATURE_PASCAL}(id: '1', name: 'Test')),
    );
    await tester.pump();

    // The data line is localized with a {name} placeholder (English below).
    expect(find.text('Data: Test'), findsOneWidget);
  });

  testWidgets('displays the localized failure and retries on failure', (
    WidgetTester tester,
  ) async {
    final Fake${FEATURE_PASCAL}Cubit cubit = Fake${FEATURE_PASCAL}Cubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      buildTestableWidget(
        BlocProvider<${FEATURE_PASCAL}Cubit>.value(
          value: cubit,
          child: const ${FEATURE_PASCAL}Screen(),
        ),
      ),
    );

    cubit.pushState(
      const ${FEATURE_PASCAL}State.error(failure: Failure.networkError()),
    );
    await tester.pump();

    // The category is localized (English), not a raw exception string.
    expect(
      find.text('Network error. Please check your connection.'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    expect(cubit.loadCalls, 1);
  });
}
EOF

# --- 19. Publish -----------------------------------------------------------------

echo -e "${GREEN}✓ Feature $FEATURE_SNAKE files rendered. Publishing...${NC}"
mkdir -p "$APP_ROOT/lib/features" "$APP_ROOT/test/features"
mv "$STAGE_LIB" "$LIB_FEATURE_DIR"
mv "$STAGE_TEST" "$TEST_FEATURE_DIR"

echo -e "${GREEN}✓ Feature $FEATURE_SNAKE files generated!${NC}"

# --- 20. Localization keys (via fstr, with collision check) -------------------------

L10N_FAILED=false
FSTR="$APP_ROOT/scripts/fstr.sh"
if [ -f "$FSTR" ]; then
    echo -e "${BLUE}🌍 Adding localization keys ($L10N_TITLE_KEY, $L10N_DATA_KEY)...${NC}"
    if ! bash "$FSTR" "$L10N_TITLE_KEY" "Exemple $FEATURE_PASCAL" "$FEATURE_PASCAL example" "$APP_ROOT"; then
        L10N_FAILED=true
    fi
    if [ "$L10N_FAILED" = false ]; then
        if ! bash "$FSTR" "$L10N_DATA_KEY" "Données : {name}" "Data: {name}" "$APP_ROOT"; then
            L10N_FAILED=true
        fi
    fi
    if [ "$L10N_FAILED" = true ]; then
        err ""
        err "Localization failed (missing key, collision, or gen-l10n error). The new"
        err "feature '$FEATURE_SNAKE' was published but is INCOMPLETE: the screen"
        err "references the '$L10N_TITLE_KEY' and '$L10N_DATA_KEY' keys."
        err "Fix the error above, then re-run:"
        err "  bash scripts/fstr.sh $L10N_TITLE_KEY \"Exemple $FEATURE_PASCAL\" \"$FEATURE_PASCAL example\""
        err "  bash scripts/fstr.sh $L10N_DATA_KEY \"Données : {name}\" \"Data: {name}\""
        exit 1
    fi
else
    err "scripts/fstr.sh not found in this application. The screen references the"
    err "localization keys '$L10N_TITLE_KEY' and '$L10N_DATA_KEY' — add them before"
    err "the app compiles:"
    err "  bash scripts/fstr.sh $L10N_TITLE_KEY \"Exemple $FEATURE_PASCAL\" \"$FEATURE_PASCAL example\""
    err "  bash scripts/fstr.sh $L10N_DATA_KEY \"Données : {name}\" \"Data: {name}\""
    exit 1
fi

# --- 21. Auto-run Build Runner -----------------------------------------------------

echo -e "${BLUE}🔧 Running build_runner to generate Freezed code...${NC}"
if command -v dart &> /dev/null; then
    if ! (cd "$APP_ROOT" && dart run build_runner build --delete-conflicting-outputs); then
        err ""
        err "build_runner failed. The new feature '$FEATURE_SNAKE' was published but is INCOMPLETE."
        err "Published files: '$LIB_FEATURE_DIR' and '$TEST_FEATURE_DIR'."
        err "Fix the errors above, then re-run: dart run build_runner build --delete-conflicting-outputs"
        exit 1
    fi
    echo -e "${GREEN}✓ Code generation complete. No more analyze errors!${NC}"

    # Format ONLY the files this script just generated. Line wrapping depends
    # on the feature-name length, so the heredoc templates cannot be
    # formatter-exact for every name; this step makes them compliant for any
    # name. It never touches user files (fverify's format gate stays
    # non-mutating by construction).
    echo -e "${BLUE}🎨 Formatting the generated files...${NC}"
    if ! (cd "$APP_ROOT" && dart format "$LIB_FEATURE_DIR" "$TEST_FEATURE_DIR"); then
        err "dart format failed on the generated files. The feature was published"
        err "but is INCOMPLETE. Fix the errors above, then re-run:"
        err "  dart format '$LIB_FEATURE_DIR' '$TEST_FEATURE_DIR'"
        exit 1
    fi
else
    echo -e "${RED}⚠️  Warning: 'dart' command not found. Run build_runner manually.${NC}" >&2
fi

# --- 22. Next steps (DI + route wiring, per layout) ----------------------------------

echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "${BLUE}⚠️  IMPORTANT: a scaffold that passes its unit tests is NOT a routed feature.${NC}"
echo -e "It only appears in the app once the DI and route steps below are applied —"
echo -e "run ${GREEN}fverify${NC} after wiring to smoke-test it end to end."
echo ""
echo -e "1. Register dependencies in ${GREEN}lib/core/di/service_locator.dart${NC}:"
echo -e "   getIt.registerLazySingleton<I${FEATURE_PASCAL}RemoteDataSource>(() => ${FEATURE_PASCAL}RemoteDataSource());"
echo -e "   getIt.registerLazySingleton<I${FEATURE_PASCAL}Repository>(() => ${FEATURE_PASCAL}Repository(getIt<I${FEATURE_PASCAL}RemoteDataSource>()));"
if [ "$WITH_SERVICE" = true ]; then
    echo -e "   getIt.registerLazySingleton<${FEATURE_PASCAL}Service>(() => ${FEATURE_PASCAL}Service(getIt<I${FEATURE_PASCAL}Repository>()));"
    echo -e "   (${FEATURE_PASCAL}Service is a PLACEHOLDER: grow it into real coordination logic or remove it)"
    echo -e "   getIt.registerFactory<${FEATURE_PASCAL}Cubit>(() => ${FEATURE_PASCAL}Cubit(getIt<${FEATURE_PASCAL}Service>()));"
else
    echo -e "   getIt.registerFactory<${FEATURE_PASCAL}Cubit>(() => ${FEATURE_PASCAL}Cubit(getIt<I${FEATURE_PASCAL}Repository>()));"
fi
echo -e "2. Add the route in ${GREEN}lib/core/router/app_router.dart${NC} — the route provides the cubit:"
echo -e "   GoRoute("
echo -e "     path: Routes.${FEATURE_CAMEL},"
echo -e "     name: '${FEATURE_PASCAL}',"
echo -e "     builder: (context, state) => BlocProvider<${FEATURE_PASCAL}Cubit>("
echo -e "       create: (_) => getIt<${FEATURE_PASCAL}Cubit>()..loadData(),"
echo -e "       child: const ${FEATURE_PASCAL}Screen(),"
echo -e "     ),"
echo -e "   )"
echo -e "   ...and the constant in ${GREEN}lib/core/router/route_constants.dart${NC}:"
echo -e "   static const String ${FEATURE_CAMEL} = '/${FEATURE_SNAKE}';"
echo -e "3. Update ${GREEN}test/core/di/service_locator_test.dart${NC} with the new registrations."
echo -e "4. Replace the placeholder data source in ${GREEN}lib/features/$FEATURE_SNAKE/data/datasources/${FEATURE_SNAKE}_remote_datasource.dart${NC} with real I/O."
if [ "$WITH_DTO" = false ]; then
    echo -e "   The lean layout has no transport schema; when a real one appears, hand-write"
    echo -e "   the DTO + conversion (or use --with-dto on a scratch name as a reference)."
fi
if [ "$WITH_SERVICE" = true ]; then
    echo -e "5. ${FEATURE_PASCAL}Service must gain actual rules/coordination or be removed — a forwarding service is not mandatory architecture."
    echo -e "6. Run ${GREEN}fverify${NC} before finishing."
else
    echo -e "5. Run ${GREEN}fverify${NC} before finishing."
fi
echo ""
