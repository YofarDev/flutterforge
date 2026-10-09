library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/models/failure.dart';

part 'home_state.freezed.dart';

/// Union-state idiom for a load-lifecycle screen: exactly one variant is
/// active at a time and the UI must handle each one exhaustively.
/// Compare with `CounterState` (flat idiom) — see the flutter-architecture
/// skill for when to use each.
///
/// The failure state carries the typed [Failure], not a message: presentation
/// text is derived at build time from the failure category (see
/// `core/l10n/failure_localization.dart`).
@freezed
sealed class HomeState with _$HomeState {
  const factory HomeState.initial() = _Initial;
  const factory HomeState.loading() = _Loading;
  const factory HomeState.loaded({required String welcomeMessage}) = _Loaded;
  const factory HomeState.failure({required Failure failure}) = _Failure;
}
