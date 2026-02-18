part of 'counter_cubit.dart';

/// The state for the Counter feature.
///
/// DEMO FEATURE: This is a demonstration feature that can be deleted.
/// It shows how to structure a feature with BLoC/Cubit pattern.
class CounterState extends Equatable {
  /// The current count value.
  final int count;

  const CounterState({this.count = 0});

  /// Creates a copy of this state with the count value replaced.
  CounterState copyWith({int? count}) {
    return CounterState(count: count ?? this.count);
  }

  @override
  List<Object> get props => <Object>[count];
}
