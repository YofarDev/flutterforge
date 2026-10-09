import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exception_mapper.dart';
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
      final CounterSettings settings = dto.toDomain();
      return Right<Failure, CounterSettings>(settings);
    } catch (e, st) {
      return Left<Failure, CounterSettings>(
        mapExceptionToFailure(e, stackTrace: st, tag: 'CounterRepository'),
      );
    }
  }

  @override
  Future<Either<Failure, void>> saveSettings(CounterSettings settings) async {
    try {
      final CounterSettingsDto dto = CounterSettingsDto.fromDomain(settings);
      await _dataSource.saveSettings(dto);
      return const Right<Failure, void>(null);
    } catch (e, st) {
      return Left<Failure, void>(
        mapExceptionToFailure(e, stackTrace: st, tag: 'CounterRepository'),
      );
    }
  }
}
