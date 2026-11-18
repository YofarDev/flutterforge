import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/models/failure.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/models/counter_settings.dart';
import '../../domain/services/counter_service.dart';
import 'counter_state.dart';

/// Every accepted increment/decrement applies (they are writes, not
/// superseding reads); `reset()` discards operations still awaiting their
/// settings lookup. There is no ordered write queue: noncommutative writes
/// would need one.
class CounterCubit extends Cubit<CounterState> {
  final CounterService _counterService;

  /// Advanced by [reset]; an operation that started under an older
  /// generation is dropped.
  int _generation = 0;

  CounterCubit(this._counterService) : super(const CounterState()) {
    AppLogger.debug('CounterCubit initialized', tag: 'CounterCubit');
  }

  Future<void> increment() => _step(_applyIncrement);

  Future<void> decrement() => _step(_applyDecrement);

  Future<void> _step(int Function(CounterSettings settings) apply) async {
    if (isClosed) {
      return;
    }

    final int generation = _generation;

    final Either<Failure, CounterSettings> result = await _counterService
        .getSettings();

    if (isClosed || generation != _generation) {
      return;
    }

    result.fold(
      (Failure failure) {
        // Apply the user's action with default settings rather than drop it.
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
    return _counterService.applyStepSizeDown(state.count, settings);
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
    _generation++;
    emit(const CounterState());
  }
}
