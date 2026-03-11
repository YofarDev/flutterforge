import 'package:fpdart/fpdart.dart';
import '../../../../core/models/failure.dart';
import '../repositories/counter_repository.dart';
import '../models/counter_settings.dart';

class CounterService {
  final ICounterRepository _repository;

  CounterService(this._repository);

  Future<Either<Failure, CounterSettings>> getSettings() {
    return _repository.getSettings();
  }

  int clampValue(int value, CounterSettings settings) {
    int result = value;
    final int? min = settings.minValue;
    final int? max = settings.maxValue;
    if (min != null && result < min) {
      result = min;
    }
    if (max != null && result > max) {
      result = max;
    }
    return result;
  }

  int applyStepSize(int value, CounterSettings settings) {
    return value + settings.stepSize;
  }
}
