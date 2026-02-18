import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/features/counter/bloc/counter_cubit.dart';

/// Tests for the CounterCubit.
///
/// These tests verify the business logic of the counter feature.
/// For each method in the cubit, we test:
/// - Initial state
/// - State transitions
/// - Edge cases
void main() {
  group('CounterCubit', () {
    late CounterCubit counterCubit;

    setUp(() {
      counterCubit = CounterCubit();
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

      blocTest<CounterCubit, CounterState>(
        'emits correct states when increment is called multiple times',
        build: () => counterCubit,
        act: (CounterCubit cubit) {
          cubit
            ..increment()
            ..increment()
            ..increment();
        },
        expect: () => <CounterState>[
          const CounterState(count: 1),
          const CounterState(count: 2),
          const CounterState(count: 3),
        ],
      );
    });

    group('decrement', () {
      blocTest<CounterCubit, CounterState>(
        'emits [count: -1] when decrement is called from initial state',
        build: () => counterCubit,
        act: (CounterCubit cubit) => cubit.decrement(),
        expect: () => <CounterState>[const CounterState(count: -1)],
      );

      blocTest<CounterCubit, CounterState>(
        'emits correct states when decrement is called multiple times',
        build: () => counterCubit,
        act: (CounterCubit cubit) {
          cubit
            ..decrement()
            ..decrement();
        },
        expect: () => <CounterState>[
          const CounterState(count: -1),
          const CounterState(count: -2),
        ],
      );
    });

    group('reset', () {
      blocTest<CounterCubit, CounterState>(
        'emits [count: 0] when reset is called from non-zero state',
        build: () => counterCubit,
        seed: () => const CounterState(count: 5),
        act: (CounterCubit cubit) => cubit.reset(),
        expect: () => <CounterState>[const CounterState(count: 0)],
      );

      blocTest<CounterCubit, CounterState>(
        'emits [count: 0] when reset is called from initial state',
        build: () => counterCubit,
        act: (CounterCubit cubit) => cubit.reset(),
        expect: () => <CounterState>[const CounterState(count: 0)],
      );
    });

    group('combined operations', () {
      blocTest<CounterCubit, CounterState>(
        'emits correct sequence for increment, increment, decrement, reset',
        build: () => counterCubit,
        act: (CounterCubit cubit) {
          cubit
            ..increment()
            ..increment()
            ..decrement()
            ..reset();
        },
        expect: () => <CounterState>[
          const CounterState(count: 1),
          const CounterState(count: 2),
          const CounterState(count: 1),
          const CounterState(count: 0),
        ],
      );
    });
  });
}
