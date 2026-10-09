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

    /// Defaults mirror the domain model so JSON stored before these fields
    /// existed restores the same values `CounterSettings` would create.
    @Default(false) bool showMilestones,
    @Default(10) int milestoneInterval,
  }) = _CounterSettingsDto;

  factory CounterSettingsDto.fromJson(Map<String, dynamic> json) =>
      _$CounterSettingsDtoFromJson(json);

  const CounterSettingsDto._();

  factory CounterSettingsDto.fromDomain(CounterSettings domain) {
    return CounterSettingsDto(
      stepSize: domain.stepSize,
      minValue: domain.minValue,
      maxValue: domain.maxValue,
      showMilestones: domain.showMilestones,
      milestoneInterval: domain.milestoneInterval,
    );
  }

  CounterSettings toDomain() {
    return CounterSettings(
      stepSize: stepSize,
      minValue: minValue,
      maxValue: maxValue,
      showMilestones: showMilestones,
      milestoneInterval: milestoneInterval,
    );
  }
}
