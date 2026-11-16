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
      // Inside the try: a malformed payload becomes a typed failure.
      final HomeData data = dto.toDomain();
      return Right<Failure, HomeData>(data);
    } catch (e, st) {
      return Left<Failure, HomeData>(
        mapExceptionToFailure(e, stackTrace: st, tag: 'HomeRepository'),
      );
    }
  }
}
