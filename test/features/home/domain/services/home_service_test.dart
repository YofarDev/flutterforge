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
        when(() => mockRepository.getHomeData())
            .thenAnswer((_) async => Right<Failure, HomeData>(data));

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
      test('returns message unchanged when already trimmed', () {
        expect(service.formatWelcomeMessage('Hello'), 'Hello');
        expect(service.formatWelcomeMessage('Welcome!'), 'Welcome!');
      });

      test('trims surrounding whitespace', () {
        expect(service.formatWelcomeMessage('  Hello  '), 'Hello');
        expect(service.formatWelcomeMessage('\tHi\n'), 'Hi');
      });

      test('returns empty string when there is no message', () {
        // The presentation layer falls back to a localized default on empty.
        expect(service.formatWelcomeMessage(''), '');
        expect(service.formatWelcomeMessage('   '), '');
        expect(service.formatWelcomeMessage('\t\n'), '');
        expect(service.formatWelcomeMessage('  \t  \n  '), '');
      });
    });
  });
}
