import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/models/failure.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/models/counter_settings.dart';
import '../../domain/services/counter_service.dart';
import 'counter_state.dart';

/// Flat-state idiom: the counter is persistent interactive state, so a single
/// copyWith-able class beats a union of load states. Compare with `HomeState`
/// (union idiom) — see the flutter-architecture skill for when to use each.
///
/// Concurrency semantics (deliberate, tested in `counter_cubit_test.dart`):
/// - Increment/decrement are writes: each accepted action applies exactly one
///   step, reading the current count when its settings lookup completes.
///   Multiple increments without an intervening `reset()` all apply.
/// - `reset()` invalidates pending pre-reset operations via a generation
///   counter: each operation captures the generation before awaiting, and
///   `reset()` advances it, so an operation whose settings lookup started
///   before the reset is discarded instead of overwriting the reset.
/// - This example does NOT provide an ordered persistent-write queue. Future
///   noncommutative writes (e.g. set-count, server-synced writes) need
///   serialization or another explicit ordering policy.
class CounterCubit extends Cubit<CounterState> {
  final CounterService _counterService;

  /// Generation counter advanced by [reset]. Pending operations capture the
  /// generation before awaiting their settings lookup and are dropped when the
  /// generation has moved on by the time the lookup resolves.
  int _generation = 0;

  CounterCubit(this._counterService) : super(const CounterState()) {
    AppLogger.debug('CounterCubit initialized', tag: 'CounterCubit');
  }

  Future<void> increment() => _step(_applyIncrement);

  Future<void> decrement() => _step(_applyDecrement);

  Future<void> _step(int Function(CounterSettings settings) apply) async {
    // Never start work on a closed cubit.
    if (isClosed) {
      return;
    }

    final int generation = _generation;

    final Either<Failure, CounterSettings> result = await _counterService
        .getSettings();

    // After the await: drop the operation if the cubit closed or a reset
    // invalidated this generation while the lookup was in flight.
    if (isClosed || generation != _generation) {
      return;
    }

    result.fold(
      (Failure failure) {
        // Documented fallback: when settings retrieval fails, apply the write
        // using default settings instead of dropping the user action. The
        // exception itself was already logged at the repository boundary.
        AppLogger.warning(
          'Falling back to default settings (${failure.runtimeType})',
          tag: 'CounterCubit',
        );
        _updateCount(apply(const CounterSettings()), const CounterSettings());
      },
      (CounterSettings settings) {
        _updateCount(apply(settings), settings);
      },
    );
  }

  int _applyIncrement(CounterSettings settings) {
    return _counterService.applyStepSize(state.count, settings);
  }

  int _applyDecrement(CounterSettings settings) {
    return state.count - settings.stepSize;
  }

  void _updateCount(int newValue, CounterSettings settings) {
    final int clampedValue = _counterService.clampValue(newValue, settings);
    AppLogger.debug(
      'Updating count to $clampedValue (from $newValue)',
      tag: 'CounterCubit',
    );
    emit(state.copyWith(count: clampedValue));
  }

  void reset() {
    AppLogger.info('Resetting counter', tag: 'CounterCubit');
    // Advance the generation so any in-flight increment/decrement that
    // captured the previous generation is discarded when it resumes.
    _generation++;
    emit(const CounterState());
  }
}
