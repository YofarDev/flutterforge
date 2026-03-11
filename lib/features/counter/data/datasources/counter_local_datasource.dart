import '../models/counter_settings_dto.dart';

abstract class ICounterLocalDataSource {
  Future<CounterSettingsDto> getSettings();
  Future<void> saveSettings(CounterSettingsDto settings);
}

class CounterLocalDataSource implements ICounterLocalDataSource {
  CounterSettingsDto _settings = const CounterSettingsDto();

  @override
  Future<CounterSettingsDto> getSettings() async {
    // In a real app, this would use SharedPreferences or Hive
    return _settings;
  }

  @override
  Future<void> saveSettings(CounterSettingsDto settings) async {
    _settings = settings;
  }
}
