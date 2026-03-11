import 'package:fpdart/fpdart.dart';
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
      return Right<Failure, HomeData>(dto.toDomain());
    } catch (e) {
      return Left<Failure, HomeData>(Failure.serverError(message: e.toString()));
    }
  }
}
