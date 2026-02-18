import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/utils/logger.dart';

part 'counter_state.dart';

/// DEMO FEATURE - Delete counter folder when building your app.
/// Demonstrates basic cubit with state management.
class CounterCubit extends Cubit<CounterState> {
  CounterCubit() : super(const CounterState()) {
    AppLogger.debug('CounterCubit initialized', tag: 'CounterCubit');
  }

  /// Increments the count by 1.
  void increment() {
    final int newCount = state.count + 1;
    AppLogger.debug('Incrementing count to $newCount', tag: 'CounterCubit');
    emit(state.copyWith(count: newCount));
  }

  /// Decrements the count by 1.
  void decrement() {
    final int newCount = state.count - 1;
    AppLogger.debug('Decrementing count to $newCount', tag: 'CounterCubit');
    emit(state.copyWith(count: newCount));
  }

  /// Resets the count to 0.
  void reset() {
    AppLogger.info('Resetting counter', tag: 'CounterCubit');
    emit(const CounterState());
  }

  @override
  void onChange(Change<CounterState> change) {
    super.onChange(change);
    AppLogger.debug(
      'State changed: ${change.currentState.count} → ${change.nextState.count}',
      tag: 'CounterCubit',
    );
  }
}
