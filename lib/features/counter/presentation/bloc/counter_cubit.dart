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
class CounterCubit extends Cubit<CounterState> {
  final CounterService _counterService;

  CounterCubit(this._counterService) : super(const CounterState()) {
    AppLogger.debug('CounterCubit initialized', tag: 'CounterCubit');
  }

  Future<void> increment() async {
    final Either<Failure, CounterSettings> result = await _counterService
        .getSettings();

    result.fold(
      (Failure failure) {
        AppLogger.warning(
          'Falling back to default settings: ${failure.message}',
          tag: 'CounterCubit',
        );
        _updateCount(state.count + 1, const CounterSettings());
      },
      (CounterSettings settings) {
        final int newValue = _counterService.applyStepSize(
          state.count,
          settings,
        );
        _updateCount(newValue, settings);
      },
    );
  }

  Future<void> decrement() async {
    final Either<Failure, CounterSettings> result = await _counterService
        .getSettings();

    result.fold(
      (Failure failure) {
        AppLogger.warning(
          'Falling back to default settings: ${failure.message}',
          tag: 'CounterCubit',
        );
        _updateCount(state.count - 1, const CounterSettings());
      },
      (CounterSettings settings) {
        final int newValue = state.count - settings.stepSize;
        _updateCount(newValue, settings);
      },
    );
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
    emit(const CounterState());
  }
}
