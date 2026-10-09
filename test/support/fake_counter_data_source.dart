import 'package:my_flutter_app/features/counter/data/datasources/counter_local_datasource.dart';
import 'package:my_flutter_app/features/counter/data/models/counter_settings_dto.dart';

/// Fake persistence seam for the counter: always returns the configured
/// settings (or throws when [FailingCounterDataSource] is preferred).
class FakeCounterLocalDataSource implements ICounterLocalDataSource {
  FakeCounterLocalDataSource(this._settings);

  final CounterSettingsDto _settings;

  @override
  Future<CounterSettingsDto> getSettings() async => _settings;

  @override
  Future<void> saveSettings(CounterSettingsDto settings) async {}
}

/// Persistence seam whose read always fails, so the repository produces a
/// typed Left(Failure) through the real mapping boundary.
class FailingCounterLocalDataSource implements ICounterLocalDataSource {
  @override
  Future<CounterSettingsDto> getSettings() async {
    throw Exception('storage broke');
  }

  @override
  Future<void> saveSettings(CounterSettingsDto settings) async {}
}
