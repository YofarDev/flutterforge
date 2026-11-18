/// Boundary-rule regression tests for the architecture checker: domain
/// purity through re-export chains, and feature dependency cycles.
///
/// Deliberately a SEPARATE test file from `architecture_checker_test.dart`:
/// the analyzer retains per-process state across fixture runs, and a fresh
/// isolate per test file keeps these checks independent of whatever state
/// earlier fixture-heavy files leave behind.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/architecture_checker.dart';
import 'support/fixture_app.dart';
import 'support/checker_expectations.dart';

void main() {
  group('feature dependency cycles', () {
    /// Adds a cross-feature import from one feature's domain service to
    /// another feature's public barrel (a legal edge). Fixtures must be free
    /// of unresolved URIs: the checker fails closed on them, so a fixture
    /// error would mask the rule under test.
    const Set<String> knownFeatures = <String>{'alpha', 'beta'};

    /// A type from each known feature's barrel, so the cross-feature import
    /// is actually used (mirroring real barrel consumers).
    const Map<String, String> barrelSymbols = <String, String>{
      'alpha': 'AlphaModel',
      'beta': 'BetaContract',
    };

    Map<String, String> withEdge(String fromFeature, String toFeature) {
      final String title =
          fromFeature[0].toUpperCase() + fromFeature.substring(1);
      final String? symbol = barrelSymbols[toFeature];
      final String usage = symbol == null
          ? ''
          : '\n  void use($symbol value) {}';
      return <String, String>{
        'lib/features/$fromFeature/domain/services/${fromFeature}_service.dart':
            """
import 'package:flutterforge_arch_fixture/features/$toFeature/$toFeature.dart';

class ${title}Service {
  ${title}Service(Object? dependency);$usage
}
""",
        // The target barrel must exist; alpha and beta already have one.
        if (!knownFeatures.contains(toFeature))
          'lib/features/$toFeature/$toFeature.dart': '// empty barrel\n',
      };
    }

    test('accepted: a single directed edge alpha → beta', () async {
      await expectClean(
        fixtureWith(withEdge('alpha', 'beta')),
        'one-way alpha → beta barrel access',
      );
    });

    test('accepted: an acyclic diamond', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          ...withEdge('alpha', 'gamma'),
          'lib/features/alpha/domain/services/alpha_service.dart': '''
import 'package:flutterforge_arch_fixture/features/beta/beta.dart';
import 'package:flutterforge_arch_fixture/features/gamma/gamma.dart';

class AlphaService {
  AlphaService(Object? dependency);
  void use(BetaContract value) {}
}
''',
          ...withEdge('beta', 'delta'),
          ...withEdge('gamma', 'delta'),
        }),
      );
      expect(
        result.violations
            .where(
              (ArchitectureViolation violation) =>
                  violation.ruleId == 'feature-dependency-cycle',
            )
            .toList(),
        isEmpty,
        reason: 'acyclic diamond must pass: ${result.violations}',
      );
      expect(result.errors, isEmpty, reason: 'fixture must be analyzable');
    });

    test('rejected: alpha → beta → alpha', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          ...withEdge('alpha', 'beta'),
          ...withEdge('beta', 'alpha'),
        }),
      );
      final List<ArchitectureViolation> cycles = result.violations
          .where(
            (ArchitectureViolation violation) =>
                violation.ruleId == 'feature-dependency-cycle',
          )
          .toList();
      expect(cycles, hasLength(1), reason: '${result.violations}');
      expect(cycles.single.explanation, contains('alpha → beta → alpha'));
      expect(cycles.single.path, contains('lib/features/'));
      expect(result.errors, isEmpty, reason: 'fixture must be analyzable');
    });

    test('rejected: a three-feature cycle', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          ...withEdge('alpha', 'beta'),
          ...withEdge('beta', 'gamma'),
          ...withEdge('gamma', 'alpha'),
        }),
      );
      final List<ArchitectureViolation> cycles = result.violations
          .where(
            (ArchitectureViolation violation) =>
                violation.ruleId == 'feature-dependency-cycle',
          )
          .toList();
      expect(cycles, hasLength(1), reason: '${result.violations}');
      expect(
        cycles.single.explanation,
        contains('alpha → beta → gamma → alpha'),
      );
      expect(result.errors, isEmpty);
    });

    test('rejected: a conditional import branch creating a cycle', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          ...withEdge('alpha', 'beta'),
          'lib/features/beta/domain/services/beta_service.dart': """
import '../models/beta_model.dart'
    if (dart.library.io)
        'package:flutterforge_arch_fixture/features/alpha/alpha.dart';

class BetaService {
  void use(BetaModel m) {}
}
""",
        }),
      );
      final List<ArchitectureViolation> cycles = result.violations
          .where(
            (ArchitectureViolation violation) =>
                violation.ruleId == 'feature-dependency-cycle',
          )
          .toList();
      expect(cycles, hasLength(1), reason: '${result.violations}');
      expect(result.errors, isEmpty);
    });

    test(
      'repeated imports creating a cycle yield a single diagnostic',
      () async {
        final CheckerResult result = await ArchitectureChecker.checkSources(
          fixtureWith(<String, String>{
            ...withEdge('alpha', 'beta'),
            'lib/features/beta/domain/services/beta_service.dart': """
import 'package:flutterforge_arch_fixture/features/alpha/alpha.dart';
import 'package:flutterforge_arch_fixture/features/alpha/alpha.dart';

class BetaService {}
""",
          }),
        );
        expect(
          result.violations
              .where(
                (ArchitectureViolation violation) =>
                    violation.ruleId == 'feature-dependency-cycle',
              )
              .length,
          1,
          reason: 'no duplicated cycle diagnostics: ${result.violations}',
        );
        expect(result.errors, isEmpty);
      },
    );

    test('same-feature references never count as a cycle', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          ...withEdge('alpha', 'beta'),
          'lib/features/beta/data/beta_repository.dart': withImport(
            fixtureApp['lib/features/beta/data/beta_repository.dart']!,
            "import '../domain/models/beta_model.dart';",
          ),
        }),
      );
      expect(
        result.violations
            .where(
              (ArchitectureViolation violation) =>
                  violation.ruleId == 'feature-dependency-cycle',
            )
            .toList(),
        isEmpty,
        reason: 'intra-feature edges are not cycle candidates',
      );
      expect(result.errors, isEmpty);
    });
  });

  group('domain purity through re-export chains', () {
    for (final String layer in <String>['data', 'presentation']) {
      test(
        'rejected: own $layer types through a local feature barrel',
        () async {
          final CheckerResult result = await ArchitectureChecker.checkSources(
            fixtureWith(<String, String>{
              'lib/features/alpha/shared.dart':
                  "export '$layer/hidden_type.dart';\n",
              'lib/features/alpha/$layer/hidden_type.dart':
                  'class HiddenType {}\n',
              'lib/features/alpha/domain/models/alpha_model.dart': '''
import '../../shared.dart' show HiddenType;

class AlphaModel {
  const AlphaModel(this.id);
  final String id;
  bool hasHiddenType(HiddenType? value) => value != null;
}
''',
            }),
          );
          expect(result.errors, isEmpty);
          expect(
            result.violations.map((ArchitectureViolation v) => v.ruleId),
            contains('domain-purity'),
          );
        },
      );
    }

    for (final String uri in <String>[
      'dart:ui',
      'package:flutter_bloc/flutter_bloc.dart',
      'package:bloc/bloc.dart',
      'package:go_router/go_router.dart',
    ]) {
      test('rejected: $uri re-exported through a core barrel', () async {
        final CheckerResult result = await ArchitectureChecker.checkSources(
          fixtureWith(<String, String>{
            'lib/core/bridge.dart': "export '$uri';\n",
            'lib/features/alpha/domain/models/alpha_model.dart': '''
import '../../../../core/bridge.dart';

class AlphaModel {
  const AlphaModel(this.id);
  final String id;
}
''',
          }),
        );
        expect(result.errors, isEmpty);
        expect(
          result.violations.map((ArchitectureViolation v) => v.ruleId),
          contains('domain-purity'),
          reason: '$uri must be caught in the re-export chain',
        );
      });
    }

    test('rejected: material exported by a generated library', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          'lib/core/ui_bridge.g.dart':
              "export 'package:material_ui/material_ui.dart';\n",
          'lib/features/alpha/domain/models/alpha_model.dart': '''
import '../../../../core/ui_bridge.g.dart';

class AlphaModel {
  const AlphaModel(this.id);
  final String id;
  bool isAttached(BuildContext? context) => context != null;
}
''',
        }),
      );
      expect(result.errors, isEmpty);
      expect(
        result.violations.map((ArchitectureViolation v) => v.ruleId),
        contains('domain-purity'),
      );
    });

    test('rejected: generated library on an unselected conditional branch', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          'lib/core/shared.dart':
              "export 'pure.dart' if (dart.library.html) 'ui_bridge.g.dart';\n",
          'lib/core/pure.dart': 'class Pure {}\n',
          'lib/core/ui_bridge.g.dart':
              "export 'package:material_ui/material_ui.dart';\n",
          'lib/features/alpha/domain/models/alpha_model.dart': withImport(
            fixtureApp['lib/features/alpha/domain/models/alpha_model.dart']!,
            "import '../../../../core/shared.dart';",
          ),
        }),
      );
      expect(result.errors, isEmpty);
      expect(
        result.violations.map((ArchitectureViolation v) => v.ruleId),
        contains('domain-purity'),
      );
    });

    test(
      'accepted: generated pure exports are traversed without banning them',
      () async {
        await expectClean(
          fixtureWith(<String, String>{
            'lib/core/pure_bridge.g.dart': "export 'models/failure.dart';\n",
            'lib/features/alpha/domain/models/alpha_model.dart': withImport(
              fixtureApp['lib/features/alpha/domain/models/alpha_model.dart']!,
              "import '../../../../core/pure_bridge.g.dart';",
            ),
          }),
          'generated libraries exposing pure domain types',
        );
      },
    );

    test('unresolved generated export chains fail closed', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          'lib/core/bridge.g.dart': "export 'missing.dart';\n",
          'lib/features/alpha/domain/models/alpha_model.dart': withImport(
            fixtureApp['lib/features/alpha/domain/models/alpha_model.dart']!,
            "import '../../../../core/bridge.g.dart';",
          ),
        }),
      );
      expect(result.isClean, isFalse);
      expect(result.errors, isNotEmpty);
    });

    /// A core barrel re-exporting material, imported by a domain file that
    /// USES BuildContext — the real loophole: without the chain walk, the
    /// symbol resolves through the re-export and nothing is reported.
    Map<String, String> buildContextThroughBarrel(String importLine) =>
        fixtureWith(<String, String>{
          'lib/core/shared.dart': '''
export 'package:material_ui/material_ui.dart';
''',
          'lib/features/alpha/domain/models/alpha_model.dart':
              '''
$importLine

class AlphaModel {
  const AlphaModel(this.id);
  final String id;

  bool isAttached(BuildContext? context) => context != null;
}
''',
        });

    test('rejected: core barrel re-exporting material, BuildContext used '
        '(relative import)', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        buildContextThroughBarrel("import '../../../../core/shared.dart';"),
      );
      expect(
        result.violations.map(
          (ArchitectureViolation violation) => violation.ruleId,
        ),
        contains('domain-purity'),
        reason: 're-exported material must be rejected: ${result.violations}',
      );
      expect(result.errors, isEmpty, reason: 'fixture must be analyzable');
    });

    test('rejected: same through a package: import', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        buildContextThroughBarrel(
          "import 'package:flutterforge_arch_fixture/core/shared.dart';",
        ),
      );
      expect(
        result.violations.map(
          (ArchitectureViolation violation) => violation.ruleId,
        ),
        contains('domain-purity'),
      );
      expect(result.errors, isEmpty);
    });

    test('rejected: even behind a show clause', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        buildContextThroughBarrel(
          "import '../../../../core/shared.dart' show BuildContext;",
        ),
      );
      expect(
        result.violations.map(
          (ArchitectureViolation violation) => violation.ruleId,
        ),
        contains('domain-purity'),
        reason: 'a show clause must not launder the dependency',
      );
      expect(result.errors, isEmpty);
    });

    test('rejected: multiple hops through local re-exports', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          'lib/core/shared.dart': '''
export 'shared_impl.dart';
''',
          'lib/core/shared_impl.dart': '''
export 'package:material_ui/material_ui.dart';
''',
          'lib/features/alpha/domain/models/alpha_model.dart': withImport(
            fixtureApp['lib/features/alpha/domain/models/alpha_model.dart']!,
            "import '../../../../core/shared.dart';",
          ),
        }),
      );
      expect(
        result.violations.map(
          (ArchitectureViolation violation) => violation.ruleId,
        ),
        contains('domain-purity'),
        reason: 'two-hop re-export must be rejected: ${result.violations}',
      );
      expect(result.errors, isEmpty);
      // The explanation carries the full chain.
      expect(
        result.violations
            .firstWhere(
              (ArchitectureViolation violation) =>
                  violation.ruleId == 'domain-purity',
            )
            .explanation,
        contains('core/shared.dart'),
      );
    });

    test('rejected: conditional export branch re-exporting material', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          'lib/core/shared.dart': '''
export 'pure_models.dart' if (dart.library.io) 'ui_reexport.dart';
''',
          'lib/core/pure_models.dart': '''
class PureModel {
  const PureModel();
}
''',
          'lib/core/ui_reexport.dart': '''
export 'package:material_ui/material_ui.dart';
''',
          'lib/features/alpha/domain/models/alpha_model.dart': withImport(
            fixtureApp['lib/features/alpha/domain/models/alpha_model.dart']!,
            "import '../../../../core/shared.dart';",
          ),
        }),
      );
      expect(
        result.violations.map(
          (ArchitectureViolation violation) => violation.ruleId,
        ),
        contains('domain-purity'),
        reason:
            'every conditional branch is a real dependency on some '
            'platform: ${result.violations}',
      );
      expect(result.errors, isEmpty);
    });

    test('rejected: forbidden local infrastructure through a barrel', () async {
      final CheckerResult result = await ArchitectureChecker.checkSources(
        fixtureWith(<String, String>{
          'lib/core/shared.dart': '''
export 'utils/logger.dart';
''',
          'lib/features/alpha/domain/models/alpha_model.dart': withImport(
            fixtureApp['lib/features/alpha/domain/models/alpha_model.dart']!,
            "import '../../../../core/shared.dart';",
          ),
        }),
      );
      expect(
        result.violations.map(
          (ArchitectureViolation violation) => violation.ruleId,
        ),
        contains('domain-purity'),
        reason:
            'the logger must not be reachable through a barrel: '
            '${result.violations}',
      );
      expect(result.errors, isEmpty);
    });

    test(
      'accepted: pure Dart core exports (including dart: and fpdart)',
      () async {
        await expectClean(
          fixtureWith(<String, String>{
            'lib/core/shared.dart': '''
export 'dart:async';
export 'package:fpdart/fpdart.dart';
export 'package:flutter/foundation.dart';
''',
            'lib/features/alpha/domain/models/alpha_model.dart': withImport(
              fixtureApp['lib/features/alpha/domain/models/alpha_model.dart']!,
              "import '../../../../core/shared.dart';",
            ),
          }),
          'a pure core barrel (dart:async, fpdart, foundation only)',
        );
      },
    );

    test('cyclic pure exports terminate', () async {
      await expectClean(
        fixtureWith(<String, String>{
          'lib/core/cycle_a.dart': '''
export 'cycle_b.dart';
''',
          'lib/core/cycle_b.dart': '''
export 'cycle_a.dart';
''',
          'lib/features/alpha/domain/models/alpha_model.dart': withImport(
            fixtureApp['lib/features/alpha/domain/models/alpha_model.dart']!,
            "import '../../../../core/cycle_a.dart';",
          ),
        }),
        'a cycle of pure exports must terminate, not loop forever',
      );
    });

    test('unrelated UI files do not make a pure domain import fail', () async {
      await expectClean(
        fixtureWith(<String, String>{
          'lib/core/shared.dart': '''
export 'models/failure.dart';
''',
          'lib/features/alpha/domain/models/alpha_model.dart': withImport(
            fixtureApp['lib/features/alpha/domain/models/alpha_model.dart']!,
            "import '../../../../core/shared.dart';",
          ),
        }),
        'a domain import of a pure barrel stays clean even though the app '
        'has UI files elsewhere',
      );
    });
  });

  group('file locations and feature modules', () {
    /// A feature module that also exposes a locator: only the app-wide
    /// composition roots may import it, or anything could resolve through it.
    const String alphaModule = '''
import 'package:get_it/get_it.dart';

final GetIt alphaLocator = GetIt.instance;

void registerAlphaFeature(GetIt getIt) {}
''';

    test(
      'rejected: a lib/shared/ file re-exporting feature internals',
      () async {
        await expectViolation(
          fixtureWith(<String, String>{
            'lib/shared/bridge.dart': '''
export '../features/alpha/data/repositories/alpha_repository_impl.dart';
''',
          }),
          'core-imports-feature',
          'lib/shared/ is infrastructure like lib/core/, not a rule-free zone',
        );
      },
    );

    test('rejected: an extra file at a feature root', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/alpha_internal.dart': '''
export 'data/datasources/alpha_remote_datasource.dart';
''',
        }),
        'unclassified-location',
        'alpha_internal.dart beside the barrel and module',
      );
    });

    test(
      'rejected: a feature folder outside data/domain/presentation',
      () async {
        await expectViolation(
          fixtureWith(<String, String>{
            'lib/features/alpha/services/alpha_helper.dart': '''
class AlphaHelper {}
''',
          }),
          'unclassified-location',
          'features/alpha/services/ has no layer',
        );
      },
    );

    test('rejected: a file directly in lib/features/', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/shared.dart': '''
export 'beta/presentation/beta_screen.dart';
''',
        }),
        'unclassified-location',
        'lib/features/shared.dart',
      );
    });

    test('rejected: presentation importing its own feature module', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/alpha_module.dart': alphaModule,
          'lib/features/alpha/presentation/screens/uses_module.dart': '''
import '../../alpha_module.dart';

final Object locator = alphaLocator;
''',
        }),
        'module-import',
        'presentation reaching the locator through alpha_module.dart',
      );
    });

    test('rejected: domain importing its own feature module', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/features/alpha/alpha_module.dart': alphaModule,
          'lib/features/alpha/domain/services/uses_module.dart': '''
import '../../alpha_module.dart';

final Object locator = alphaLocator;
''',
        }),
        'module-import',
        'domain reaching the locator through alpha_module.dart',
      );
    });

    test('accepted: the service locator imports a feature module, and a '
        'lib/shared/ file holds pure infrastructure', () async {
      await expectClean(
        fixtureWith(<String, String>{
          'lib/features/alpha/alpha_module.dart': alphaModule,
          'lib/core/di/service_locator.dart': withImport(
            fixtureApp['lib/core/di/service_locator.dart']!,
            "import '../../features/alpha/alpha_module.dart';",
          ),
          'lib/shared/formatting.dart': '''
String shout(String value) => value.toUpperCase();
''',
        }),
        'module imported by its composition root; rule-abiding lib/shared/',
      );
    });
  });

  group('app state (lib/app_state/)', () {
    /// App-wide state reading the alpha feature through its public barrel.
    const String walletState = '''
import '../features/alpha/alpha.dart';

class WalletState {
  const WalletState(this.model);
  final AlphaModel model;
}
''';

    test('accepted: app state reads a barrel; presentation and app.dart '
        'consume it', () async {
      await expectClean(
        fixtureWith(<String, String>{
          'lib/app_state/wallet_state.dart': walletState,
          'lib/features/beta/presentation/wallet_badge.dart': '''
import '../../../app_state/wallet_state.dart';

String badge(WalletState state) => state.model.id;
''',
          'lib/app.dart': withImport(
            fixtureApp['lib/app.dart']!,
            "import 'app_state/wallet_state.dart';",
          ),
        }),
        'app state over a barrel, consumed by presentation and app.dart',
      );
    });

    test('rejected: app state importing feature internals', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/app_state/wallet_state.dart': '''
import '../features/alpha/data/datasources/alpha_remote_datasource.dart';

Object source() => AlphaRemoteDataSource();
''',
        }),
        'app-state-imports-internals',
        'app state reaching into alpha/data',
      );
    });

    test('rejected: domain depending on app state', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/app_state/wallet_state.dart': walletState,
          'lib/features/beta/domain/models/uses_wallet.dart': '''
import '../../../../app_state/wallet_state.dart';

String id(WalletState state) => state.model.id;
''',
        }),
        'app-state-access',
        'beta domain importing app state',
      );
    });

    test('rejected: core depending on app state', () async {
      await expectViolation(
        fixtureWith(<String, String>{
          'lib/app_state/wallet_state.dart': walletState,
          'lib/core/wallet_format.dart': '''
import '../app_state/wallet_state.dart';

String format(WalletState state) => state.model.id;
''',
        }),
        'app-state-access',
        'core importing app state',
      );
    });
  });
}
