import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_flutter_app/core/bloc/latest_request_wins.dart';
import 'package:my_flutter_app/core/l10n/app_localization_delegates.dart';
import 'package:my_flutter_app/core/l10n/generated/app_localizations.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_cubit.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_state.dart';
import 'package:my_flutter_app/features/home/presentation/screens/home_screen.dart';

/// Fake cubit so tests can push states without driving the real repository.
class FakeHomeCubit extends Cubit<HomeState>
    with LatestRequestWins<HomeState>
    implements HomeCubit {
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

/// Widget tests for the HomeScreen: what each state renders and the retry
/// action. Failure-category copy is covered by the pure-function test in
/// `test/core/l10n/failure_localization_test.dart`.
void main() {
  group('HomeScreen states', () {
    late FakeHomeCubit fakeHomeCubit;

    setUp(() {
      fakeHomeCubit = FakeHomeCubit();
    });

    tearDown(() {
      fakeHomeCubit.close();
    });

    Widget buildTestableWidget(Widget child) {
      return MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<HomeCubit>.value(value: fakeHomeCubit, child: child),
      );
    }

    testWidgets('shows a spinner in the initial and loading states', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const HomeScreen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

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

    testWidgets('displays Home title', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(const HomeScreen()));

      expect(find.text('Home'), findsOneWidget);
    });
  });
}
