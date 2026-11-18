# Mocktail Cheatsheet & Examples

## Mocktail Reference

```dart
// Stub a method
when(() => mock.method(any())).thenReturn(value);
when(() => mock.method(any())).thenAnswer((_) async => value);
when(() => mock.method(any())).thenThrow(Exception());

// Named params
when(() => mock.login(email: any(named: 'email'), password: any(named: 'password')))
    .thenAnswer((_) async => fakeUser);

// Verify
verify(() => mock.method(expectedArg)).called(1);
verifyNever(() => mock.method(any()));

// Capture
final captured = verify(() => mock.method(captureAny())).captured;
expect(captured.single, expectedArg);

// Streams for cubits/blocs
whenListen(mockCubit, Stream.fromIterable([state1, state2]));

// Register fallback values for custom types
setUpAll(() {
  registerFallbackValue(const AuthState.initial());
  registerFallbackValue(FakeUser());
});
```

## Complete Test Examples

### Cubit Test with `bloc_test`

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository mockRepo;
  late AuthCubit cubit;

  setUp(() {
    mockRepo = MockAuthRepository();
    cubit = AuthCubit(mockRepo);
  });

  tearDown(() => cubit.close());

  group('AuthCubit', () {
    blocTest<AuthCubit, AuthState>(
      'emits [loading, authenticated] on success',
      build: () {
        when(() => mockRepo.login(any(), any()))
            .thenAnswer((_) async => Right(fakeUser));
        return cubit;
      },
      act: (c) => c.login('a@b.com', 'pass'),
      expect: () => [
        const AuthState.loading(),
        AuthState.authenticated(fakeUser),
      ],
    );

    blocTest<AuthCubit, AuthState>(
      'emits [loading, failure] on repository error',
      build: () {
        when(() => mockRepo.login(any(), any()))
            .thenAnswer((_) async => const Left(Failure.unauthorized()));
        return cubit;
      },
      act: (c) => c.login('a@b.com', 'wrong'),
      expect: () => [
        const AuthState.loading(),
        const AuthState.failure(failure: Failure.unauthorized()),
      ],
    );
  });
}
```

### Repository Test

```dart
class MockAuthApi extends Mock implements AuthApi {}

void main() {
  late MockAuthApi mockApi;
  late AuthRepository repo;

  setUp(() {
    mockApi = MockAuthApi();
    repo = AuthRepository(mockApi);
  });

  group('AuthRepository.login', () {
    test('maps dto to domain user on success', () async {
      when(() => mockApi.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenAnswer((_) async => fakeUserDto);

      final result = await repo.login('a@b.com', 'pass');

      verify(() => mockApi.login(
        email: 'a@b.com',
        password: 'pass',
      )).called(1);

      result.fold(
        (_) => fail('Expected Right(User)'),
        (user) => expect(user.id, fakeUserDto.id),
      );
    });

    test('returns a typed Left(Failure) on API exception', () async {
      when(() => mockApi.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenThrow(ApiException(statusCode: 401, message: 'Unauthorized'));

      final Either<Failure, User> result = await repo.login('a@b.com', 'wrong');

      result.fold(
        // Assert the failure *category*; Failure carries no user-facing
        // message by design (diagnostics are for logs only).
        (failure) => expect(failure, isA<FailureUnauthorized>()),
        (_) => fail('Expected Left(Failure)'),
      );
    });
  });
}
```

### Widget Test

```dart
class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

void main() {
  group('LoginForm', () {
    testWidgets('shows error banner when state is failure', (tester) async {
      final mockCubit = MockAuthCubit();
      when(() => mockCubit.state).thenReturn(const AuthState.initial());
      whenListen(
        mockCubit,
        Stream.fromIterable(
          [const AuthState.failure(failure: Failure.unauthorized())],
        ),
        initialState: const AuthState.initial(),
      );

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: mockCubit,
          // Localized failure text comes from localizeFailure(); assert the
          // localized string for the test locale, never a diagnostic message.
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: LoginForm()),
          ),
        ),
      );

      await tester.pump();

      expect(find.text(l10n.failureUnauthorized), findsOneWidget);
    });

    testWidgets('calls cubit.login on form submit', (tester) async {
      final mockCubit = MockAuthCubit();
      when(() => mockCubit.state).thenReturn(const AuthState.initial());
      when(() => mockCubit.login(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: mockCubit,
          child: const MaterialApp(home: Scaffold(body: LoginForm())),
        ),
      );

      await tester.enterText(find.byKey(const Key('email_field')), 'a@b.com');
      await tester.enterText(find.byKey(const Key('password_field')), 'pass');
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pump();

      verify(() => mockCubit.login('a@b.com', 'pass')).called(1);
    });
  });
}
```

### Navigation and wiring

Do not mock `GoRouter` or `pumpAndSettle` to verify navigation. Use the feature's
flow test (`test/features/<f>/<f>_flow_test.dart`): real module registrations on
`GetIt.asNewInstance()`, real route, fake data source only. See `test/README.md`.

### Golden Test

Uses `testWidgets` with the built-in `matchesGoldenFile` matcher (no extra
package — `flutter_test` has no `testGoldens`).

```dart
void main() {
  testWidgets('LoginScreen renders correctly', (tester) async {
    final mockCubit = MockAuthCubit();
    when(() => mockCubit.state).thenReturn(const AuthState.initial());

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      BlocProvider<AuthCubit>.value(
        value: mockCubit,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('goldens/login_screen_initial.png'),
    );
  });
}
```
