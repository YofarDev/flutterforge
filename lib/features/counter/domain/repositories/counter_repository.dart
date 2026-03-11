import 'package:fpdart/fpdart.dart';
import '../../../../core/models/failure.dart';
import '../models/counter_settings.dart';

abstract class ICounterRepository {
  Future<Either<Failure, CounterSettings>> getSettings();
  Future<Either<Failure, void>> saveSettings(CounterSettings settings);
}
