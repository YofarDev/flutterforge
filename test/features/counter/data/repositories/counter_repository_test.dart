import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/counter/data/datasources/counter_local_datasource.dart';
import 'package:my_flutter_app/features/counter/data/models/counter_settings_dto.dart';
import 'package:my_flutter_app/features/counter/data/repositories/counter_repository_impl.dart';
import 'package:my_flutter_app/features/counter/domain/models/counter_settings.dart';

class MockCounterLocalDataSource extends Mock
    implements ICounterLocalDataSource {}

void main() {
  late CounterRepository repository;
  late MockCounterLocalDataSource mockDataSource;

  setUpAll(() {
    registerFallbackValue(const CounterSettingsDto());
  });

  setUp(() {
    mockDataSource = MockCounterLocalDataSource();
    repository = CounterRepository(mockDataSource);
  });

  group('CounterRepository', () {
    group('getSettings', () {
      test('returns Right(CounterSettings) on success', () async {
        const CounterSettingsDto dto = CounterSettingsDto(
          stepSize: 5,
          minValue: -10,
          maxValue: 100,
        );
        when(() => mockDataSource.getSettings()).thenAnswer((_) async => dto);

        final Either<Failure, CounterSettings> result = await repository
            .getSettings();

        expect(result.isRight(), true);
        result.fold((_) => fail('Should not return Left'), (
          CounterSettings settings,
        ) {
          expect(settings.stepSize, 5);
          expect(settings.minValue, -10);
          expect(settings.maxValue, 100);
        });
        verify(() => mockDataSource.getSettings()).called(1);
      });

      test('returns Left(Failure) when datasource throws', () async {
        when(
          () => mockDataSource.getSettings(),
        ).thenThrow(Exception('Storage error'));

        final Either<Failure, CounterSettings> result = await repository
            .getSettings();

        expect(result.isLeft(), true);
        result.fold((Failure failure) {
          expect(
            failure.map(
              serverError: (_) => true,
              networkError: (_) => false,
              unauthorized: (_) => false,
            ),
            true,
          );
        }, (_) => fail('Should not return Right'));
      });

      test('maps DTO to domain correctly', () async {
        const CounterSettingsDto dto = CounterSettingsDto(stepSize: 3);
        when(() => mockDataSource.getSettings()).thenAnswer((_) async => dto);

        final Either<Failure, CounterSettings> result = await repository
            .getSettings();

        result.fold((_) => fail('Should not return Left'), (
          CounterSettings settings,
        ) {
          expect(settings, isA<CounterSettings>());
          expect(settings.stepSize, equals(dto.stepSize));
        });
      });
    });

    group('saveSettings', () {
      test('returns Right(null) on success', () async {
        const CounterSettings settings = CounterSettings(stepSize: 2);
        when(() => mockDataSource.saveSettings(any())).thenAnswer((_) async {});

        final Either<Failure, void> result = await repository.saveSettings(
          settings,
        );

        expect(result.isRight(), true);
        verify(() => mockDataSource.saveSettings(any())).called(1);
      });

      test('returns Left(Failure) when datasource throws', () async {
        const CounterSettings settings = CounterSettings(stepSize: 2);
        when(
          () => mockDataSource.saveSettings(any()),
        ).thenThrow(Exception('Save failed'));

        final Either<Failure, void> result = await repository.saveSettings(
          settings,
        );

        expect(result.isLeft(), true);
        result.fold((Failure failure) {
          expect(
            failure.map(
              serverError: (_) => true,
              networkError: (_) => false,
              unauthorized: (_) => false,
            ),
            true,
          );
        }, (_) => fail('Should not return Right'));
      });

      test('converts domain to DTO before saving', () async {
        const CounterSettings settings = CounterSettings(
          stepSize: 4,
          minValue: -5,
          maxValue: 50,
        );
        when(() => mockDataSource.saveSettings(any())).thenAnswer((_) async {});

        await repository.saveSettings(settings);

        verify(() => mockDataSource.saveSettings(any())).called(1);
      });
    });
  });
}
