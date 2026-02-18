// GENERATED CODE - DO NOT MODIFY BY HAND
//**************************************************************************
// FreezedGenerator
//**************************************************************************

// CoverageIgnore(version:latest)

part of 'counter_settings.dart';

// **************************************************************************
// _$CounterSettings
// **************************************************************************

/// @nodoc
@internal
class _$CounterSettings with _$_CounterSettings {
  const _$CounterSettings({
    super.maxValue,
    super.minValue,
    super.stepSize = 1,
    super.showMilestones = false,
    super.milestoneInterval = 10,
  });

  @override
  @JsonKey()
  final int? maxValue;

  @override
  @JsonKey()
  final int? minValue;

  @override
  @JsonKey()
  @Default(1)
  final int stepSize;

  @override
  @JsonKey()
  @Default(false)
  final bool showMilestones;

  @override
  @JsonKey()
  @Default(10)
  final int milestoneInterval;

  @override
  String toString() {
    return 'CounterSettings(maxValue: $maxValue, minValue: $minValue, stepSize: $stepSize, showMilestones: $showMilestones, milestoneInterval: $milestoneInterval)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other is _CounterSettings &&
            maxValue == other.maxValue &&
            minValue == other.minValue &&
            stepSize == other.stepSize &&
            showMilestones == other.showMilestones &&
            milestoneInterval == other.milestoneInterval);
  }

  @override
  int get hashCode => Object.hash(
    maxValue,
    minValue,
    stepSize,
    showMilestones,
    milestoneInterval,
  );

  @override
  @JsonKey()
  _CounterSettings copyWith({
    Object? maxValue = freezed,
    Object? minValue = freezed,
    Object? stepSize = freezed,
    Object? showMilestones = freezed,
    Object? milestoneInterval = freezed,
  }) {
    return _CounterSettings(
      maxValue: maxValue == freezed
          ? this.maxValue
          : maxValue // ignore: unnecessary_cast
              as int?,
      minValue: minValue == freezed
          ? this.minValue
          : minValue // ignore: unnecessary_cast
              as int?,
      stepSize: stepSize == freezed
          ? this.stepSize
          : stepSize // ignore: unnecessary_cast
              as int,
      showMilestones: showMilestones == freezed
          ? this.showMilestones
          : showMilestones // ignore: unnecessary_cast
              as bool,
      milestoneInterval: milestoneInterval == freezed
          ? this.milestoneInterval
          : milestoneInterval // ignore: unnecessary_cast
              as int,
    );
  }

  @override
  Map<String, dynamic> toJson() => _$CounterSettingsToJson(this);
}

// **************************************************************************
// CounterSettings copyWith extensions
// **************************************************************************

extension _$CounterSettingsCopyWith on CounterSettings {
  /// Creates a copy of CounterSettings with the given fields replaced
  /// by the non-null parameter values.
  _CounterSettings copyWith({
    Object? maxValue = freezed,
    Object? minValue = freezed,
    Object? stepSize = freezed,
    Object? showMilestones = freezed,
    Object? milestoneInterval = freezed,
  }) =>
      _CounterSettings(
        maxValue: maxValue == freezed
            ? (this as _CounterSettings).maxValue
            : maxValue // ignore: unnecessary_cast
                as int?,
        minValue: minValue == freezed
            ? (this as _CounterSettings).minValue
            : minValue // ignore: unnecessary_cast
                as int?,
        stepSize: stepSize == freezed
            ? (this as _CounterSettings).stepSize
            : stepSize // ignore: unnecessary_cast
                as int,
        showMilestones: showMilestones == freezed
            ? (this as _CounterSettings).showMilestones
            : showMilestones // ignore: unnecessary_cast
                as bool,
        milestoneInterval: milestoneInterval == freezed
            ? (this as _CounterSettings).milestoneInterval
            : milestoneInterval // ignore: unnecessary_cast
                as int,
      );
}

abstract class _$_CounterSettings {
  factory _$_CounterSettings({
    int? maxValue,
    int? minValue,
    int stepSize = 1,
    bool showMilestones = false,
    int milestoneInterval = 10,
  }) = _CounterSettings;

  int? get maxValue;
  int? get minValue;
  int get stepSize;
  bool get showMilestones;
  int get milestoneInterval;

  @JsonKey()
  _CounterSettings copyWith({
    Object? maxValue = freezed,
    Object? minValue = freezed,
    Object? stepSize = freezed,
    Object? showMilestones = freezed,
    Object? milestoneInterval = freezed,
  });

  Map<String, dynamic> toJson();
}

const _CounterSettings _freezedCounterSettings = _CounterSettings;
