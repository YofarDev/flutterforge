import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/counter/domain/models/counter_settings.dart';
import 'package:my_flutter_app/features/counter/domain/repositories/counter_repository.dart';
import 'package:my_flutter_app/features/counter/domain/services/counter_service.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_cubit.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_state.dart';

/// Repository seam: answers every settings read with [settings], or with
/// the next pending completer when [pending] is not empty.
class FakeCounterRepository implements ICounterRepository {
  FakeCounterRepository([
    this.settings = const Right<Failure, CounterSettings>(CounterSettings()),
  ]);

  final Either<Failure, CounterSettings> settings;
  final List<Completer<Either<Failure, CounterSettings>>> pending =
      <Completer<Either<Failure, CounterSettings>>>[];

  Completer<Either<Failure, CounterSettings>> holdNextRead() {
    final Completer<Either<Failure, CounterSettings>> completer =
        Completer<Either<Failure, CounterSettings>>();
    pending.add(completer);
    return completer;
  }

  @override
  Future<Either<Failure, CounterSettings>> getSettings() => pending.isEmpty
      ? Future<Either<Failure, CounterSettings>>.value(settings)
      : pending.removeAt(0).future;

  @override
  Future<Either<Failure, void>> saveSettings(CounterSettings settings) async =>
      const Right<Failure, void>(null);
}

/// CounterCubit over the REAL CounterService: step and clamp arithmetic is
/// the production implementation; only the repository is faked.
void main() {
  const Either<Failure, CounterSettings> defaults =
      Right<Failure, CounterSettings>(CounterSettings());

  CounterCubit buildCubit(FakeCounterRepository repository) {
    final CounterCubit cubit = CounterCubit(CounterService(repository));
    addTearDown(cubit.close);
    return cubit;
  }

  Future<List<CounterState>> recordWhile(
    CounterCubit cubit,
    Future<void> Function() body,
  ) async {
    final List<CounterState> emissions = <CounterState>[];
    final StreamSubscription<CounterState> subscription = cubit.stream.listen(
      emissions.add,
    );
    await body();
    // Let the broadcast stream deliver queued emissions before cancelling.
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return emissions;
  }

  test('increment, decrement and reset move the count', () async {
    final CounterCubit cubit = buildCubit(FakeCounterRepository());

    await cubit.increment();
    await cubit.increment();
    expect(cubit.state, const CounterState(count: 2));

    await cubit.decrement();
    expect(cubit.state, const CounterState(count: 1));

    cubit.reset();
    expect(cubit.state, const CounterState(count: 0));
  });

  test('applies a non-default step size', () async {
    final CounterCubit cubit = buildCubit(
      FakeCounterRepository(
        const Right<Failure, CounterSettings>(CounterSettings(stepSize: 3)),
      ),
    );

    await cubit.increment();
    await cubit.increment();
    expect(cubit.state, const CounterState(count: 6));
  });

  test('clamps to the configured maximum and minimum', () async {
    final CounterCubit cubit = buildCubit(
      FakeCounterRepository(
        const Right<Failure, CounterSettings>(
          CounterSettings(stepSize: 4, minValue: -2, maxValue: 5),
        ),
      ),
    );

    await cubit.increment();
    await cubit.increment(); // 4 + 4 = 8 clamps to 5.
    expect(cubit.state, const CounterState(count: 5));

    await cubit.decrement();
    await cubit.decrement(); // 1 - 4 = -3 clamps to -2.
    expect(cubit.state, const CounterState(count: -2));
  });

  test('a settings failure falls back to default settings', () async {
    final CounterCubit cubit = buildCubit(
      FakeCounterRepository(
        const Left<Failure, CounterSettings>(Failure.networkError()),
      ),
    );

    // The user's action is applied with step 1 instead of being dropped.
    await cubit.increment();
    expect(cubit.state, const CounterState(count: 1));
  });

  group('async lifecycle', () {
    test('two overlapping increments are both applied', () async {
      final FakeCounterRepository repository = FakeCounterRepository();
      final Completer<Either<Failure, CounterSettings>> first = repository
          .holdNextRead();
      final Completer<Either<Failure, CounterSettings>> second = repository
          .holdNextRead();
      final CounterCubit cubit = buildCubit(repository);

      final List<CounterState> emissions = await recordWhile(cubit, () async {
        // Both start before either settings read resolves; each must read
        // the current count when its own read completes.
        final Future<void> firstIncrement = cubit.increment();
        final Future<void> secondIncrement = cubit.increment();
        first.complete(defaults);
        await firstIncrement;
        second.complete(defaults);
        await secondIncrement;
      });

      expect(emissions, <CounterState>[
        const CounterState(count: 1),
        const CounterState(count: 2),
      ]);
    });

    test('reset invalidates an earlier pending operation', () async {
      final FakeCounterRepository repository = FakeCounterRepository();
      final Completer<Either<Failure, CounterSettings>> pending = repository
          .holdNextRead();
      final CounterCubit cubit = buildCubit(repository);

      final List<CounterState> emissions = await recordWhile(cubit, () async {
        final Future<void> pendingIncrement = cubit.increment();
        cubit.reset();
        // Resolves after the reset: the increment must be dropped.
        pending.complete(defaults);
        await pendingIncrement;
      });

      expect(emissions, <CounterState>[const CounterState(count: 0)]);
      expect(cubit.state, const CounterState(count: 0));
    });

    test('a pending operation after close does not emit or throw', () async {
      final FakeCounterRepository repository = FakeCounterRepository();
      final Completer<Either<Failure, CounterSettings>> pending = repository
          .holdNextRead();
      final CounterCubit cubit = buildCubit(repository);

      final List<CounterState> emissions = await recordWhile(cubit, () async {
        final Future<void> pendingIncrement = cubit.increment();
        await cubit.close();
        pending.complete(defaults);
        await pendingIncrement;
      });

      expect(emissions, isEmpty);
    });
  });
}
