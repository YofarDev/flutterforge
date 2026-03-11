import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/models/counter_settings.dart';

part 'counter_settings_dto.freezed.dart';
part 'counter_settings_dto.g.dart';

@freezed
sealed class CounterSettingsDto with _$CounterSettingsDto {
  const factory CounterSettingsDto({
    @Default(1) int stepSize,
    int? minValue,
    int? maxValue,
  }) = _CounterSettingsDto;

  factory CounterSettingsDto.fromJson(Map<String, dynamic> json) =>
      _$CounterSettingsDtoFromJson(json);

  const CounterSettingsDto._();

  factory CounterSettingsDto.fromDomain(CounterSettings domain) {
    return CounterSettingsDto(
      stepSize: domain.stepSize,
      minValue: domain.minValue,
      maxValue: domain.maxValue,
    );
  }

  CounterSettings toDomain() {
    return CounterSettings(
      stepSize: stepSize,
      minValue: minValue,
      maxValue: maxValue,
    );
  }
}
