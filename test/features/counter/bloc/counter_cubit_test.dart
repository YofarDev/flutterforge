import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/counter/domain/models/counter_settings.dart';
import 'package:my_flutter_app/features/counter/domain/services/counter_service.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_cubit.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_state.dart';

class MockCounterService extends Mock implements CounterService {}

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
      when(() => mockCounterService.applyStepSize(any(), any())).thenAnswer((
        Invocation invocation,
      ) {
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
  });
}
