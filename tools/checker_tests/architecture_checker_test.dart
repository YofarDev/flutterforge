@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/architecture_checker.dart';
import 'support/checker_expectations.dart';
import 'support/fixture_app.dart';

void main() {
  group('plain Dart VM', () {
    test('checker runs under `dart run` (normalized SDK path)', () async {
      final ProcessResult result = await Process.run('dart', <String>[
        'run',
        'test/checker_selftest/support/plain_vm_check.dart',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
  });

  group('base fixture', () {
    test(
      'valid DI, router, app composition and main bootstrap are accepted',
      () async {
        await expectClean(fixtureApp, 'the valid base fixture app');
      },
    );
  });

  group('inward dependencies', () {
    test('own domain importing own data — relative syntax', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': '''
import 'package:fpdart/fpdart.dart';

import '../../../../core/models/failure.dart';
import '../models/alpha_model.dart';
import '../repositories/i_alpha_repository.dart';
import '../../../alpha/data/datasources/alpha_remote_datasource.dart';

class AlphaService {
  AlphaService(this._repository);
  final IAlphaRepository _repository;
}
''',
        }),
        'inward-dependency',
        'domain importing data via relative import',
      );
    });

    test('own domain importing own data — package syntax', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': withImport(
            fixtureApp['lib/features/alpha/domain/services/alpha_service.dart']!,
            "import 'package:flutterforge_arch_fixture/features/alpha/data/models/alpha_dto.dart';",
          ),
          'lib/features/alpha/data/models/alpha_dto.dart': '''
class AlphaDto {
  const AlphaDto(this.id);
  final String id;
}
''',
        }),
        'inward-dependency',
        'domain importing data via package: import',
      );
    });

    test('presentation importing own data', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/screens/alpha_screen.dart': withImport(
            fixtureApp['lib/features/alpha/presentation/screens/alpha_screen.dart']!,
            "import '../../data/datasources/alpha_remote_datasource.dart';",
          ),
        }),
        'inward-dependency',
        'presentation importing data',
      );
    });

    test('data importing own presentation', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/data/repositories/alpha_repository_impl.dart':
              withImport(
                fixtureApp['lib/features/alpha/data/repositories/alpha_repository_impl.dart']!,
                "import '../../presentation/bloc/alpha_cubit.dart';",
              ),
        }),
        'inward-dependency',
        'data importing presentation',
      );
    });
  });

  group('domain purity', () {
    for (final String uri in <String>[
      'dart:ui',
      'package:flutter_bloc/flutter_bloc.dart',
      'package:bloc/bloc.dart',
      'package:go_router/go_router.dart',
    ]) {
      test('domain importing $uri is rejected', () async {
        await expectDomainForbidden("import '$uri';");
      });

      test('public barrel exporting $uri is rejected', () async {
        await expectViolation(
          fixtureWith(<String, String>{
            'lib/features/alpha/alpha.dart':
                "${fixtureApp['lib/features/alpha/alpha.dart']!}export '$uri';\n",
          }),
          'domain-purity',
          'public barrel exporting $uri',
        );
      });
    }

    test('domain importing flutter/material is rejected', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/models/alpha_model.dart': '''
import 'package:flutter/material.dart';

class AlphaModel {
  const AlphaModel(this.id);
  final String id;
  Color get color => Colors.blue;
}
''',
        }),
        'domain-purity',
        'domain importing flutter/material',
      );
    });

    test('domain importing material_ui is rejected', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/models/alpha_model.dart': '''
import 'package:material_ui/material_ui.dart';

class AlphaModel {
  const AlphaModel(this.id);
  final String id;
  Color get color => Colors.blue;
}
''',
        }),
        'domain-purity',
        'domain importing material_ui',
      );
    });

    test('domain importing cupertino_ui is rejected', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/models/alpha_model.dart': '''
import 'package:cupertino_ui/cupertino_ui.dart';

class AlphaModel {
  const AlphaModel(this.id);
  final String id;
  Color get color => CupertinoColors.systemBlue;
}
''',
        }),
        'domain-purity',
        'domain importing cupertino_ui',
      );
    });

    test('domain importing generated localizations is rejected', () async {
      await expectDomainForbidden(
        "import '../../../../core/l10n/generated/app_localizations.dart';",
      );
    });

    test('domain importing the router is rejected', () async {
      await expectDomainForbidden(
        "import '../../../../core/router/app_router.dart';",
      );
    });

    test('domain importing the DI composition root is rejected', () async {
      await expectDomainForbidden(
        "import '../../../../core/di/service_locator.dart';",
      );
    });

    test('domain importing the theme is rejected', () async {
      await expectDomainForbidden(
        "import '../../../../core/theme/app_theme.dart';",
      );
    });

    test('domain importing the logger is rejected', () async {
      await expectDomainForbidden(
        "import '../../../../core/utils/logger.dart';",
      );
    });

    test(
      'domain may depend on pure shared models and approved Dart packages',
      () async {
        await expectClean(
          fixtureApp,
          'domain importing core/models and fpdart',
        );
      },
    );
  });

  group('cross-feature access', () {
    test('allowed: importing another feature public domain contract via its '
        'barrel', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': '''
import 'package:flutterforge_arch_fixture/features/beta/beta.dart';
import '../repositories/i_alpha_repository.dart';

class AlphaService implements BetaContract {
  AlphaService(this._repository);
  final IAlphaRepository _repository;

  @override
  String describe() => 'alpha';
}
''',
          'lib/features/beta/beta.dart': '''
export 'domain/models/beta_model.dart';
export 'domain/contracts/beta_contract.dart';
''',
        }),
      );
      expect(
        result.violations
            .where(
              (ArchitectureViolation violation) =>
                  violation.ruleId == 'cross-feature-internals',
            )
            .toList(),
        isEmpty,
        reason: 'importing the public barrel is allowed: ${result.violations}',
      );
      expect(result.errors, isEmpty, reason: 'fixture must be analyzable');
    });

    test('rejected: direct import of another feature domain internals', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': withImport(
            fixtureApp['lib/features/alpha/domain/services/alpha_service.dart']!,
            "import '../../../beta/domain/models/beta_model.dart';",
          ),
        }),
        'cross-feature-internals',
        'direct domain-internal cross-feature import',
      );
    });

    test('rejected: cross-feature data and presentation imports', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': withImport(
            fixtureApp['lib/features/alpha/domain/services/alpha_service.dart']!,
            "import 'package:flutterforge_arch_fixture/features/beta/data/beta_repository.dart';",
          ),
        }),
        'cross-feature-internals',
        'cross-feature data import',
      );
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/screens/alpha_screen.dart': withImport(
            fixtureApp['lib/features/alpha/presentation/screens/alpha_screen.dart']!,
            "import 'package:flutterforge_arch_fixture/features/beta/presentation/beta_screen.dart';",
          ),
        }),
        'cross-feature-internals',
        'cross-feature presentation import',
      );
    });

    test('rejected: barrel that leaks another feature data layer', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/beta/beta.dart': '''
export 'domain/models/beta_model.dart';
export 'domain/contracts/beta_contract.dart';
export 'data/beta_repository.dart';
''',
        }),
        'barrel-exposes-implementation',
        'barrel exporting a data file',
      );
    });

    test(
      'rejected: barrel leaking data transitively through a domain file',
      () async {
        await expectViolation(
          fixtureWith(<String, String>{
            'lib/features/beta/beta.dart': '''
export 'domain/models/beta_model.dart';
export 'domain/contracts/beta_contract.dart';
export 'domain/models/beta_model.dart' show BetaModel;
export 'domain/leak.dart';
''',
            'lib/features/beta/domain/leak.dart': '''
export '../data/beta_repository.dart';
''',
          }),
          'barrel-exposes-implementation',
          'transitive barrel leak',
        );
      },
    );

    test(
      'rejected: barrel conditionally exporting a data implementation',
      () async {
        await expectViolation(
          fixtureWith(<String, String>{
            'lib/features/beta/beta.dart': '''
export 'domain/contracts/beta_contract.dart';
export 'domain/models/beta_model.dart'
    if (dart.library.io) 'data/beta_repository.dart';
''',
          }),
          'barrel-exposes-implementation',
          'conditional export branch of a data file',
        );
      },
    );

    test(
      'accepted: barrel conditionally exporting a domain contract',
      () async {
        await expectClean(
          fixtureWith(<String, String>{
            'lib/features/beta/beta.dart': '''
export 'domain/models/beta_model.dart';
export 'domain/contracts/beta_contract.dart'
    if (dart.library.io) 'domain/models/beta_model.dart';
''',
          }),
          'conditional export branch of a domain file',
        );
      },
    );

    test('rejected: public contract (barrel) importing its own data '
        'implementation', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/beta/beta.dart': '''
import 'data/beta_repository.dart';

export 'domain/models/beta_model.dart';
export 'domain/contracts/beta_contract.dart';
''',
        }),
        'inward-dependency',
        'public barrel importing its feature data layer',
      );
    });

    test(
      'accepted: public contract importing its own domain contract',
      () async {
        await expectClean(
          fixtureWith(<String, String>{
            'lib/features/beta/beta.dart': '''
import 'domain/contracts/beta_contract.dart';

export 'domain/models/beta_model.dart';
export 'domain/contracts/beta_contract.dart';
''',
          }),
          'public barrel importing a domain file',
        );
      },
    );
  });

  group('part and part-of relationships', () {
    test('rejected: a data library including a domain part file', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/data/alpha_cache.dart': '''
part '../domain/models/ui_part.dart';

class AlphaCache {
  const AlphaCache();
}
''',
          'lib/features/alpha/domain/models/ui_part.dart': '''
part of '../../data/alpha_cache.dart';

class UiPart {
  const UiPart();
}
''',
        }),
        'part-location',
        'part file living in another layer than its library',
      );
    });

    test('rejected: a part file in another feature than its library', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/models/alpha_holder.dart': '''
part '../../../beta/domain/models/beta_part.dart';

class AlphaHolder {
  const AlphaHolder();
}
''',
          'lib/features/beta/domain/models/beta_part.dart': '''
part of '../../../alpha/domain/models/alpha_holder.dart';

class BetaPart {
  const BetaPart();
}
''',
        }),
        'part-location',
        'part file living in another feature than its library',
      );
    });

    test('rejected: domain library including a data file through part', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': withImport(
            fixtureApp['lib/features/alpha/domain/services/alpha_service.dart']!,
            "part '../../data/leak_part.dart';",
          ),
          'lib/features/alpha/data/leak_part.dart': '''
part of '../domain/services/alpha_service.dart';

class LeakedData {
  const LeakedData();
}
''',
        }),
        'inward-dependency',
        'domain library with a data part file',
      );
    });

    test('rejected: data file that is part of a domain library (part-of side '
        'alone, library excluded as generated)', () async {
      // Isolates the part-of mechanism: the library is a `.g.dart` file,
      // excluded from checking by the generated-file policy, so its own
      // `part` directive is never evaluated — only the part file's
      // `part of` can expose the domain→data dependency.
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.g.dart': '''
part '../../data/leak_part.dart';
''',
          'lib/features/alpha/data/leak_part.dart': '''
part of '../domain/services/alpha_service.g.dart';

class LeakedData {
  const LeakedData();
}
''',
        }),
        'inward-dependency',
        'part-of dependency reported from the library side alone',
      );
    });

    test('accepted: domain library with a same-layer domain part', () async {
      await expectClean(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': withImport(
            fixtureApp['lib/features/alpha/domain/services/alpha_service.dart']!,
            "part 'alpha_service_helpers.dart';",
          ),
          'lib/features/alpha/domain/services/alpha_service_helpers.dart': '''
part of 'alpha_service.dart';

class AlphaServiceHelper {
  const AlphaServiceHelper();
}
''',
        }),
        'same-layer part inclusion',
      );
    });
  });

  group('stored state controllers', () {
    Future<void> expectStoredCubit(String fieldDeclaration, String why) async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/bloc/beta_mirror_cubit.dart':
              '''
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fpdart/fpdart.dart';

import '../../../../core/models/failure.dart';
import '../../domain/models/alpha_model.dart';
import '../../domain/repositories/i_alpha_repository.dart';
import '../../domain/services/alpha_service.dart';
import 'alpha_cubit.dart';

class MirrorCubit extends Cubit<AlphaState2> {
  MirrorCubit(this._service) : super(const AlphaInitial2());

  final AlphaService _service;
  $fieldDeclaration
}

typedef AlphaCubitRef = AlphaCubit;

AlphaCubit placeholder() => AlphaCubit(AlphaService(PlaceholderRepository()));

class PlaceholderRepository implements IAlphaRepository {
  @override
  Future<Either<Failure, AlphaModel>> fetch() async =>
      Right<Failure, AlphaModel>(const AlphaModel('x'));
}

AlphaCubit placeholder2() => placeholder();

class AlphaState2 {
  const AlphaState2();
}

class CustomBase extends BlocBase<int> {
  CustomBase() : super(0);
}

extension type CubitHandle(AlphaCubit cubit) {}

class AlphaInitial2 extends AlphaState2 {
  const AlphaInitial2();
}
''',
        }),
        'stored-cubit',
        why,
      );
    }

    test('nullable stored cubit is rejected', () async {
      await expectStoredCubit('AlphaCubit? _other;', 'nullable cubit field');
    });

    test('late final stored cubit is rejected', () async {
      await expectStoredCubit(
        'late final AlphaCubit _other;',
        'late final cubit field',
      );
    });

    test('mutable (non-final) stored cubit is rejected', () async {
      await expectStoredCubit(
        'AlphaCubit _other = placeholder();',
        'mutable cubit field',
      );
    });

    test('aliased stored cubit is rejected', () async {
      await expectStoredCubit(
        'AlphaCubitRef _other = placeholder2();',
        'aliased cubit field',
      );
    });

    test('generic/container stored cubit is rejected', () async {
      await expectStoredCubit(
        'List<AlphaCubit> _others = <AlphaCubit>[];',
        'container cubit field',
      );
    });

    test('bloc-family base types are rejected (BlocBase, StateStreamable, '
        'StateStreamableSource, Emittable, custom BlocBase subtype)', () async {
      await expectStoredCubit('BlocBase<int>? _other;', 'BlocBase field');
      await expectStoredCubit(
        'StateStreamable<int>? _other;',
        'StateStreamable field',
      );
      await expectStoredCubit(
        'StateStreamableSource<int>? _other;',
        'StateStreamableSource field',
      );
      await expectStoredCubit('Emittable<int>? _other;', 'Emittable field');
      await expectStoredCubit(
        'CustomBase? _other;',
        'direct BlocBase subtype that is neither Cubit nor Bloc',
      );
    });

    test('record containing a cubit is rejected', () async {
      await expectStoredCubit(
        '(AlphaCubit, int)? _other;',
        'positional record',
      );
      await expectStoredCubit(
        '({AlphaCubit cubit, int count})? _other;',
        'named record',
      );
    });

    test('stored cubit factory (function type returning a cubit) is '
        'rejected', () async {
      await expectStoredCubit(
        'AlphaCubit Function()? _other;',
        'cubit factory',
      );
      await expectStoredCubit(
        'Future<AlphaCubit> Function()? _other;',
        'async cubit factory',
      );
    });

    test('extension type erasing to a cubit is rejected', () async {
      await expectStoredCubit('CubitHandle? _other;', 'extension type field');
    });

    group('freezed factory parameters', () {
      Map<String, String> freezedFixture(String parameter) =>
          fixtureWith(<String, String>{
            'lib/features/alpha/presentation/bloc/alpha_form.dart':
                '''
import 'package:freezed_annotation/freezed_annotation.dart';

import 'alpha_cubit.dart';

part 'alpha_form.freezed.dart';

@freezed
abstract class AlphaForm with _\$AlphaForm {
  const factory AlphaForm({$parameter}) = _AlphaForm;
}
''',
            'lib/features/alpha/presentation/bloc/alpha_form.freezed.dart': '''
part of 'alpha_form.dart';

mixin _\$AlphaForm {}

class _AlphaForm implements AlphaForm {
  const _AlphaForm({this.name, this.cubit});
  final Object? name;
  final Object? cubit;
}
''',
          });

      test('rejected: a cubit parameter of the redirecting factory', () async {
        await expectViolation(
          freezedFixture('String? name, AlphaCubit? cubit'),
          'stored-cubit',
          'freezed class holding a cubit',
        );
      });

      test('accepted: a freezed class without cubit parameters', () async {
        await expectClean(
          freezedFixture('String? name, int? cubit'),
          'freezed class with plain parameters',
        );
      });
    });

    test('accepted: widgets and State objects may store a cubit received '
        'through their constructor', () async {
      await expectClean(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/widgets/alpha_dialog.dart': '''
import 'package:material_ui/material_ui.dart';

import '../bloc/alpha_cubit.dart';

class AlphaDialog extends StatelessWidget {
  const AlphaDialog({super.key, required this.cubit, required this.create});

  final AlphaCubit cubit;
  final AlphaCubit Function() create;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class AlphaPage extends StatefulWidget {
  const AlphaPage({super.key, required this.cubit});

  final AlphaCubit cubit;

  @override
  State<AlphaPage> createState() => _AlphaPageState();
}

class _AlphaPageState extends State<AlphaPage> {
  AlphaCubit? _cached;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''',
        }),
        'widget and State fields holding a cubit',
      );
    });

    test('rejected: a non-widget class next to a widget still cannot store a '
        'cubit', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/widgets/alpha_dialog.dart': '''
import 'package:material_ui/material_ui.dart';

import '../bloc/alpha_cubit.dart';

class AlphaDialog extends StatelessWidget {
  const AlphaDialog({super.key, required this.cubit});

  final AlphaCubit cubit;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class AlphaHelper {
  AlphaHelper(this.cubit);

  final AlphaCubit cubit;
}
''',
        }),
        'stored-cubit',
        'plain helper class in a widget file',
      );
    });

    test('unusually named Cubit subclass stored is rejected', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/bloc/weird_cubit.dart': '''
import 'package:flutter_bloc/flutter_bloc.dart';

class WeirdController extends Cubit<int> {
  WeirdController() : super(0);
}
''',
          'lib/features/alpha/presentation/bloc/beta_mirror_cubit.dart': '''
import 'package:flutter_bloc/flutter_bloc.dart';

import 'weird_cubit.dart';

class Holder {
  WeirdController stored = WeirdController();
}
''',
        }),
        'stored-cubit',
        'unusually named cubit subclass stored as field',
      );
    });

    test('cubit inheriting another stored/inherited type chain is rejected '
        '(inherited cubit type)', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/bloc/weird_cubit.dart': '''
import 'package:flutter_bloc/flutter_bloc.dart';

class WeirdController extends Cubit<int> {
  WeirdController() : super(0);
}

class DerivedController extends WeirdController {
  DerivedController() : super();
}
''',
          'lib/features/alpha/presentation/bloc/beta_mirror_cubit.dart': '''
import 'weird_cubit.dart';

class Holder {
  DerivedController stored = DerivedController();
}
''',
        }),
        'stored-cubit',
        'field typed as a subclass of a Cubit subclass (inherited type)',
      );
    });

    test('allowed: local context.read inside a widget callback', () async {
      await expectClean(fixtureApp, 'context.read inside onPressed callback');
    });

    test('allowed: non-cubit fields', () async {
      await expectClean(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/bloc/beta_mirror_cubit.dart': '''
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/services/alpha_service.dart';

class AlphaState3 {
  const AlphaState3();
}

class MirrorCubit extends Cubit<AlphaState3> {
  MirrorCubit(this._service) : super(const AlphaState3());

  final AlphaService _service;
  final List<String> items = <String>[];
}
''',
        }),
        'service field is not a cubit field',
      );
    });
  });

  group('locator access', () {
    test('rejected: feature-level direct getIt resolution', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': getItFixture(
            "import 'package:get_it/get_it.dart';",
            'final AlphaService self = GetIt.instance<AlphaService>();',
          ),
        }),
        'locator-access',
        'feature-level getIt resolution',
      );
    });

    test('rejected: aliased GetIt.instance resolution in a feature', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': getItFixture(
            "import 'package:get_it/get_it.dart' as sl;",
            'final AlphaService self = sl.GetIt.instance<AlphaService>();',
          ),
        }),
        'locator-access',
        'aliased GetIt.instance resolution',
      );
    });

    test('rejected: presentation resolving getIt via relative DI import '
        '(no package:get_it import)', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/screens/alpha_screen.dart': '''
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../bloc/alpha_cubit.dart';
import '../bloc/alpha_state.dart';

class AlphaScreen extends StatelessWidget {
  const AlphaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AlphaCubit>(
      create: (_) => getIt<AlphaCubit>(),
      child: Scaffold(
        body: BlocBuilder<AlphaCubit, AlphaState>(
          builder: (BuildContext context, AlphaState state) =>
              const Text('alpha'),
        ),
      ),
    );
  }
}
''',
        }),
        'locator-access',
        'presentation resolving getIt through the relative DI import',
      );
    });

    test('rejected: domain resolving getIt via relative DI import '
        '(no package:get_it import)', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': '''
import '../../../../core/di/service_locator.dart';
import '../models/alpha_model.dart';
import '../repositories/i_alpha_repository.dart';

class AlphaService {
  AlphaService(this._repository);

  final IAlphaRepository _repository;

  AlphaModel grab() => getIt<AlphaModel>();
}
''',
        }),
        'locator-access',
        'domain resolving getIt through the relative DI import',
      );
    });

    test(
      'accepted: main.dart imports the DI file for bootstrap setup only',
      () async {
        await expectClean(
          fixtureApp,
          'main.dart importing service_locator.dart and calling '
          'setupServiceLocator() without touching getIt',
        );
      },
    );

    test('rejected: registration outside service_locator.dart', () async {
      final String routerWithDataSource = withImport(
        fixtureApp['lib/core/router/app_router.dart']!,
        "import '../../features/alpha/data/datasources/alpha_remote_datasource.dart';\n"
        "import '../../features/alpha/data/repositories/alpha_repository_impl.dart';\n"
        "import '../../features/alpha/domain/services/alpha_service.dart';",
      );
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/core/router/app_router.dart':
              '$routerWithDataSource\n'
              'void sneaky() => getIt.registerFactory<AlphaCubit>(\n'
              '    () => AlphaCubit(AlphaService(AlphaRepository(AlphaRemoteDataSource()))));\n',
        }),
        'registration-outside-di',
        'registration in app_router',
      );
    });

    const String alphaModule = '''
import 'package:get_it/get_it.dart';

import 'data/datasources/alpha_remote_datasource.dart';
import 'data/repositories/alpha_repository_impl.dart';
import 'domain/repositories/i_alpha_repository.dart';
import 'domain/services/alpha_service.dart';
import 'presentation/bloc/alpha_cubit.dart';

void registerAlphaFeature(GetIt getIt) {
  getIt.registerLazySingleton<IAlphaRemoteDataSource>(
    () => AlphaRemoteDataSource(),
  );
  getIt.registerLazySingleton<IAlphaRepository>(
    () => AlphaRepository(getIt<IAlphaRemoteDataSource>()),
  );
  getIt.registerLazySingleton<AlphaService>(
    () => AlphaService(getIt<IAlphaRepository>()),
  );
  getIt.registerFactory<AlphaCubit>(() => AlphaCubit(getIt<AlphaService>()));
}
''';

    test('accepted: a feature module registers its own feature', () async {
      await expectClean(
        fixtureWith(<String, String>{
          'lib/features/alpha/alpha_module.dart': alphaModule,
        }),
        'alpha_module.dart importing get_it and registering alpha',
      );
    });

    test('rejected: registration in a module-named file outside the feature '
        'root', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/alpha_module.dart': alphaModule
              .replaceAll("'data/", "'../data/")
              .replaceAll("'domain/", "'../domain/")
              .replaceAll("'presentation/", "'"),
        }),
        'registration-outside-di',
        'registration in presentation/alpha_module.dart',
      );
    });

    test('rejected: another feature importing a feature module', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/alpha_module.dart': alphaModule,
          'lib/features/beta/presentation/uses_alpha.dart': '''
import '../../alpha/alpha_module.dart';

final Object alphaRegistration = registerAlphaFeature;
''',
        }),
        'cross-feature-internals',
        'beta importing alpha_module.dart',
      );
    });

    test('accepted: constructor injection in features', () async {
      await expectClean(fixtureApp, 'constructor injection');
    });
  });

  group('composition and bootstrap', () {
    test('accepted: app.dart composing app-scoped providers with '
        'presentation imports', () async {
      await expectClean(
        fixtureApp,
        'app.dart composition with presentation imports',
      );
    });

    test('accepted: main bootstrap calling setup + runApp', () async {
      await expectClean(fixtureApp, 'main bootstrap');
    });

    test('rejected: main.dart registering dependencies', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/main.dart': '''
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/di/service_locator.dart';
import 'features/alpha/presentation/bloc/alpha_cubit.dart';
import 'features/alpha/domain/repositories/i_alpha_repository.dart';
import 'features/alpha/domain/services/alpha_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  getIt.registerFactory<AlphaCubit>(
    () => AlphaCubit(AlphaService(getIt<IAlphaRepository>())),
  );
  await setupServiceLocator();
  runApp(const MyApp());
}
''',
        }),
        'registration-outside-di',
        'registration in main.dart',
      );
    });

    test('rejected: main.dart registration reports the locator once, not the '
        'method name too', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          'lib/main.dart': '''
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/di/service_locator.dart';
import 'features/alpha/presentation/bloc/alpha_cubit.dart';
import 'features/alpha/domain/repositories/i_alpha_repository.dart';
import 'features/alpha/domain/services/alpha_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  getIt.registerFactory<AlphaCubit>(
    () => AlphaCubit(AlphaService(getIt<IAlphaRepository>())),
  );
  await setupServiceLocator();
  runApp(const MyApp());
}
''',
        }),
      );
      expect(result.errors, isEmpty);
      final List<String> locatorFindings = result.violations
          .where((ArchitectureViolation v) => v.ruleId == 'locator-access')
          .map((ArchitectureViolation v) => v.explanation)
          .toList();
      expect(locatorFindings, isNotEmpty);
      expect(
        locatorFindings.where(
          (String text) => text.contains('registerFactory'),
        ),
        isEmpty,
        reason:
            'the get_it method name is not a finding of its own: '
            '$locatorFindings',
      );
      expect(
        result.violations.map((ArchitectureViolation v) => v.ruleId),
        contains('registration-outside-di'),
      );
    });

    test('rejected: core importing feature internals outside composition '
        'roots', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/core/services/example_service.dart': '''
import '../../features/alpha/presentation/bloc/alpha_cubit.dart';

class ExampleService {
  ExampleService();
}
''',
        }),
        'core-imports-feature',
        'core importing presentation',
      );
    });
  });

  group('syntax and resolution handling', () {
    /// A file URI of a real, resolvable library (the checker under test).
    final String fileUri = Directory.current.uri
        .resolve('test/support/architecture_checker.dart')
        .toString();

    for (final String directive in <String>['import', 'export']) {
      test('file: URI in an $directive fails closed', () async {
        final CheckerResult result = await ArchitectureChecker.checkSources(
          fixtureWith(<String, String>{
            'lib/features/alpha/domain/models/alpha_model.dart':
                "$directive '$fileUri';\n"
                '${fixtureApp['lib/features/alpha/domain/models/alpha_model.dart']!}',
          }),
        );
        expect(result.errors, isNotEmpty, reason: 'file: URI must be an error');
        expect(
          result.errors.map((CheckerError error) => error.message),
          contains(contains("'file:'")),
        );
        expect(result.isClean, isFalse);
      });
    }

    test('conditional imports are inspected on every branch', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': '''
import 'package:fpdart/fpdart.dart';

import '../../../../core/models/failure.dart';
import '../models/alpha_model.dart';
import '../repositories/i_alpha_repository.dart'
    if (dart.library.io) '../../../alpha/data/datasources/alpha_remote_datasource.dart';

class AlphaService {
  AlphaService(this._repository);
  final IAlphaRepository _repository;
}
''',
        }),
        'inward-dependency',
        'conditional import data branch',
      );
    });

    test('multiline import syntax is inspected', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/screens/alpha_screen.dart': '''
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import
    '../../data/datasources/alpha_remote_datasource.dart';
import '../bloc/alpha_cubit.dart';
import '../bloc/alpha_state.dart';

class AlphaScreen extends StatelessWidget {
  const AlphaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AlphaCubit, AlphaState>(
      builder: (BuildContext context, AlphaState state) => const Text('x'),
    );
  }
}
''',
        }),
        'inward-dependency',
        'multiline import',
      );
    });

    test('path normalization: ../ chains and ./ segments resolve to the same '
        'file identity', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': withImport(
            fixtureApp['lib/features/alpha/domain/services/alpha_service.dart']!,
            "import './../.././../alpha/data/datasources/./alpha_remote_datasource.dart';",
          ),
        }),
        'inward-dependency',
        'normalized path resolves to data file',
      );
    });

    test('path normalization: package import whose ../ segments collapse into '
        'the data layer', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': withImport(
            fixtureApp['lib/features/alpha/domain/services/alpha_service.dart']!,
            "import 'package:flutterforge_arch_fixture/features/alpha/domain/../data/datasources/alpha_remote_datasource.dart';",
          ),
        }),
        'inward-dependency',
        'package import with .. collapsing into a data file',
      );
    });

    test(
      'malformed fixture (syntax error) fails loudly, not silently',
      () async {
        final CheckerResult result = await ArchitectureChecker.checkSources(
          fixtureWith(<String, String>{
            'lib/features/alpha/domain/models/broken.dart': 'class Broken {',
          }),
        );
        expect(result.errors, isNotEmpty, reason: 'syntax error must surface');
        expect(result.isClean, isFalse);
      },
    );

    test('unresolved import fails loudly with an actionable checker error', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': withImport(
            fixtureApp['lib/features/alpha/domain/services/alpha_service.dart']!,
            "import '../repositories/does_not_exist.dart';",
          ),
        }),
      );
      expect(result.errors, isNotEmpty, reason: 'unresolved URI must surface');
      expect(
        result.errors.any(
          (CheckerError error) => error.message.contains('does_not_exist.dart'),
        ),
        isTrue,
        reason: 'error should name the unresolved file: ${result.errors}',
      );
    });

    test('unresolved package import fails loudly', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          'lib/features/alpha/domain/services/alpha_service.dart': withImport(
            fixtureApp['lib/features/alpha/domain/services/alpha_service.dart']!,
            "import 'package:not_a_real_package/nope.dart';",
          ),
        }),
      );
      expect(result.errors, isNotEmpty);
    });
  });

  group('generated-file policy', () {
    test('generated implementation files are excluded from checking', () async {
      await expectClean(
        fixtureWith(<String, String>{
          'lib/features/alpha/presentation/bloc/alpha_cubit.freezed.dart': '''
// Generated garbage that would violate every rule if checked.
import 'dart:html';
import '../../data/datasources/alpha_remote_datasource.dart';
class FreezedJunk {
  AlphaCubit? _cubit;
}
''',
          'lib/core/l10n/generated/app_localizations.dart': '''
import 'package:material_ui/material_ui.dart';
import '../../features/alpha/data/datasources/alpha_remote_datasource.dart';
class AppLocalizations {}
''',
        }),
        'generated files excluded by policy',
      );
    });
  });
}
