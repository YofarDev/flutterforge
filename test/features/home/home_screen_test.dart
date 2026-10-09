import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/di/service_locator.dart';
import 'package:my_flutter_app/core/l10n/generated/app_localizations.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/home/domain/models/home_data.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_cubit.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_state.dart';
import 'package:my_flutter_app/features/home/presentation/screens/home_screen.dart';

class MockHomeCubit extends Mock implements HomeCubit {}

/// Fake cubit so tests can push states without driving the real repository.
class FakeHomeCubit extends Cubit<HomeState> implements HomeCubit {
  FakeHomeCubit() : super(const HomeState.initial());

  int refreshCalls = 0;

  void pushState(HomeState nextState) => emit(nextState);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }
}

/// Widget tests for the HomeScreen (a single screen widget — there is no
/// separate View to forward to).
void main() {
  setUpAll(() {
    registerFallbackValue(const HomeState.initial());
    registerFallbackValue(
      HomeData(welcomeMessage: '', lastUpdated: DateTime(2024)),
    );
  });

  group('HomeScreen', () {
    late MockHomeCubit mockHomeCubit;

    setUp(() {
      mockHomeCubit = MockHomeCubit();
      getIt.reset();
      getIt.registerFactory<HomeCubit>(() => mockHomeCubit);

      when(() => mockHomeCubit.initialize()).thenAnswer((_) async {});
      when(() => mockHomeCubit.state)
          .thenReturn(const HomeState.loaded(welcomeMessage: ''));
      when(() => mockHomeCubit.stream)
          .thenAnswer((_) => const Stream<HomeState>.empty());
      when(() => mockHomeCubit.close()).thenAnswer((_) async {});
    });

    testWidgets('provides HomeCubit', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider<HomeCubit>.value(
            value: mockHomeCubit,
            child: const HomeScreen(),
          ),
        ),
      );

      final Element context = tester.element(find.byType(HomeScreen));
      expect(context.read<HomeCubit>(), isNotNull);
    });
  });

  group('HomeScreen states', () {
    late FakeHomeCubit fakeHomeCubit;

    setUp(() {
      fakeHomeCubit = FakeHomeCubit();
      getIt.reset();
      getIt.registerFactory<HomeCubit>(() => fakeHomeCubit);
    });

    tearDown(() {
      fakeHomeCubit.close();
    });

    Widget buildTestableWidget(
      Widget child, {
      Locale locale = const Locale('en'),
    }) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: BlocProvider<HomeCubit>.value(value: fakeHomeCubit, child: child),
      );
    }

    testWidgets('shows a spinner in the initial state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeScreen()));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows a spinner in the loading state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeScreen()));

      fakeHomeCubit.pushState(const HomeState.loading());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays welcome message when loaded', (
      WidgetTester tester,
    ) async {
      const String welcomeMessage = 'Test Welcome Message';

      await tester.pumpWidget(buildTestableWidget(const HomeScreen()));

      fakeHomeCubit.pushState(
        const HomeState.loaded(welcomeMessage: welcomeMessage),
      );
      await tester.pump();

      expect(find.text(welcomeMessage), findsOneWidget);
    });

    testWidgets('falls back to the localized welcome when message is empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeScreen()));

      fakeHomeCubit.pushState(const HomeState.loaded(welcomeMessage: ''));
      await tester.pump();

      // homeWelcome = 'Welcome to the app!'
      expect(find.text('Welcome to the app!'), findsOneWidget);
    });

    testWidgets(
      'trims whitespace-only messages before falling back (presentation transformation)',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildTestableWidget(const HomeScreen()));

        fakeHomeCubit.pushState(
          const HomeState.loaded(welcomeMessage: '   \t\n '),
        );
        await tester.pump();

        expect(find.text('Welcome to the app!'), findsOneWidget);
      },
    );

    testWidgets('displays the localized failure and retries on failure', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeScreen()));

      fakeHomeCubit.pushState(
        const HomeState.failure(failure: Failure.networkError()),
      );
      await tester.pump();

      // The category is localized (English), not a raw exception string.
      expect(
        find.text('Network error. Please check your connection.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(fakeHomeCubit.refreshCalls, 1);
    });

    testWidgets('renders every failure category in English', (
      WidgetTester tester,
    ) async {
      final Map<Failure, String> cases = <Failure, String>{
        const Failure.networkError():
            'Network error. Please check your connection.',
        const Failure.unauthorized(): 'You are not authorized.',
        const Failure.serverError(message: 'ignored'):
            'A server error occurred. Please try again later.',
        const Failure.unexpected(): 'An error occurred',
      };

      for (final MapEntry<Failure, String> entry in cases.entries) {
        await tester.pumpWidget(buildTestableWidget(const HomeScreen()));
        fakeHomeCubit.pushState(HomeState.failure(failure: entry.key));
        // Two pumps: the first flushes the emission, the second draws it —
        // needed when a previous loop iteration already delivered an emission.
        await tester.pump();
        await tester.pump();

        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: 'en rendering of ${entry.key.runtimeType}',
        );
      }
    });

    testWidgets('renders every failure category in French', (
      WidgetTester tester,
    ) async {
      final Map<Failure, String> cases = <Failure, String>{
        const Failure.networkError():
            'Erreur réseau. Vérifiez votre connexion.',
        const Failure.unauthorized(): "Vous n'êtes pas autorisé.",
        const Failure.serverError(message: 'ignoré'):
            'Une erreur de serveur est survenue. Réessayez plus tard.',
        const Failure.unexpected(): "Une erreur s'est produite",
      };

      for (final MapEntry<Failure, String> entry in cases.entries) {
        await tester.pumpWidget(
          buildTestableWidget(const HomeScreen(), locale: const Locale('fr')),
        );
        fakeHomeCubit.pushState(HomeState.failure(failure: entry.key));
        await tester.pump();
        await tester.pump();

        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: 'fr rendering of ${entry.key.runtimeType}',
        );
      }
    });

    testWidgets('never renders diagnostic details carried by the failure', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeScreen()));

      fakeHomeCubit.pushState(
        const HomeState.failure(
          failure: Failure.serverError(message: 'SECRET-DIAGNOSTIC-42'),
        ),
      );
      await tester.pump();

      expect(find.text('SECRET-DIAGNOSTIC-42'), findsNothing);
      expect(find.textContaining('SECRET-DIAGNOSTIC'), findsNothing);
      expect(
        find.text('A server error occurred. Please try again later.'),
        findsOneWidget,
      );
    });

    testWidgets('changing the locale updates an existing error state message', (
      WidgetTester tester,
    ) async {
      // Existing error state, rendered in English.
      fakeHomeCubit.pushState(
        const HomeState.failure(failure: Failure.networkError()),
      );

      await tester.pumpWidget(buildTestableWidget(const HomeScreen()));
      expect(
        find.text('Network error. Please check your connection.'),
        findsOneWidget,
      );

      // Rebuild the same (unchanged) error state under a French locale.
      await tester.pumpWidget(
        buildTestableWidget(const HomeScreen(), locale: const Locale('fr')),
      );
      await tester.pump();

      expect(
        find.text('Erreur réseau. Vérifiez votre connexion.'),
        findsOneWidget,
      );
      expect(
        find.text('Network error. Please check your connection.'),
        findsNothing,
      );
    });

    testWidgets('displays Home title', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(const HomeScreen()));

      expect(find.text('Home'), findsOneWidget);
    });
  });
}
