import 'dart:async';

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
/// swallowed. They also pin the deliberate async semantics: reads use
/// latest-request-wins via a monotonic request identifier, nothing is emitted
/// after close, and a stale (superseded) result — success or failure — is
/// discarded instead of overwriting a newer request's state.
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

    group('async lifecycle', () {
      Completer<Either<Failure, HomeData>> makeCompleter() =>
          Completer<Either<Failure, HomeData>>();

      Right<Failure, HomeData> success(String message) =>
          Right<Failure, HomeData>(
            HomeData(welcomeMessage: message, lastUpdated: DateTime(2024)),
          );

      test('a success completing after close does not emit or throw', () async {
        final Completer<Either<Failure, HomeData>> completer = makeCompleter();
        when(() => mockHomeRepository.getHomeData())
            .thenAnswer((_) => completer.future);

        final List<HomeState> emissions = <HomeState>[];
        final StreamSubscription<HomeState> subscription = homeCubit.stream
            .listen(emissions.add);

        final Future<void> load = homeCubit.initialize();
        await homeCubit.close();
        completer.complete(success('Late'));

        // Completing after close must not throw (emit on a closed cubit
        // would) and must not emit.
        await load;
        // Flush the microtask queue so the broadcast state stream delivers
        // queued emissions before the subscription is cancelled.
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        expect(emissions, <HomeState>[const HomeState.loading()]);
      });

      test('a failure completing after close does not emit or throw', () async {
        final Completer<Either<Failure, HomeData>> completer = makeCompleter();
        when(() => mockHomeRepository.getHomeData())
            .thenAnswer((_) => completer.future);

        final List<HomeState> emissions = <HomeState>[];
        final StreamSubscription<HomeState> subscription = homeCubit.stream
            .listen(emissions.add);

        final Future<void> load = homeCubit.initialize();
        await homeCubit.close();
        completer.complete(
          const Left<Failure, HomeData>(Failure.networkError()),
        );

        await load;
        // Flush the microtask queue so the broadcast state stream delivers
        // queued emissions before the subscription is cancelled.
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        expect(emissions, <HomeState>[const HomeState.loading()]);
      });

      test(
        'two reads completed in reverse order retain the newer result',
        () async {
          final Completer<Either<Failure, HomeData>> first = makeCompleter();
          final Completer<Either<Failure, HomeData>> second = makeCompleter();
          int call = 0;
          when(() => mockHomeRepository.getHomeData()).thenAnswer((_) {
            call++;
            return call == 1 ? first.future : second.future;
          });

          final List<HomeState> emissions = <HomeState>[];
          final StreamSubscription<HomeState> subscription = homeCubit.stream
              .listen(emissions.add);

          final Future<void> firstLoad = homeCubit.initialize();
          final Future<void> secondLoad = homeCubit.refresh();

          // The newer request resolves first, then the stale older one.
          second.complete(success('Newer'));
          await secondLoad;
          first.complete(success('Older'));
          await firstLoad;

          // Flush the microtask queue so the broadcast state stream delivers
          // queued emissions before the subscription is cancelled.
          await Future<void>.delayed(Duration.zero);
          await subscription.cancel();
          expect(
            emissions.last,
            const HomeState.loaded(welcomeMessage: 'Newer'),
          );
        },
      );

      test('a stale failure cannot overwrite a newer success', () async {
        final Completer<Either<Failure, HomeData>> first = makeCompleter();
        final Completer<Either<Failure, HomeData>> second = makeCompleter();
        int call = 0;
        when(() => mockHomeRepository.getHomeData()).thenAnswer((_) {
          call++;
          return call == 1 ? first.future : second.future;
        });

        final List<HomeState> emissions = <HomeState>[];
        final StreamSubscription<HomeState> subscription = homeCubit.stream
            .listen(emissions.add);

        final Future<void> firstLoad = homeCubit.initialize();
        final Future<void> secondLoad = homeCubit.refresh();

        second.complete(success('Newer'));
        await secondLoad;
        first.complete(const Left<Failure, HomeData>(Failure.networkError()));
        await firstLoad;

        // Flush the microtask queue so the broadcast state stream delivers
        // queued emissions before the subscription is cancelled.
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        expect(
          emissions.last,
          isNot(const HomeState.failure(failure: Failure.networkError())),
        );
        expect(emissions.last, const HomeState.loaded(welcomeMessage: 'Newer'));
      });

      test(
        'a failed current request is followed by a successful retry',
        () async {
          final Completer<Either<Failure, HomeData>> first = makeCompleter();
          when(() => mockHomeRepository.getHomeData())
              .thenAnswer((_) => first.future);

          final List<HomeState> emissions = <HomeState>[];
          final StreamSubscription<HomeState> subscription = homeCubit.stream
              .listen(emissions.add);

          final Future<void> failedLoad = homeCubit.initialize();
          first.complete(const Left<Failure, HomeData>(Failure.networkError()));
          await failedLoad;

          // Retry: the new request becomes the current one and succeeds.
          when(() => mockHomeRepository.getHomeData())
              .thenAnswer((_) async => success('Retried'));
          await homeCubit.refresh();

          // Flush the microtask queue so the broadcast state stream delivers
          // queued emissions before the subscription is cancelled.
          await Future<void>.delayed(Duration.zero);
          await subscription.cancel();
          expect(emissions, <HomeState>[
            const HomeState.loading(),
            const HomeState.failure(failure: Failure.networkError()),
            const HomeState.loading(),
            const HomeState.loaded(welcomeMessage: 'Retried'),
          ]);
        },
      );
    });
  });
}
