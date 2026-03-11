import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/home/data/datasources/home_remote_datasource.dart';
import 'package:my_flutter_app/features/home/data/models/home_data_dto.dart';
import 'package:my_flutter_app/features/home/data/repositories/home_repository_impl.dart';
import 'package:my_flutter_app/features/home/domain/models/home_data.dart';

class MockHomeRemoteDataSource extends Mock implements IHomeRemoteDataSource {}

void main() {
  late HomeRepository repository;
  late MockHomeRemoteDataSource mockDataSource;

  setUpAll(() {
    registerFallbackValue(
      HomeDataDto(welcomeMessage: 'test', lastUpdated: '2024-01-01'),
    );
  });

  setUp(() {
    mockDataSource = MockHomeRemoteDataSource();
    repository = HomeRepository(mockDataSource);
  });

  group('HomeRepository', () {
    group('getHomeData', () {
      test('returns Right(HomeData) on success', () async {
        final HomeDataDto dto = HomeDataDto(
          welcomeMessage: 'Welcome!',
          lastUpdated: '2024-01-01T00:00:00.000',
        );
        when(() => mockDataSource.getHomeData()).thenAnswer((_) async => dto);

        final Either<Failure, HomeData> result = await repository.getHomeData();

        expect(result.isRight(), true);
        result.fold((_) => fail('Should not return Left'), (HomeData data) {
          expect(data.welcomeMessage, 'Welcome!');
          expect(data.lastUpdated.year, 2024);
        });
        verify(() => mockDataSource.getHomeData()).called(1);
      });

      test('returns Left(Failure) when datasource throws', () async {
        when(
          () => mockDataSource.getHomeData(),
        ).thenThrow(Exception('Network error'));

        final Either<Failure, HomeData> result = await repository.getHomeData();

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
        final HomeDataDto dto = HomeDataDto(
          welcomeMessage: 'Hello World',
          lastUpdated: '2024-06-15T12:30:00.000',
        );
        when(() => mockDataSource.getHomeData()).thenAnswer((_) async => dto);

        final Either<Failure, HomeData> result = await repository.getHomeData();

        result.fold((_) => fail('Should not return Left'), (HomeData data) {
          expect(data, isA<HomeData>());
          expect(data.welcomeMessage, equals(dto.welcomeMessage));
          expect(data.lastUpdated.month, 6);
          expect(data.lastUpdated.day, 15);
        });
      });
    });
  });
}
