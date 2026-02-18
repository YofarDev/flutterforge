import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'counter_state.dart';

/// The cubit for the Counter feature.
///
/// DEMO FEATURE: This is a demonstration feature that can be deleted.
/// It shows how to create a cubit with state management.
///
/// This cubit manages a simple counter with increment, decrement, and
/// reset functionality. Use this as a reference when creating your own
/// features.
class CounterCubit extends Cubit<CounterState> {
  CounterCubit() : super(const CounterState());

  /// Increments the count by 1.
  void increment() {
    emit(state.copyWith(count: state.count + 1));
  }

  /// Decrements the count by 1.
  void decrement() {
    emit(state.copyWith(count: state.count - 1));
  }

  /// Resets the count to 0.
  void reset() {
    emit(const CounterState());
  }
}
