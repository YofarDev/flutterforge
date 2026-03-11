import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/models/home_data.dart';

part 'home_data_dto.freezed.dart';
part 'home_data_dto.g.dart';

@freezed
sealed class HomeDataDto with _$HomeDataDto {
  const factory HomeDataDto({
    required String welcomeMessage,
    required String lastUpdated,
  }) = _HomeDataDto;

  factory HomeDataDto.fromJson(Map<String, dynamic> json) =>
      _$HomeDataDtoFromJson(json);

  const HomeDataDto._();

  HomeData toDomain() {
    return HomeData(
      welcomeMessage: welcomeMessage,
      lastUpdated: DateTime.parse(lastUpdated),
    );
  }
}
