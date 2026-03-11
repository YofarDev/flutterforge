import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/home/domain/models/home_data.dart';
import 'package:my_flutter_app/features/home/domain/services/home_service.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_cubit.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_state.dart';

class MockHomeService extends Mock implements HomeService {}

/// Tests for the HomeCubit.
///
/// These tests verify the business logic of the home feature,
/// particularly the async initialization and state management.
void main() {
  setUpAll(() {
    registerFallbackValue(
      HomeData(welcomeMessage: '', lastUpdated: DateTime(2024)),
    );
  });

  group('HomeCubit', () {
    late HomeCubit homeCubit;
    late MockHomeService mockHomeService;

    setUp(() {
      mockHomeService = MockHomeService();
      homeCubit = HomeCubit(mockHomeService);
    });

    tearDown(() {
      homeCubit.close();
    });

    test('initial state has isLoading false and empty welcomeMessage', () {
      expect(
        homeCubit.state,
        const HomeState(isLoading: false, welcomeMessage: ''),
      );
    });

    group('initialize', () {
      blocTest<HomeCubit, HomeState>(
        'emits loading state then loaded state with welcome message',
        setUp: () {
          when(() => mockHomeService.loadHomeData()).thenAnswer(
            (_) async => Right<Failure, HomeData>(
              HomeData(
                welcomeMessage: 'Welcome to the app!',
                lastUpdated: DateTime(2024),
              ),
            ),
          );
          when(
            () => mockHomeService.formatWelcomeMessage(any()),
          ).thenReturn('Welcome to the app!');
        },
        build: () => homeCubit,
        act: (HomeCubit cubit) => cubit.initialize(),
        expect: () => <HomeState>[
          const HomeState(isLoading: true, welcomeMessage: ''),
          const HomeState(
            isLoading: false,
            welcomeMessage: 'Welcome to the app!',
          ),
        ],
      );

      blocTest<HomeCubit, HomeState>(
        'emits loading state then failure state (isLoading: false) on error',
        setUp: () {
          when(() => mockHomeService.loadHomeData()).thenAnswer(
            (_) async => const Left<Failure, HomeData>(
              Failure.serverError(message: 'error'),
            ),
          );
        },
        build: () => homeCubit,
        act: (HomeCubit cubit) => cubit.initialize(),
        expect: () => <HomeState>[
          const HomeState(isLoading: true, welcomeMessage: ''),
          const HomeState(isLoading: false, welcomeMessage: ''),
        ],
      );
    });

    group('refresh', () {
      blocTest<HomeCubit, HomeState>(
        're-initializes when refresh is called',
        setUp: () {
          when(() => mockHomeService.loadHomeData()).thenAnswer(
            (_) async => Right<Failure, HomeData>(
              HomeData(
                welcomeMessage: 'Welcome to the app!',
                lastUpdated: DateTime(2024),
              ),
            ),
          );
          when(
            () => mockHomeService.formatWelcomeMessage(any()),
          ).thenReturn('Welcome to the app!');
        },
        build: () => homeCubit,
        seed: () => const HomeState(
          isLoading: false,
          welcomeMessage: 'Previous message',
        ),
        act: (HomeCubit cubit) => cubit.refresh(),
        expect: () => <HomeState>[
          const HomeState(isLoading: true, welcomeMessage: 'Previous message'),
          const HomeState(
            isLoading: false,
            welcomeMessage: 'Welcome to the app!',
          ),
        ],
      );
    });
  });
}
