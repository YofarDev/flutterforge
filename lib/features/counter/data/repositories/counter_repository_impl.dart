import 'package:fpdart/fpdart.dart';
import '../../../../core/models/failure.dart';
import '../../domain/repositories/counter_repository.dart';
import '../../domain/models/counter_settings.dart';
import '../datasources/counter_local_datasource.dart';
import '../models/counter_settings_dto.dart';

class CounterRepository implements ICounterRepository {
  final ICounterLocalDataSource _dataSource;

  CounterRepository(this._dataSource);

  @override
  Future<Either<Failure, CounterSettings>> getSettings() async {
    try {
      final CounterSettingsDto dto = await _dataSource.getSettings();
      return Right<Failure, CounterSettings>(dto.toDomain());
    } catch (e) {
      return Left<Failure, CounterSettings>(Failure.serverError(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> saveSettings(CounterSettings settings) async {
    try {
      final CounterSettingsDto dto = CounterSettingsDto.fromDomain(settings);
      await _dataSource.saveSettings(dto);
      return const Right<Failure, void>(null);
    } catch (e) {
      return Left<Failure, void>(Failure.serverError(message: e.toString()));
    }
  }
}
