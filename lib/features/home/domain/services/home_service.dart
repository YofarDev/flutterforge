import 'package:fpdart/fpdart.dart';
import '../../../../core/models/failure.dart';
import '../repositories/home_repository.dart';
import '../models/home_data.dart';

class HomeService {
  final IHomeRepository _repository;

  HomeService(this._repository);

  Future<Either<Failure, HomeData>> loadHomeData() async {
    return _repository.getHomeData();
  }

  String formatWelcomeMessage(String message) {
    return message.trim().isEmpty ? 'Welcome!' : message;
  }
}
