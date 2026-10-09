import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_flutter_app/app.dart';
import 'package:my_flutter_app/core/di/service_locator.dart';
import 'package:my_flutter_app/core/router/app_router.dart';
import 'package:my_flutter_app/features/counter/data/datasources/counter_local_datasource.dart';
import 'package:my_flutter_app/features/counter/data/models/counter_settings_dto.dart';
import 'package:my_flutter_app/features/home/data/models/home_data_dto.dart';

import '../../support/fake_counter_data_source.dart';
import '../../support/fake_home_data_source.dart';

/// Real-component feature-flow tests for the home → counter navigation.
///
/// Everything runs the production wiring: the real DI composition (only the
/// two data-source seams are overridden with fakes via
/// `setupServiceLocator`), the real router (a fresh instance per test,
/// explicitly injected and disposed), real repositories, real
/// `CounterService`, and real cubits provided by the routes.
///
/// Naming note: these are widget tests of the in-process dependency chain and
/// navigation. They are not device-level integration tests and do not prove a
/// platform build. No network, no timers — pending responses are controlled
/// with `Completer`s.
void main() {
  late ScriptedHomeDataSource homeDataSource;
  late ICounterLocalDataSource counterDataSource;

  // Full composition with narrow data-source overrides; the dependency graph
  // itself is never duplicated here.
  Future<void> configureApp({ICounterLocalDataSource? counterOverride}) async {
    homeDataSource = ScriptedHomeDataSource();
    counterDataSource =
        counterOverride ??
        FakeCounterLocalDataSource(const CounterSettingsDto());
    await getIt.reset();
    await setupServiceLocator(
      counterLocalDataSourceOverride: counterDataSource,
      homeRemoteDataSourceOverride: homeDataSource,
    );
  }

  // Each test gets its own router; MyApp never creates one per build.
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final GoRouter router = AppRouter.createRouter();
    await tester.pumpWidget(MyApp(router: router));
    await tester.pump();
    return router;
  }

  // Unmount the tree (closing route-owned cubits), dispose the injected
  // router, and await the asynchronous getIt reset.
  Future<void> disposeApp(WidgetTester tester, GoRouter router) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    router.dispose();
    await getIt.reset();
  }

  tearDown(() async {
    await getIt.reset();
  });

  void enqueueSuccess({String welcomeMessage = 'Flow welcome'}) {
    homeDataSource.enqueue(
      () async => HomeDataDto(
        welcomeMessage: welcomeMessage,
        lastUpdated: DateTime(2024, 1, 1).toIso8601String(),
      ),
    );
  }

  testWidgets(
    'loads home data from loading to success through the real chain',
    (WidgetTester tester) async {
      await configureApp();
      final Completer<HomeDataDto> pending = Completer<HomeDataDto>();
      homeDataSource.enqueue(() => pending.future);

      final GoRouter router = await pumpApp(tester);

      // The route created a real HomeCubit which is awaiting the repository.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);

      pending.complete(
        HomeDataDto(
          welcomeMessage: 'Flow welcome',
          lastUpdated: DateTime(2024, 1, 1).toIso8601String(),
        ),
      );
      await tester.pump();

      expect(find.text('Flow welcome'), findsOneWidget);
      expect(homeDataSource.calls, 1);

      await disposeApp(tester, router);
    },
  );

  testWidgets(
    'malformed payload renders a localized error and a retry succeeds',
    (WidgetTester tester) async {
      await configureApp();
      // First response: a real DTO whose lastUpdated is not a date. The REAL
      // repository must catch the FormatException from toDomain() and map it
      // to a typed failure — nothing is thrown from a mock callback.
      homeDataSource.enqueue(
        () async => const HomeDataDto(
          welcomeMessage: 'broken',
          lastUpdated: 'not-a-date',
        ),
      );
      enqueueSuccess(welcomeMessage: 'Recovered');

      final GoRouter router = await pumpApp(tester);
      await tester.pump();

      // Failure.unexpected localized at build time (English), with no
      // diagnostic leakage.
      expect(find.text('An error occurred'), findsOneWidget);
      expect(find.text('not-a-date'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(find.text('Recovered'), findsOneWidget);
      expect(homeDataSource.calls, 2);

      await disposeApp(tester, router);
    },
  );

  testWidgets(
    'navigates to the counter and back, recreating route-scoped counter state',
    (WidgetTester tester) async {
      await configureApp();
      enqueueSuccess();

      final GoRouter router = await pumpApp(tester);
      await tester.pump();
      expect(find.text('Flow welcome'), findsOneWidget);

      // Navigate to the counter route: a fresh CounterCubit is created by the
      // route (default settings through the real service).
      await tester.tap(find.text('Try the Counter Demo'));
      await tester.pumpAndSettle();

      expect(find.text('Counter Demo'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      await tester.tap(find.byTooltip('Increment'));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      // Back: the counter route's cubit is disposed; the home cubit (still on
      // the stack below) keeps its loaded state.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Flow welcome'), findsOneWidget);
      expect(find.text('Counter Demo'), findsNothing);

      // Pushing the counter route again recreates its state per policy: a new
      // cubit starts at 0, not at the previous visit's 1.
      await tester.tap(find.text('Try the Counter Demo'));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsNothing);

      await disposeApp(tester, router);
    },
  );

  testWidgets(
    'counter applies non-default settings and bounds through the real service',
    (WidgetTester tester) async {
      await configureApp(
        counterOverride: FakeCounterLocalDataSource(
          const CounterSettingsDto(stepSize: 3, minValue: 0, maxValue: 5),
        ),
      );
      enqueueSuccess();

      final GoRouter router = await pumpApp(tester);
      await tester.pump();

      await tester.tap(find.text('Try the Counter Demo'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Increment'));
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);

      // 3 + 3 = 6 is clamped to maxValue 5 by the real CounterService.
      await tester.tap(find.byTooltip('Increment'));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);

      // 5 - 3 = 2.
      await tester.tap(find.byTooltip('Decrement'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);

      await disposeApp(tester, router);
    },
  );

  testWidgets(
    'counter falls back to default settings when the persistence read fails',
    (WidgetTester tester) async {
      await configureApp(counterOverride: FailingCounterLocalDataSource());
      enqueueSuccess();

      final GoRouter router = await pumpApp(tester);
      await tester.pump();

      await tester.tap(find.text('Try the Counter Demo'));
      await tester.pumpAndSettle();

      // The real repository maps the datasource exception to a typed failure
      // and the real cubit applies the documented default-settings fallback,
      // so the user's increment is not dropped.
      await tester.tap(find.byTooltip('Increment'));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      await disposeApp(tester, router);
    },
  );

  testWidgets(
    'unmounting the app with a pending request closes the cubit without throwing',
    (WidgetTester tester) async {
      await configureApp();
      final Completer<HomeDataDto> neverResolved = Completer<HomeDataDto>();
      homeDataSource.enqueue(() => neverResolved.future);

      final GoRouter router = await pumpApp(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Unmount while the repository call is still pending; the route-owned
      // HomeCubit closes with work in flight.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Completing after close must not throw (request-id/close guard); a
      // FlutterError here would fail the test.
      neverResolved.complete(
        HomeDataDto(
          welcomeMessage: 'late',
          lastUpdated: DateTime(2024, 1, 1).toIso8601String(),
        ),
      );
      await tester.pump();
      await tester.pump();

      router.dispose();
      await getIt.reset();
    },
  );
}
