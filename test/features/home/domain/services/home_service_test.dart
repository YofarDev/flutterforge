import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_flutter_app/core/models/failure.dart';
import 'package:my_flutter_app/features/home/domain/models/home_data.dart';
import 'package:my_flutter_app/features/home/domain/repositories/home_repository.dart';
import 'package:my_flutter_app/features/home/domain/services/home_service.dart';

class MockHomeRepository extends Mock implements IHomeRepository {}

void main() {
  late HomeService service;
  late MockHomeRepository mockRepository;

  setUp(() {
    mockRepository = MockHomeRepository();
    service = HomeService(mockRepository);
  });

  group('HomeService', () {
    group('loadHomeData', () {
      test('delegates to repository and returns Right on success', () async {
        final HomeData data = HomeData(
          welcomeMessage: 'Welcome!',
          lastUpdated: DateTime(2024),
        );
        when(
          () => mockRepository.getHomeData(),
        ).thenAnswer((_) async => Right<Failure, HomeData>(data));

        final Either<Failure, HomeData> result = await service.loadHomeData();

        expect(result.isRight(), true);
        verify(() => mockRepository.getHomeData()).called(1);
      });

      test('delegates to repository and returns Left on failure', () async {
        when(() => mockRepository.getHomeData()).thenAnswer(
          (_) async => const Left<Failure, HomeData>(
            Failure.serverError(message: 'error'),
          ),
        );

        final Either<Failure, HomeData> result = await service.loadHomeData();

        expect(result.isLeft(), true);
        verify(() => mockRepository.getHomeData()).called(1);
      });
    });

    group('formatWelcomeMessage', () {
      test('returns message when not empty', () {
        expect(service.formatWelcomeMessage('Hello'), 'Hello');
        expect(service.formatWelcomeMessage('Welcome!'), 'Welcome!');
        expect(service.formatWelcomeMessage('  Hello  '), '  Hello  ');
      });

      test('returns "Welcome!" when message is empty', () {
        expect(service.formatWelcomeMessage(''), 'Welcome!');
      });

      test('returns "Welcome!" when message is whitespace only', () {
        expect(service.formatWelcomeMessage('   '), 'Welcome!');
        expect(service.formatWelcomeMessage('\t\n'), 'Welcome!');
        expect(service.formatWelcomeMessage('  \t  \n  '), 'Welcome!');
      });

      test('trims message before checking emptiness', () {
        expect(service.formatWelcomeMessage('  Hello  '), '  Hello  ');
        expect(service.formatWelcomeMessage('\tHi\n'), '\tHi\n');
      });
    });
  });
}
