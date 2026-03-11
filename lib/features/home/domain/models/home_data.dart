import 'package:freezed_annotation/freezed_annotation.dart';

part 'home_data.freezed.dart';
part 'home_data.g.dart';

@freezed
sealed class HomeData with _$HomeData {
  const factory HomeData({
    required String welcomeMessage,
    required DateTime lastUpdated,
  }) = _HomeData;

  factory HomeData.fromJson(Map<String, dynamic> json) =>
      _$HomeDataFromJson(json);
}
