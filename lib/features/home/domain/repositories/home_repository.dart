import 'package:fpdart/fpdart.dart';
import '../../../../core/models/failure.dart';
import '../models/home_data.dart';

abstract class IHomeRepository {
  Future<Either<Failure, HomeData>> getHomeData();
}
