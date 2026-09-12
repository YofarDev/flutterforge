import 'package:freezed_annotation/freezed_annotation.dart';

part 'counter_settings.freezed.dart';
part 'counter_settings.g.dart';

/// Example freezed domain model for the counter feature: immutable fields,
/// `copyWith`, `when`/`map`, and JSON serialization via the generated
/// `fromJson`. See the flutter-architecture skill for model conventions.
@freezed
abstract class CounterSettings with _$CounterSettings {
  /// Creates a new CounterSettings instance.
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
