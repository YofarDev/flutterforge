// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'counter_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

// CoverageIgnore(version:latest)

CounterSettings _$CounterSettingsFromJson(Map<String, dynamic> json) =>
    CounterSettings(
      maxValue: json['maxValue'] as int?,
      minValue: json['minValue'] as int?,
      stepSize: json['stepSize'] as int? ?? 1,
      showMilestones: json['showMilestones'] as bool? ?? false,
      milestoneInterval: json['milestoneInterval'] as int? ?? 10,
    );

Map<String, dynamic> _$CounterSettingsToJson(CounterSettings instance) =>
    <String, dynamic>{
      'maxValue': instance.maxValue,
      'minValue': instance.minValue,
      'stepSize': instance.stepSize,
      'showMilestones': instance.showMilestones,
      'milestoneInterval': instance.milestoneInterval,
    };
