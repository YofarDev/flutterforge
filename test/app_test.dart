import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_flutter_app/app.dart';
import 'package:my_flutter_app/core/di/service_locator.dart';
import 'package:my_flutter_app/core/router/app_router.dart';
import 'package:my_flutter_app/features/home/data/models/home_data_dto.dart';

import 'support/fake_home_data_source.dart';

/// Boot smoke tests for the real dependency graph: real DI composition, real
/// router, real cubits and repositories — only the network seam is replaced by
/// an immediately-resolving fake data source.
///
/// These are widget tests of app wiring, not device-level integration tests.
/// Cross-screen flows (navigation, failure/retry, disposal with pending work)
/// live in `test/features/home/home_flow_test.dart`.
void main() {
  late ScriptedHomeDataSource dataSource;

  setUp(() async {
    dataSource = ScriptedHomeDataSource();
    await getIt.reset();
    await setupServiceLocator(homeRemoteDataSourceOverride: dataSource);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('app boots on the home route and renders the loaded screen', (
    WidgetTester tester,
  ) async {
    dataSource.enqueue(
      () async => const HomeDataDto(
        welcomeMessage: 'Boot smoke',
        lastUpdated: '2024-01-01T00:00:00.000',
      ),
    );

    final GoRouter router = AppRouter.createRouter();
    await tester.pumpWidget(MyApp(router: router));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Boot smoke'), findsOneWidget);

    // Dispose the injected router explicitly and unmount the tree so the
    // route-owned cubits close before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    router.dispose();
  });

  testWidgets('the default (non-injected) router ownership also works', (
    WidgetTester tester,
  ) async {
    dataSource.enqueue(
      () async => const HomeDataDto(
        welcomeMessage: 'Default ownership',
        lastUpdated: '2024-01-01T00:00:00.000',
      ),
    );

    // MyApp creates and owns its own router when none is injected; the
    // internally owned router is disposed with the widget's state.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Default ownership'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('rebuilding the root widget retains the route and state of the '
      'default-owned router', (WidgetTester tester) async {
    dataSource.enqueue(
      () async => const HomeDataDto(
        welcomeMessage: 'Rebuild me',
        lastUpdated: '2024-01-01T00:00:00.000',
      ),
    );

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);

    // Navigate to the counter and change its state.
    await tester.tap(find.text('Try the Counter Demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increment'));
    await tester.pumpAndSettle();
    expect(find.text('Counter Demo'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Rebuild the same root element (as a locale/theme change above MyApp
    // would): a new MyApp instance must NOT create a replacement router.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Still on the counter route with its state — not reset to Home/0.
    expect(find.text('Counter Demo'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Rebuild me'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'an injected router stays caller-owned: MyApp does not dispose it',
    (WidgetTester tester) async {
      dataSource.enqueue(
        () async => const HomeDataDto(
          welcomeMessage: 'Injected',
          lastUpdated: '2024-01-01T00:00:00.000',
        ),
      );

      final GoRouter router = AppRouter.createRouter();
      await tester.pumpWidget(MyApp(router: router));
      await tester.pumpAndSettle();
      expect(find.text('Injected'), findsOneWidget);

      // Unmount MyApp: the caller's router must remain usable.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Re-attaching the same router instance only works when MyApp did not
      // dispose it (a disposed GoRouter cannot serve as routerConfig).
      dataSource.enqueue(
        () async => const HomeDataDto(
          welcomeMessage: 'Reattached',
          lastUpdated: '2024-01-01T00:00:00.000',
        ),
      );
      await tester.pumpWidget(MyApp(router: router));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Reattached'), findsOneWidget);

      // Caller-side disposal works.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      router.dispose();
    },
  );
}
