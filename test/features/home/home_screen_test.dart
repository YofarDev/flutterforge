import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/di/service_locator.dart';
import 'package:my_flutter_app/core/l10n/generated/app_localizations.dart';
import 'package:my_flutter_app/features/home/domain/models/home_data.dart';
import 'package:my_flutter_app/features/home/domain/services/home_service.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_cubit.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_state.dart';
import 'package:my_flutter_app/features/home/presentation/screens/home_screen.dart';

class MockHomeService extends Mock implements HomeService {}

class MockHomeCubit extends Mock implements HomeCubit {}

/// Fake cubit so tests can push states without driving the real service.
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

/// Widget tests for the HomeScreen and HomeView.
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

    testWidgets('renders HomeView', (WidgetTester tester) async {
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

      expect(find.byType(HomeView), findsOneWidget);
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

      final Element context = tester.element(find.byType(HomeView));
      expect(context.read<HomeCubit>(), isNotNull);
    });
  });

  group('HomeView', () {
    late FakeHomeCubit fakeHomeCubit;

    setUp(() {
      fakeHomeCubit = FakeHomeCubit();
      getIt.reset();
      getIt.registerFactory<HomeCubit>(() => fakeHomeCubit);
    });

    tearDown(() {
      fakeHomeCubit.close();
    });

    Widget buildTestableWidget(Widget child) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<HomeCubit>.value(value: fakeHomeCubit, child: child),
      );
    }

    testWidgets('shows a spinner in the initial state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeView()));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows a spinner in the loading state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeView()));

      fakeHomeCubit.pushState(const HomeState.loading());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays welcome message when loaded', (
      WidgetTester tester,
    ) async {
      const String welcomeMessage = 'Test Welcome Message';

      await tester.pumpWidget(buildTestableWidget(const HomeView()));

      fakeHomeCubit.pushState(
        const HomeState.loaded(welcomeMessage: welcomeMessage),
      );
      await tester.pump();

      expect(find.text(welcomeMessage), findsOneWidget);
    });

    testWidgets('falls back to the localized welcome when message is empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeView()));

      fakeHomeCubit.pushState(const HomeState.loaded(welcomeMessage: ''));
      await tester.pump();

      // homeWelcome = 'Welcome to the app!'
      expect(find.text('Welcome to the app!'), findsOneWidget);
    });

    testWidgets('displays error message and retries on failure', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeView()));

      fakeHomeCubit.pushState(const HomeState.failure(message: 'Boom'));
      await tester.pump();

      expect(find.text('Boom'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(fakeHomeCubit.refreshCalls, 1);
    });

    testWidgets('displays Home title', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(const HomeView()));

      expect(find.text('Home'), findsOneWidget);
    });
  });
}
