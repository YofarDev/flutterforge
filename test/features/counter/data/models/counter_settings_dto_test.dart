import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/features/counter/data/models/counter_settings_dto.dart';
import 'package:my_flutter_app/features/counter/domain/models/counter_settings.dart';

void main() {
  group('CounterSettingsDto', () {
    test('full round trip preserves every field with non-default values', () {
      // domain → DTO → JSON → DTO → domain
      const CounterSettings domain = CounterSettings(
        stepSize: 3,
        minValue: -5,
        maxValue: 50,
        showMilestones: true,
        milestoneInterval: 7,
      );

      final CounterSettingsDto firstDto = CounterSettingsDto.fromDomain(domain);
      final Map<String, dynamic> json = firstDto.toJson();
      final CounterSettingsDto secondDto = CounterSettingsDto.fromJson(json);
      final CounterSettings restored = secondDto.toDomain();

      expect(restored, equals(domain));
      expect(restored.stepSize, 3);
      expect(restored.minValue, -5);
      expect(restored.maxValue, 50);
      expect(restored.showMilestones, true);
      expect(restored.milestoneInterval, 7);
    });

    test('nullable bounds survive the round trip', () {
      const CounterSettings domain = CounterSettings(
        stepSize: 2,
        minValue: null,
        maxValue: null,
      );

      final CounterSettingsDto dto = CounterSettingsDto.fromDomain(domain);
      final CounterSettings restored = CounterSettingsDto.fromJson(dto.toJson())
          .toDomain();

      expect(restored.minValue, isNull);
      expect(restored.maxValue, isNull);
      expect(restored.stepSize, 2);
    });

    test('older JSON without milestone keys restores domain defaults', () {
      // A payload persisted before the milestone settings existed must not
      // lose or corrupt them: the DTO defaults mirror the domain defaults.
      final Map<String, dynamic> legacyJson = <String, dynamic>{
        'stepSize': 4,
        'minValue': -10,
        'maxValue': 100,
      };

      final CounterSettings restored = CounterSettingsDto.fromJson(legacyJson)
          .toDomain();

      expect(restored.stepSize, 4);
      expect(restored.minValue, -10);
      expect(restored.maxValue, 100);
      expect(restored.showMilestones, false);
      expect(restored.milestoneInterval, 10);
    });

    test('fromDomain maps milestone settings to the DTO', () {
      const CounterSettings domain = CounterSettings(
        showMilestones: true,
        milestoneInterval: 25,
      );

      final CounterSettingsDto dto = CounterSettingsDto.fromDomain(domain);

      expect(dto.showMilestones, true);
      expect(dto.milestoneInterval, 25);
    });
  });
}
