import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/di/service_locator.dart';
import 'package:my_flutter_app/core/l10n/generated/app_localizations.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/counter/domain/models/counter_settings.dart';
import 'package:my_flutter_app/features/counter/domain/services/counter_service.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_cubit.dart';
import 'package:my_flutter_app/features/counter/presentation/screens/counter_screen.dart';

class MockCounterService extends Mock implements CounterService {}

/// Behavior tests for the counter UI driven by a real CounterCubit.
void main() {
  setUpAll(() {
    registerFallbackValue(const CounterSettings());
  });

  group('CounterView', () {
    late CounterCubit counterCubit;
    late MockCounterService mockCounterService;

    setUp(() {
      mockCounterService = MockCounterService();
      counterCubit = CounterCubit(mockCounterService);

      getIt.reset();
      getIt.registerFactory<CounterCubit>(() => counterCubit);

      // Default stubs
      when(() => mockCounterService.getSettings()).thenAnswer(
        (_) async => const Right<Failure, CounterSettings>(CounterSettings()),
      );
      when(() => mockCounterService.clampValue(any(), any())).thenAnswer(
        (Invocation invocation) => invocation.positionalArguments[0] as int,
      );
      when(() => mockCounterService.applyStepSize(any(), any()))
          .thenAnswer((Invocation invocation) {
            final int val = invocation.positionalArguments[0] as int;
            final CounterSettings settings =
                invocation.positionalArguments[1] as CounterSettings;
            return val + settings.stepSize;
          });
    });

    tearDown(() {
      counterCubit.close();
    });

    Widget buildTestableWidget(Widget child) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<CounterCubit>.value(
          value: counterCubit,
          child: child,
        ),
      );
    }

    testWidgets('displays initial count of 0', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(const CounterView()));

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('increments count when + button is tapped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const CounterView()));

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('decrements count when - button is tapped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const CounterView()));

      // First increment to have a positive number
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Then decrement
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('resets count when reset button is tapped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const CounterView()));

      // Increment a few times
      await tester.tap(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);

      // Reset
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('displays counter title', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(const CounterView()));

      expect(find.text('Counter Demo'), findsOneWidget);
    });
  });
}
