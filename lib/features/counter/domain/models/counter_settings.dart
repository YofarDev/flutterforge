import 'package:freezed_annotation/freezed_annotation.dart';

part 'counter_settings.freezed.dart';
part 'counter_settings.g.dart';

/// Example of a freezed model for the Counter feature.
///
/// ## THIS IS AN EXAMPLE MODEL
///
/// When building your app, you can:
/// - **DELETE THIS FILE** if you don't need it
/// - **USE AS REFERENCE** for creating your own models
/// - **MODIFY** for your specific data needs
///
/// ## Why Freezed?
///
/// Freezed provides:
/// - **Immutability**: All fields are final by default
/// - **copyWith**: Easy to create modified copies
/// - **Pattern matching**: Powerful when/map/switchMap
/// - **JSON serialization**: Automatic toJson/fromJson
/// - **Union types**: One class with multiple variants
///
/// ## How to Create Your Own Models
///
/// 1. Add dependencies (already in packages_to_add.json):
///    - `freezed_annotation`
///    - `freezed` (dev dependency)
///    - `build_runner` (dev dependency)
///
/// 2. Create your model file:
/// ```dart
/// import 'package:freezed_annotation/freezed_annotation.dart';
///
/// part 'my_model.freezed.dart';
/// part 'my_model.g.dart';
///
/// @freezed
/// class MyModel with _$MyModel {
///   const factory MyModel({
///     required String id,
///     required String name,
///     String? description,
///   }) = _MyModel;
///
///   factory MyModel.fromJson(Map<String, dynamic> json) =>
///       _$MyModelFromJson(json);
/// }
/// ```
///
/// 3. Run code generation (done automatically by create_flutter_project.sh):
/// ```bash
/// dart run build_runner build --delete-conflicting-outputs
/// ```
///
/// 4. Use in your app:
/// ```dart
/// final model = MyModel(id: '1', name: 'Test');
/// final updated = model.copyWith(name: 'Updated');
/// final json = model.toJson();
/// ```
@freezed
abstract class CounterSettings with _$CounterSettings {
  /// Creates a new CounterSettings instance.
  ///
  /// All fields are final (immutable) by default.
  /// Use `copyWith()` to create modified copies.
  const factory CounterSettings({
    /// The maximum value the counter can reach.
    /// Use `null` for no limit.
    int? maxValue,

    /// The minimum value the counter can reach.
    /// Use `null` for no limit.
    int? minValue,

    /// The step size for increment/decrement operations.
    /// Default is 1.
    @Default(1) int stepSize,

    /// Whether to show milestone notifications (e.g., every 10 counts).
    @Default(false) bool showMilestones,

    /// The interval for milestone notifications.
    /// Only used if showMilestones is true.
    @Default(10) int milestoneInterval,
  }) = _CounterSettings;

  /// Creates CounterSettings from JSON.
  ///
  /// This is required for JSON serialization.
  /// Run `dart run build_runner build` after modifying this class.
  factory CounterSettings.fromJson(Map<String, dynamic> json) =>
      _$CounterSettingsFromJson(json);

  /// Private constructor for adding custom methods.
  const CounterSettings._();
}
