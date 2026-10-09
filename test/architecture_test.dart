import 'package:flutter_test/flutter_test.dart';

import 'support/architecture_checker.dart';

/// Architecture boundary gate for the real application's `lib/` tree.
///
/// The rules are enforced by the analyzer-based checker in
/// `test/support/architecture_checker.dart` (see its documentation and the
/// checker's own regression tests in `test/architecture_checker_test.dart`
/// for the rule-by-rule fixtures):
///
/// 1. Inward dependencies — presentation never imports data; domain never
///    imports data or presentation; data never imports presentation.
/// 2. Domain purity — no Flutter UI libraries, generated localizations,
///    router, DI, theme or logger in domain.
/// 3. Cross-feature access — only designated public domain barrels.
/// 4. Public barrels expose domain contracts only.
/// 5. Core stays infrastructure-only outside designated composition roots.
/// 6. No production component stores a Cubit/Bloc dependency (nullable, late,
///    mutable, aliased, generic and inherited types included).
/// 7. Locator access — get_it resolution (imports of `package:get_it` and
///    references to the app's `getIt`) is limited to `lib/app.dart`,
///    `lib/core/di/service_locator.dart` and
///    `lib/core/router/app_router.dart`; importing `service_locator.dart` is
///    additionally allowed from `lib/main.dart` for bootstrap setup only;
///    registration only in `service_locator.dart`.
/// 8. `lib/main.dart` is a bootstrap, never a second registration site.
///
/// A run with checker errors (syntax problems, unresolved imports) fails the
/// gate: the checker never passes code it could not analyze.
///
/// When you add a rule to the flutter-architecture skill, add it to the
/// checker and give it fixtures in `architecture_checker_test.dart`.
void main() {
  test('lib/ respects the architecture boundaries', () async {
    final CheckerResult result = await ArchitectureChecker.checkDirectory();
    expect(
      result.errors,
      isEmpty,
      reason:
          'The architecture checker could not analyze the following files; '
          'the gate fails closed until these are fixed:\n'
          '${result.errors.join('\n')}',
    );
    expect(
      result.violations,
      isEmpty,
      reason:
          'Architecture boundary violations:\n'
          '${result.violations.join('\n')}',
    );
  });
}
