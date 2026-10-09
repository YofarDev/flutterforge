import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/counter/domain/models/counter_settings.dart';
import 'package:my_flutter_app/features/counter/domain/repositories/counter_repository.dart';
import 'package:my_flutter_app/features/counter/domain/services/counter_service.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_cubit.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_state.dart';

class MockCounterService extends Mock implements CounterService {}

/// Fake repository returning a scripted settings result — used so the cubit
/// tests can run against the REAL CounterService (step/clamp logic is the
/// production implementation, not re-implemented in a mock callback).
class FakeCounterRepository implements ICounterRepository {
  FakeCounterRepository(this._result);

  final Either<Failure, CounterSettings> _result;

  @override
  Future<Either<Failure, CounterSettings>> getSettings() async => _result;

  @override
  Future<Either<Failure, void>> saveSettings(CounterSettings settings) async =>
      const Right<Failure, void>(null);
}

/// Tests for the CounterCubit.
void main() {
  setUpAll(() {
    registerFallbackValue(const CounterSettings());
  });

  group('CounterCubit', () {
    late CounterCubit counterCubit;
    late MockCounterService mockCounterService;

    setUp(() {
      mockCounterService = MockCounterService();
      counterCubit = CounterCubit(mockCounterService);

      // Default stubs
      when(() => mockCounterService.getSettings()).thenAnswer(
        (_) async => const Right<Failure, CounterSettings>(CounterSettings()),
      );
      when(() => mockCounterService.clampValue(any(), any())).thenAnswer(
        (Invocation invocation) => invocation.positionalArguments[0] as int,
      );
      when(() => mockCounterService.applyStepSize(any(), any()))
          .thenAnswer((Invocation invocation) {
            final int val = invocation.positionalArguments[0] as int;
            final CounterSettings settings =
                invocation.positionalArguments[1] as CounterSettings;
            return val + settings.stepSize;
          });
    });

    tearDown(() {
      counterCubit.close();
    });

    test('initial state has count of 0', () {
      expect(counterCubit.state, const CounterState(count: 0));
    });

    group('increment', () {
      blocTest<CounterCubit, CounterState>(
        'emits [count: 1] when increment is called',
        build: () => counterCubit,
        act: (CounterCubit cubit) => cubit.increment(),
        expect: () => <CounterState>[const CounterState(count: 1)],
      );
    });

    group('decrement', () {
      blocTest<CounterCubit, CounterState>(
        'emits [count: -1] when decrement is called from initial state',
        build: () => counterCubit,
        act: (CounterCubit cubit) => cubit.decrement(),
        expect: () => <CounterState>[const CounterState(count: -1)],
      );
    });

    group('reset', () {
      blocTest<CounterCubit, CounterState>(
        'emits [count: 0] when reset is called',
        build: () => counterCubit,
        act: (CounterCubit cubit) => cubit.reset(),
        expect: () => <CounterState>[const CounterState(count: 0)],
      );
    });

    group('async lifecycle', () {
      test('two increments without a reset are both applied', () async {
        final Completer<Either<Failure, CounterSettings>> first =
            Completer<Either<Failure, CounterSettings>>();
        final Completer<Either<Failure, CounterSettings>> second =
            Completer<Either<Failure, CounterSettings>>();
        int call = 0;
        when(() => mockCounterService.getSettings()).thenAnswer((_) {
          call++;
          return call == 1 ? first.future : second.future;
        });

        final List<CounterState> emissions = <CounterState>[];
        final StreamSubscription<CounterState> subscription = counterCubit
            .stream
            .listen(emissions.add);

        // Both start before either settings lookup resolves; each must read
        // the current count when its own lookup completes.
        final Future<void> firstIncrement = counterCubit.increment();
        final Future<void> secondIncrement = counterCubit.increment();

        first.complete(
          const Right<Failure, CounterSettings>(CounterSettings()),
        );
        await firstIncrement;
        second.complete(
          const Right<Failure, CounterSettings>(CounterSettings()),
        );
        await secondIncrement;

        // Flush the microtask queue so the broadcast state stream delivers
        // queued emissions before the subscription is cancelled.
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        expect(emissions, <CounterState>[
          const CounterState(count: 1),
          const CounterState(count: 2),
        ]);
        expect(counterCubit.state, const CounterState(count: 2));
      });

      test('reset invalidates an earlier pending counter operation', () async {
        final Completer<Either<Failure, CounterSettings>> pending =
            Completer<Either<Failure, CounterSettings>>();
        when(() => mockCounterService.getSettings())
            .thenAnswer((_) => pending.future);

        final List<CounterState> emissions = <CounterState>[];
        final StreamSubscription<CounterState> subscription = counterCubit
            .stream
            .listen(emissions.add);

        final Future<void> pendingIncrement = counterCubit.increment();
        counterCubit.reset();

        // The pending increment's settings lookup resolves after the reset;
        // the reset must invalidate it so the count stays 0.
        pending.complete(
          const Right<Failure, CounterSettings>(CounterSettings()),
        );
        await pendingIncrement;

        // Flush the microtask queue so the broadcast state stream delivers
        // queued emissions before the subscription is cancelled.
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        expect(emissions, <CounterState>[const CounterState(count: 0)]);
        expect(counterCubit.state, const CounterState(count: 0));
      });

      test(
        'settings retrieval failure falls back to default settings',
        () async {
          when(() => mockCounterService.getSettings()).thenAnswer(
            (_) async =>
                const Left<Failure, CounterSettings>(Failure.networkError()),
          );

          final List<CounterState> emissions = <CounterState>[];
          final StreamSubscription<CounterState> subscription = counterCubit
              .stream
              .listen(emissions.add);

          // The fallback applies the write with default settings (step 1),
          // so the user action is not dropped.
          await counterCubit.increment();

          // Flush the microtask queue so the broadcast state stream delivers
          // queued emissions before the subscription is cancelled.
          await Future<void>.delayed(Duration.zero);
          await subscription.cancel();
          expect(emissions, <CounterState>[const CounterState(count: 1)]);
          expect(counterCubit.state, const CounterState(count: 1));
        },
      );

      test('a pending operation after close does not emit or throw', () async {
        final Completer<Either<Failure, CounterSettings>> pending =
            Completer<Either<Failure, CounterSettings>>();
        when(() => mockCounterService.getSettings())
            .thenAnswer((_) => pending.future);

        final List<CounterState> emissions = <CounterState>[];
        final StreamSubscription<CounterState> subscription = counterCubit
            .stream
            .listen(emissions.add);

        final Future<void> pendingIncrement = counterCubit.increment();
        await counterCubit.close();
        pending.complete(
          const Right<Failure, CounterSettings>(CounterSettings()),
        );

        await pendingIncrement;
        // Flush the microtask queue so the broadcast state stream delivers
        // queued emissions before the subscription is cancelled.
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        expect(emissions, isEmpty);
      });
    });

    group('with the real CounterService (fake repository I/O)', () {
      // These tests exercise the cubit against the production service: the
      // step-size arithmetic and clamping are the real implementation, not
      // stubs duplicated from it.
      late CounterCubit realServiceCubit;

      tearDown(() {
        realServiceCubit.close();
      });

      test('increments by a non-default step size', () async {
        realServiceCubit = CounterCubit(
          CounterService(
            FakeCounterRepository(
              const Right<Failure, CounterSettings>(
                CounterSettings(stepSize: 3),
              ),
            ),
          ),
        );

        await realServiceCubit.increment();
        expect(realServiceCubit.state, const CounterState(count: 3));

        await realServiceCubit.increment();
        expect(realServiceCubit.state, const CounterState(count: 6));
      });

      test('clamps increments to the configured maximum', () async {
        realServiceCubit = CounterCubit(
          CounterService(
            FakeCounterRepository(
              const Right<Failure, CounterSettings>(
                CounterSettings(stepSize: 4, maxValue: 5),
              ),
            ),
          ),
        );

        await realServiceCubit.increment();
        expect(realServiceCubit.state, const CounterState(count: 4));

        // 4 + 4 = 8 clamps to 5.
        await realServiceCubit.increment();
        expect(realServiceCubit.state, const CounterState(count: 5));
      });

      test('clamps decrements to the configured minimum', () async {
        realServiceCubit = CounterCubit(
          CounterService(
            FakeCounterRepository(
              const Right<Failure, CounterSettings>(
                CounterSettings(stepSize: 3, minValue: -5),
              ),
            ),
          ),
        );

        await realServiceCubit.decrement();
        expect(realServiceCubit.state, const CounterState(count: -3));

        // -3 - 3 = -6 clamps to -5.
        await realServiceCubit.decrement();
        expect(realServiceCubit.state, const CounterState(count: -5));
      });

      test(
        'falls back to default settings when settings retrieval fails',
        () async {
          realServiceCubit = CounterCubit(
            CounterService(
              FakeCounterRepository(
                const Left<Failure, CounterSettings>(Failure.networkError()),
              ),
            ),
          );

          // Documented fallback: the write is applied with default settings
          // (step 1) instead of being dropped.
          await realServiceCubit.increment();
          expect(realServiceCubit.state, const CounterState(count: 1));
        },
      );
    });
  });
}
