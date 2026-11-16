import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/home/domain/models/home_data.dart';
import 'package:my_flutter_app/features/home/domain/repositories/home_repository.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_cubit.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_state.dart';

class MockHomeRepository extends Mock implements IHomeRepository {}

/// Tests for the HomeCubit.
///
/// These verify the union-state lifecycle: loading, loaded, and — critically —
/// that a repository failure becomes a visible failure state instead of being
/// swallowed. Latest-request-wins ordering and close safety come from the
/// shared `LatestRequestWins` mixin and are tested once in
/// `test/core/bloc/latest_request_wins_test.dart`.
void main() {
  setUpAll(() {
    registerFallbackValue(
      HomeData(welcomeMessage: '', lastUpdated: DateTime(2024)),
    );
  });

  group('HomeCubit', () {
    late HomeCubit homeCubit;
    late MockHomeRepository mockHomeRepository;

    setUp(() {
      mockHomeRepository = MockHomeRepository();
      homeCubit = HomeCubit(mockHomeRepository);
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
          when(() => mockHomeRepository.getHomeData()).thenAnswer(
            (_) async => Right<Failure, HomeData>(
              HomeData(
                welcomeMessage: 'Welcome to the app!',
                lastUpdated: DateTime(2024),
              ),
            ),
          );
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
          when(() => mockHomeRepository.getHomeData()).thenAnswer(
            (_) async => const Left<Failure, HomeData>(Failure.networkError()),
          );
        },
        build: () => homeCubit,
        act: (HomeCubit cubit) => cubit.initialize(),
        expect: () => <HomeState>[
          const HomeState.loading(),
          const HomeState.failure(failure: Failure.networkError()),
        ],
      );

      blocTest<HomeCubit, HomeState>(
        'retains the failure category and its diagnostics in the state',
        setUp: () {
          when(() => mockHomeRepository.getHomeData()).thenAnswer(
            (_) async => const Left<Failure, HomeData>(
              // Diagnostics travel in state for logs/telemetry only; the UI
              // renders the localized category instead.
              Failure.serverError(message: 'diagnostic-internal-details'),
            ),
          );
        },
        build: () => homeCubit,
        act: (HomeCubit cubit) => cubit.initialize(),
        expect: () => <HomeState>[
          const HomeState.loading(),
          const HomeState.failure(
            failure: Failure.serverError(
              message: 'diagnostic-internal-details',
            ),
          ),
        ],
      );
    });

    group('refresh', () {
      blocTest<HomeCubit, HomeState>(
        'reloads data from the loading state',
        setUp: () {
          when(() => mockHomeRepository.getHomeData()).thenAnswer(
            (_) async => Right<Failure, HomeData>(
              HomeData(
                welcomeMessage: 'Refreshed!',
                lastUpdated: DateTime(2024),
              ),
            ),
          );
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
