import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/app.dart';
import 'package:my_flutter_app/core/di/service_locator.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_cubit.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_state.dart';
import 'package:my_flutter_app/features/home/domain/services/home_service.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_cubit.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_state.dart';

class MockHomeCubit extends Mock implements HomeCubit {}

class MockCounterCubit extends Mock implements CounterCubit {}

class MockHomeService extends Mock implements HomeService {}

/// Integration/Smoke tests for the entire app.
///
/// These tests verify that:
/// - The app starts without errors
/// - Basic navigation works
/// - The app renders correctly
void main() {
  late MockHomeCubit mockHomeCubit;
  late MockCounterCubit mockCounterCubit;

  setUpAll(() {
    registerFallbackValue(const HomeState());
    registerFallbackValue(const CounterState());
  });

  setUp(() async {
    mockHomeCubit = MockHomeCubit();
    mockCounterCubit = MockCounterCubit();

    // Setup stubs for initial app state
    when(() => mockHomeCubit.state).thenReturn(const HomeState());
    when(
      () => mockHomeCubit.stream,
    ).thenAnswer((_) => const Stream<HomeState>.empty());
    when(() => mockHomeCubit.initialize()).thenAnswer((_) async {});
    when(() => mockHomeCubit.close()).thenAnswer((_) async {});

    when(() => mockCounterCubit.state).thenReturn(const CounterState());
    when(
      () => mockCounterCubit.stream,
    ).thenAnswer((_) => const Stream<CounterState>.empty());
    when(() => mockCounterCubit.close()).thenAnswer((_) async {});

    getIt.reset();
    await setupServiceLocator();
    // Unregister the cubits registered by setupServiceLocator and replace with mocks
    getIt.unregister<HomeCubit>();
    getIt.unregister<CounterCubit>();
    getIt.registerFactory<HomeCubit>(() => mockHomeCubit);
    getIt.registerFactory<CounterCubit>(() => mockCounterCubit);
  });

  group('MyApp', () {
    testWidgets('app starts and shows home screen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Verify app title is present (in home screen)
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('app has correct localization', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Verify welcome text from localization is shown (homeWelcome = 'Welcome to the app!')
      expect(find.text('Welcome to the app!'), findsOneWidget);
    });
  });
}
