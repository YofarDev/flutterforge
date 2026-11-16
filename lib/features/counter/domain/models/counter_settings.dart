import 'package:freezed_annotation/freezed_annotation.dart';

part 'counter_settings.freezed.dart';
part 'counter_settings.g.dart';

/// Counter behavior settings.
@freezed
abstract class CounterSettings with _$CounterSettings {
  const factory CounterSettings({
    /// The maximum value the counter can reach; `null` for no limit.
    int? maxValue,

    /// The minimum value the counter can reach; `null` for no limit.
    int? minValue,

    /// The step size for increment/decrement operations.
    @Default(1) int stepSize,

    /// Whether to show milestone notifications (e.g., every 10 counts).
    @Default(false) bool showMilestones,

    /// The interval for milestone notifications (if `showMilestones`).
    @Default(10) int milestoneInterval,
  }) = _CounterSettings;

  factory CounterSettings.fromJson(Map<String, dynamic> json) =>
      _$CounterSettingsFromJson(json);

  const CounterSettings._();
}
