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
/// These verify the union-state lifecycle: loading, loaded, and — critically —
/// that a repository failure becomes a visible failure state instead of being
/// swallowed.
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

    test('initial state is HomeState.initial', () {
      expect(homeCubit.state, const HomeState.initial());
    });

    group('initialize', () {
      blocTest<HomeCubit, HomeState>(
        'emits [loading, loaded] when load succeeds',
        setUp: () {
          when(() => mockHomeService.loadHomeData()).thenAnswer(
            (_) async => Right<Failure, HomeData>(
              HomeData(
                welcomeMessage: 'Welcome to the app!',
                lastUpdated: DateTime(2024),
              ),
            ),
          );
          when(() => mockHomeService.formatWelcomeMessage(any()))
              .thenReturn('Welcome to the app!');
        },
        build: () => homeCubit,
        act: (HomeCubit cubit) => cubit.initialize(),
        expect: () => <HomeState>[
          const HomeState.loading(),
          const HomeState.loaded(welcomeMessage: 'Welcome to the app!'),
        ],
      );

      blocTest<HomeCubit, HomeState>(
        'emits [loading, failure] when load fails',
        setUp: () {
          when(() => mockHomeService.loadHomeData()).thenAnswer(
            (_) async => const Left<Failure, HomeData>(Failure.networkError()),
          );
        },
        build: () => homeCubit,
        act: (HomeCubit cubit) => cubit.initialize(),
        expect: () => <HomeState>[
          const HomeState.loading(),
          const HomeState.failure(message: 'Network error occurred'),
        ],
      );
    });

    group('refresh', () {
      blocTest<HomeCubit, HomeState>(
        'reloads data from the loading state',
        setUp: () {
          when(() => mockHomeService.loadHomeData()).thenAnswer(
            (_) async => Right<Failure, HomeData>(
              HomeData(
                welcomeMessage: 'Refreshed!',
                lastUpdated: DateTime(2024),
              ),
            ),
          );
          when(() => mockHomeService.formatWelcomeMessage(any()))
              .thenReturn('Refreshed!');
        },
        build: () => homeCubit,
        seed: () => const HomeState.loaded(welcomeMessage: 'Stale'),
        act: (HomeCubit cubit) => cubit.refresh(),
        expect: () => <HomeState>[
          const HomeState.loading(),
          const HomeState.loaded(welcomeMessage: 'Refreshed!'),
        ],
      );
    });
  });
}
