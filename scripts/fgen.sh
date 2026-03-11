#!/usr/bin/env bash

# Script to generate a new feature boilerplate following FlutterForge clean architecture.
# Usage: ./scripts/fgen.sh <feature_name>

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Feature name is required${NC}"
    echo ""
    echo "Usage: $0 <feature_name>"
    echo "Example: $0 user_profile"
    echo "Example: $0 auth"
    exit 1
fi

FEATURE_NAME="$1"

# Helper to convert snake_case to PascalCase
to_pascal() {
    echo "$1" | awk -F_ '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1' OFS=""
}

# Helper to convert snake_case to camelCase
to_camel() {
    local pascal=$(to_pascal "$1")
    echo "$(echo "${pascal:0:1}" | tr '[:upper:]' '[:lower:]')${pascal:1}"
}

# Convert feature name to snake_case (basic)
FEATURE_SNAKE=$(echo "$FEATURE_NAME" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')
FEATURE_PASCAL=$(to_pascal "$FEATURE_SNAKE")
FEATURE_CAMEL=$(to_camel "$FEATURE_SNAKE")

# Get project name from pubspec.yaml
if [ -f "pubspec.yaml" ]; then
    PROJECT_NAME=$(grep "^name:" pubspec.yaml | sed 's/name: //' | tr -d ' ' | tr -d '"' | tr -d "'")
else
    PROJECT_NAME="my_flutter_app"
fi

echo -e "${BLUE}🚀 Generating boilerplate for feature: ${GREEN}$FEATURE_SNAKE${NC}"
echo -e "${BLUE}   Project: ${GREEN}$PROJECT_NAME${NC}"

# 1. Create directory structure
echo -e "${BLUE}📂 Creating directories...${NC}"
mkdir -p lib/features/$FEATURE_SNAKE/data/datasources
mkdir -p lib/features/$FEATURE_SNAKE/data/models
mkdir -p lib/features/$FEATURE_SNAKE/data/repositories
mkdir -p lib/features/$FEATURE_SNAKE/domain/models
mkdir -p lib/features/$FEATURE_SNAKE/domain/repositories
mkdir -p lib/features/$FEATURE_SNAKE/domain/services
mkdir -p lib/features/$FEATURE_SNAKE/presentation/bloc
mkdir -p lib/features/$FEATURE_SNAKE/presentation/screens
mkdir -p lib/features/$FEATURE_SNAKE/presentation/widgets

mkdir -p test/features/$FEATURE_SNAKE/presentation/bloc
mkdir -p test/features/$FEATURE_SNAKE/domain/services
mkdir -p test/features/$FEATURE_SNAKE/data/repositories

# 2. Domain Layer: Repository Interface
cat > lib/features/$FEATURE_SNAKE/domain/repositories/${FEATURE_SNAKE}_repository.dart <<EOF
import 'package:fpdart/fpdart.dart';
import '../../../../core/models/failure.dart';
import '../models/${FEATURE_SNAKE}.dart';

abstract class I${FEATURE_PASCAL}Repository {
  Future<Either<Failure, ${FEATURE_PASCAL}>> getData();
}
EOF

# 3. Domain Layer: Model (Freezed)
cat > lib/features/$FEATURE_SNAKE/domain/models/${FEATURE_SNAKE}.dart <<EOF
import 'package:freezed_annotation/freezed_annotation.dart';

part '${FEATURE_SNAKE}.freezed.dart';
part '${FEATURE_SNAKE}.g.dart';

@freezed
class ${FEATURE_PASCAL} with _\$${FEATURE_PASCAL} {
  const factory ${FEATURE_PASCAL}({
    required String id,
    @Default('') String name,
  }) = _${FEATURE_PASCAL};

  factory ${FEATURE_PASCAL}.fromJson(Map<String, dynamic> json) =>
      _\$${FEATURE_PASCAL}FromJson(json);
}
EOF

# 4. Domain Layer: Service
cat > lib/features/$FEATURE_SNAKE/domain/services/${FEATURE_SNAKE}_service.dart <<EOF
import 'package:fpdart/fpdart.dart';
import '../../../../core/models/failure.dart';
import '../repositories/${FEATURE_SNAKE}_repository.dart';
import '../models/${FEATURE_SNAKE}.dart';

class ${FEATURE_PASCAL}Service {
  final I${FEATURE_PASCAL}Repository _repository;

  ${FEATURE_PASCAL}Service(this._repository);

  Future<Either<Failure, ${FEATURE_PASCAL}>> getData() {
    return _repository.getData();
  }
}
EOF

# 5. Data Layer: Data Source Interface
cat > lib/features/$FEATURE_SNAKE/data/datasources/${FEATURE_SNAKE}_remote_datasource.dart <<EOF
import '../models/${FEATURE_SNAKE}_dto.dart';

abstract class I${FEATURE_PASCAL}RemoteDataSource {
  Future<${FEATURE_PASCAL}Dto> getData();
}

class ${FEATURE_PASCAL}RemoteDataSource implements I${FEATURE_PASCAL}RemoteDataSource {
  @override
  Future<${FEATURE_PASCAL}Dto> getData() async {
    // TODO: Implement remote call
    return const ${FEATURE_PASCAL}Dto(id: '1', name: 'Placeholder');
  }
}
EOF

# 6. Data Layer: DTO
cat > lib/features/$FEATURE_SNAKE/data/models/${FEATURE_SNAKE}_dto.dart <<EOF
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/models/${FEATURE_SNAKE}.dart';

part '${FEATURE_SNAKE}_dto.freezed.dart';
part '${FEATURE_SNAKE}_dto.g.dart';

@freezed
class ${FEATURE_PASCAL}Dto with _\$${FEATURE_PASCAL}Dto {
  const factory ${FEATURE_PASCAL}Dto({
    required String id,
    required String name,
  }) = _${FEATURE_PASCAL}Dto;

  factory ${FEATURE_PASCAL}Dto.fromJson(Map<String, dynamic> json) =>
      _\$${FEATURE_PASCAL}DtoFromJson(json);

  factory ${FEATURE_PASCAL}Dto.fromDomain(${FEATURE_PASCAL} domain) {
    return ${FEATURE_PASCAL}Dto(
      id: domain.id,
      name: domain.name,
    );
  }

  const ${FEATURE_PASCAL}Dto._();

  ${FEATURE_PASCAL} toDomain() {
    return ${FEATURE_PASCAL}(
      id: id,
      name: name,
    );
  }
}
EOF

# 7. Data Layer: Repository Implementation
cat > lib/features/$FEATURE_SNAKE/data/repositories/${FEATURE_SNAKE}_repository_impl.dart <<EOF
import 'package:fpdart/fpdart.dart';
import '../../../../core/models/failure.dart';
import '../../domain/repositories/${FEATURE_SNAKE}_repository.dart';
import '../../domain/models/${FEATURE_SNAKE}.dart';
import '../datasources/${FEATURE_SNAKE}_remote_datasource.dart';
import '../models/${FEATURE_SNAKE}_dto.dart';

class ${FEATURE_PASCAL}Repository implements I${FEATURE_PASCAL}Repository {
  final I${FEATURE_PASCAL}RemoteDataSource _dataSource;

  ${FEATURE_PASCAL}Repository(this._dataSource);

  @override
  Future<Either<Failure, ${FEATURE_PASCAL}>> getData() async {
    try {
      final dto = await _dataSource.getData();
      return Right(dto.toDomain());
    } catch (e) {
      return Left(Failure.serverError(message: e.toString()));
    }
  }
}
EOF

# 8. Presentation Layer: State
cat > lib/features/$FEATURE_SNAKE/presentation/bloc/${FEATURE_SNAKE}_state.dart <<EOF
library;

import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/models/${FEATURE_SNAKE}.dart';

part '${FEATURE_SNAKE}_state.freezed.dart';

@freezed
sealed class ${FEATURE_PASCAL}State with _\$${FEATURE_PASCAL}State {
  const factory ${FEATURE_PASCAL}State.initial() = _Initial;
  const factory ${FEATURE_PASCAL}State.loading() = _Loading;
  const factory ${FEATURE_PASCAL}State.loaded(${FEATURE_PASCAL} data) = _Loaded;
  const factory ${FEATURE_PASCAL}State.error(String message) = _Error;
}
EOF

# 9. Presentation Layer: Cubit
cat > lib/features/$FEATURE_SNAKE/presentation/bloc/${FEATURE_SNAKE}_cubit.dart <<EOF
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/services/${FEATURE_SNAKE}_service.dart';
import '${FEATURE_SNAKE}_state.dart';

class ${FEATURE_PASCAL}Cubit extends Cubit<${FEATURE_PASCAL}State> {
  final ${FEATURE_PASCAL}Service _service;

  ${FEATURE_PASCAL}Cubit(this._service) : super(const ${FEATURE_PASCAL}State.initial());

  Future<void> loadData() async {
    emit(const ${FEATURE_PASCAL}State.loading());
    final result = await _service.getData();
    result.fold(
      (failure) => emit(${FEATURE_PASCAL}State.error(failure.message)),
      (data) => emit(${FEATURE_PASCAL}State.loaded(data)),
    );
  }
}
EOF

# 10. Presentation Layer: Screen
cat > lib/features/$FEATURE_SNAKE/presentation/screens/${FEATURE_SNAKE}_screen.dart <<EOF
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/${FEATURE_SNAKE}_cubit.dart';
import '../bloc/${FEATURE_SNAKE}_state.dart';

class ${FEATURE_PASCAL}Screen extends StatelessWidget {
  const ${FEATURE_PASCAL}Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('${FEATURE_PASCAL}'),
      ),
      body: BlocBuilder<${FEATURE_PASCAL}Cubit, ${FEATURE_PASCAL}State>(
        builder: (context, state) {
          return state.when(
            initial: () => const Center(child: Text('Initial')),
            loading: () => const Center(child: CircularProgressIndicator()),
            loaded: (data) => Center(child: Text('Data: \${data.name}')),
            error: (message) => Center(child: Text('Error: \$message')),
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

# 11. Test Layer: Cubit Test
cat > test/features/$FEATURE_SNAKE/presentation/bloc/${FEATURE_SNAKE}_cubit_test.dart <<EOF
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:$PROJECT_NAME/core/models/failure.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/models/${FEATURE_SNAKE}.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/services/${FEATURE_SNAKE}_service.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/presentation/bloc/${FEATURE_SNAKE}_cubit.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/presentation/bloc/${FEATURE_SNAKE}_state.dart';

class Mock${FEATURE_PASCAL}Service extends Mock implements ${FEATURE_PASCAL}Service {}

void main() {
  group('${FEATURE_PASCAL}Cubit', () {
    late ${FEATURE_PASCAL}Cubit cubit;
    late Mock${FEATURE_PASCAL}Service mockService;

    setUp(() {
      mockService = Mock${FEATURE_PASCAL}Service();
      cubit = ${FEATURE_PASCAL}Cubit(mockService);
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
        when(() => mockService.getData()).thenAnswer(
          (_) async => const Right(${FEATURE_PASCAL}(id: '1', name: 'Test')),
        );
        return cubit;
      },
      act: (cubit) => cubit.loadData(),
      expect: () => [
        const ${FEATURE_PASCAL}State.loading(),
        const ${FEATURE_PASCAL}State.loaded(${FEATURE_PASCAL}(id: '1', name: 'Test')),
      ],
    );

    blocTest<${FEATURE_PASCAL}Cubit, ${FEATURE_PASCAL}State>(
      'emits [loading, error] when loadData fails',
      build: () {
        when(() => mockService.getData()).thenAnswer(
          (_) async => const Left(Failure.serverError(message: 'Error')),
        );
        return cubit;
      },
      act: (cubit) => cubit.loadData(),
      expect: () => [
        const ${FEATURE_PASCAL}State.loading(),
        const ${FEATURE_PASCAL}State.error('Error'),
      ],
    );
  });
}
EOF

# 12. Test Layer: Service Test
cat > test/features/$FEATURE_SNAKE/domain/services/${FEATURE_SNAKE}_service_test.dart <<EOF
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:$PROJECT_NAME/core/models/failure.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/models/${FEATURE_SNAKE}.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/repositories/${FEATURE_SNAKE}_repository.dart';
import 'package:$PROJECT_NAME/features/$FEATURE_SNAKE/domain/services/${FEATURE_SNAKE}_service.dart';

class Mock${FEATURE_PASCAL}Repository extends Mock implements I${FEATURE_PASCAL}Repository {}

void main() {
  group('${FEATURE_PASCAL}Service', () {
    late ${FEATURE_PASCAL}Service service;
    late Mock${FEATURE_PASCAL}Repository mockRepository;

    setUp(() {
      mockRepository = Mock${FEATURE_PASCAL}Repository();
      service = ${FEATURE_PASCAL}Service(mockRepository);
    });

    test('getData calls repository.getData', () async {
      when(() => mockRepository.getData()).thenAnswer(
        (_) async => const Right(${FEATURE_PASCAL}(id: '1', name: 'Test')),
      );

      final result = await service.getData();

      expect(result.isRight(), true);
      verify(() => mockRepository.getData()).called(1);
    });
  });
}
EOF

echo -e "${GREEN}✓ Feature $FEATURE_SNAKE generated successfully!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "1. Register dependencies in ${GREEN}lib/core/di/service_locator.dart${NC}:"
echo -e "   ${BLUE}Data Sources:${NC}"
echo -e "   getIt.registerLazySingleton<I${FEATURE_PASCAL}RemoteDataSource>(() => ${FEATURE_PASCAL}RemoteDataSource());"
echo -e "   ${BLUE}Repositories:${NC}"
echo -e "   getIt.registerLazySingleton<I${FEATURE_PASCAL}Repository>(() => ${FEATURE_PASCAL}Repository(getIt<I${FEATURE_PASCAL}RemoteDataSource>()));"
echo -e "   ${BLUE}Services:${NC}"
echo -e "   getIt.registerLazySingleton<${FEATURE_PASCAL}Service>(() => ${FEATURE_PASCAL}Service(getIt<I${FEATURE_PASCAL}Repository>()));"
echo -e "   ${BLUE}Cubits:${NC}"
echo -e "   getIt.registerFactory<${FEATURE_PASCAL}Cubit>(() => ${FEATURE_PASCAL}Cubit(getIt<${FEATURE_PASCAL}Service>()));"
echo ""
echo -e "2. Add a route in ${GREEN}lib/core/router/app_router.dart${NC}"
echo -e "3. Run code generation:"
echo -e "   ${GREEN}dart run build_runner build --delete-conflicting-outputs${NC}"
echo ""
