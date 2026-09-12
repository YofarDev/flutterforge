library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'home_state.freezed.dart';

/// Union-state idiom for a load-lifecycle screen: exactly one variant is
/// active at a time and the UI must handle each one exhaustively.
/// Compare with `CounterState` (flat idiom) — see the flutter-architecture
/// skill for when to use each.
@freezed
sealed class HomeState with _$HomeState {
  const factory HomeState.initial() = _Initial;
  const factory HomeState.loading() = _Loading;
  const factory HomeState.loaded({required String welcomeMessage}) = _Loaded;
  const factory HomeState.failure({required String message}) = _Failure;
}
