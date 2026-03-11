import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/counter/domain/models/counter_settings.dart';
import 'package:my_flutter_app/features/counter/domain/repositories/counter_repository.dart';
import 'package:my_flutter_app/features/counter/domain/services/counter_service.dart';

class MockCounterRepository extends Mock implements ICounterRepository {}

void main() {
  late CounterService service;
  late MockCounterRepository mockRepository;

  setUp(() {
    mockRepository = MockCounterRepository();
    service = CounterService(mockRepository);
  });

  group('CounterService', () {
    group('getSettings', () {
      test('delegates to repository and returns Right on success', () async {
        const CounterSettings settings = CounterSettings(stepSize: 5);
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => const Right<Failure, CounterSettings>(settings),
        );

        final Either<Failure, CounterSettings> result = await service
            .getSettings();

        expect(result.isRight(), true);
        verify(() => mockRepository.getSettings()).called(1);
      });

      test('delegates to repository and returns Left on failure', () async {
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => const Left<Failure, CounterSettings>(
            Failure.serverError(message: 'error'),
          ),
        );

        final Either<Failure, CounterSettings> result = await service
            .getSettings();

        expect(result.isLeft(), true);
        verify(() => mockRepository.getSettings()).called(1);
      });
    });

    group('clampValue', () {
      test('returns value when within range', () {
        const CounterSettings settings = CounterSettings(
          minValue: 0,
          maxValue: 100,
        );

        expect(service.clampValue(50, settings), 50);
        expect(service.clampValue(0, settings), 0);
        expect(service.clampValue(100, settings), 100);
      });

      test('clamps value below minimum', () {
        const CounterSettings settings = CounterSettings(
          minValue: 0,
          maxValue: 100,
        );

        expect(service.clampValue(-5, settings), 0);
        expect(service.clampValue(-100, settings), 0);
      });

      test('clamps value above maximum', () {
        const CounterSettings settings = CounterSettings(
          minValue: 0,
          maxValue: 100,
        );

        expect(service.clampValue(105, settings), 100);
        expect(service.clampValue(999, settings), 100);
      });

      test('handles null min/max (no bounds)', () {
        const CounterSettings settings = CounterSettings(stepSize: 1);

        expect(service.clampValue(-1000, settings), -1000);
        expect(service.clampValue(1000, settings), 1000);
      });
    });

    group('applyStepSize', () {
      test('adds stepSize to value', () {
        const CounterSettings settings = CounterSettings(stepSize: 5);

        expect(service.applyStepSize(0, settings), 5);
        expect(service.applyStepSize(10, settings), 15);
        expect(service.applyStepSize(-5, settings), 0);
      });

      test('handles different step sizes', () {
        const CounterSettings settings1 = CounterSettings(stepSize: 1);
        const CounterSettings settings10 = CounterSettings(stepSize: 10);
        const CounterSettings settings100 = CounterSettings(stepSize: 100);

        expect(service.applyStepSize(0, settings1), 1);
        expect(service.applyStepSize(0, settings10), 10);
        expect(service.applyStepSize(0, settings100), 100);
      });

      test('default stepSize is 1', () {
        const CounterSettings settings = CounterSettings();

        expect(service.applyStepSize(5, settings), 6);
      });
    });
  });
}
