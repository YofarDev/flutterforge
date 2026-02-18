import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/core/l10n/generated/app_localizations.dart';
import 'package:my_flutter_app/features/home/bloc/home_cubit.dart';
import 'package:my_flutter_app/features/home/screens/home_screen.dart';

/// Widget tests for the HomeScreen and HomeView.
///
/// These tests verify that:
/// - UI elements are rendered correctly
/// - Loading state is shown during initialization
/// - Welcome message is displayed after loading
void main() {
  group('HomeScreen', () {
    testWidgets('renders HomeView', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(find.byType(HomeView), findsOneWidget);
    });

    testWidgets('provides HomeCubit', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      final Element context = tester.element(find.byType(HomeView));
      expect(context.read<HomeCubit>(), isNotNull);
    });
  });

  group('HomeView', () {
    late HomeCubit homeCubit;

    setUp(() {
      homeCubit = HomeCubit();
    });

    tearDown(() {
      homeCubit.close();
    });

    Widget buildTestableWidget(Widget child) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<HomeCubit>.value(value: homeCubit, child: child),
      );
    }

    testWidgets('displays loading indicator when isLoading is true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeView()));

      // Initial state should not show loading (isLoading: false)
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Emit loading state
      homeCubit.emit(const HomeState(isLoading: true));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays welcome message when provided', (
      WidgetTester tester,
    ) async {
      const String welcomeMessage = 'Test Welcome Message';

      await tester.pumpWidget(buildTestableWidget(const HomeView()));

      homeCubit.emit(
        const HomeState(isLoading: false, welcomeMessage: welcomeMessage),
      );
      await tester.pump();

      expect(find.text(welcomeMessage), findsOneWidget);
    });

    testWidgets('displays default welcome when message is empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeView()));

      // Should show default welcome text from localization (homeWelcome = 'Welcome to the app!')
      expect(find.text('Welcome to the app!'), findsOneWidget);
    });

    testWidgets('displays Home title', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(const HomeView()));

      expect(find.text('Home'), findsOneWidget);
    });
  });
}
