library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/models/failure.dart';

part 'home_state.freezed.dart';

/// Load-lifecycle union state. The failure carries the typed [Failure]; the
/// screen derives text from it at build time.
@freezed
sealed class HomeState with _$HomeState {
  const factory HomeState.initial() = _Initial;
  const factory HomeState.loading() = _Loading;
  const factory HomeState.loaded({required String welcomeMessage}) = _Loaded;
  const factory HomeState.failure({required Failure failure}) = _Failure;
}
