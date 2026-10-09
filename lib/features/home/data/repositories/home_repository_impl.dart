import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exception_mapper.dart';
import '../../../../core/models/failure.dart';
import '../../domain/repositories/home_repository.dart';
import '../../domain/models/home_data.dart';
import '../datasources/home_remote_datasource.dart';
import '../models/home_data_dto.dart';

class HomeRepository implements IHomeRepository {
  final IHomeRemoteDataSource _remoteDataSource;

  HomeRepository(this._remoteDataSource);

  @override
  Future<Either<Failure, HomeData>> getHomeData() async {
    try {
      final HomeDataDto dto = await _remoteDataSource.getHomeData();
      // DTO conversion happens inside the guarded boundary: a malformed
      // payload (bad date, bad JSON) is mapped to a typed failure instead of
      // escaping as an exception.
      final HomeData data = dto.toDomain();
      return Right<Failure, HomeData>(data);
    } catch (e, st) {
      // Logs the error and stack trace once, at the mapping boundary.
      return Left<Failure, HomeData>(
        mapExceptionToFailure(e, stackTrace: st, tag: 'HomeRepository'),
      );
    }
  }
}
