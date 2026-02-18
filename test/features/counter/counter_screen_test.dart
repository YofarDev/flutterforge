import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/core/l10n/generated/app_localizations.dart';
import 'package:my_flutter_app/features/counter/bloc/counter_cubit.dart';
import 'package:my_flutter_app/features/counter/screens/counter_screen.dart';

/// Widget tests for the CounterScreen and CounterView.
///
/// These tests verify that:
/// - UI elements are rendered correctly
/// - User interactions trigger the correct cubit methods
/// - State changes are reflected in the UI
void main() {
  group('CounterScreen', () {
    testWidgets('renders CounterView', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CounterScreen(),
        ),
      );

      expect(find.byType(CounterView), findsOneWidget);
    });

    testWidgets('provides CounterCubit', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CounterScreen(),
        ),
      );

      final Element context = tester.element(find.byType(CounterView));
      expect(context.read<CounterCubit>(), isNotNull);
    });
  });

  group('CounterView', () {
    late CounterCubit counterCubit;

    setUp(() {
      counterCubit = CounterCubit();
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
