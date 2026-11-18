import 'package:freezed_annotation/freezed_annotation.dart';

part 'home_data.freezed.dart';

@freezed
sealed class HomeData with _$HomeData {
  const factory HomeData({
    required String welcomeMessage,
    required DateTime lastUpdated,
  }) = _HomeData;
}
