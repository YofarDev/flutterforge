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

// Stream for cubits (bloc_test)
whenListen(mockCubit, Stream.fromIterable([state1, state2]));

// Register fallback values for custom types
setUpAll(() {
  registerFallbackValue(const AuthState.initial());
  registerFallbackValue(FakeUser());
});
```

## Complete Test Examples

### Cubit Test with bloc_test

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
            .thenAnswer((_) async => Left(Failure('Invalid credentials')));
        return cubit;
      },
      act: (c) => c.login('a@b.com', 'wrong'),
      expect: () => [
        const AuthState.loading(),
        const AuthState.failure('Invalid credentials'),
      ],
    );

    blocTest<AuthCubit, AuthState>(
      'emits [loading, failure] on unexpected exception',
      build: () {
        when(() => mockRepo.login(any(), any()))
            .thenThrow(Exception('Network error'));
        return cubit;
      },
      act: (c) => c.login('a@b.com', 'pass'),
      expect: () => [
        const AuthState.loading(),
        isA<AuthState>().having(
          (s) => s.whenOrNull(failure: (msg) => msg),
          'has failure message',
          isNotNull,
        ),
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
    test('returns Right(User) on successful API call', () async {
      when(() => mockApi.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenAnswer((_) async => fakeUserDto);

      final result = await repo.login('a@b.com', 'pass');

      expect(result.isRight(), true);
      result.fold(
        (_) => fail('Expected Right'),
        (user) => expect(user.id, fakeUserDto.id),
      );
    });

    test('returns Left(Failure) on 401', () async {
      when(() => mockApi.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenThrow(ApiException(statusCode: 401, message: 'Unauthorized'));

      final result = await repo.login('a@b.com', 'wrong');

      expect(result.isLeft(), true);
    });
  });
}
```

### Widget Test

```dart
void main() {
  group('LoginForm', () {
    testWidgets('shows error banner when state is failure', (tester) async {
      final fakeCubit = FakeAuthCubit();

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: fakeCubit,
          child: const MaterialApp(home: Scaffold(body: LoginForm())),
        ),
      );

      fakeCubit.emit(const AuthState.failure('Invalid credentials'));
      await tester.pump();

      expect(find.text('Invalid credentials'), findsOneWidget);
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

      await tester.enterText(
        find.byKey(const Key('email_field')),
        'a@b.com',
      );
      await tester.enterText(
        find.byKey(const Key('password_field')),
        'pass',
      );
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pump();

      verify(() => mockCubit.login('a@b.com', 'pass')).called(1);
    });
  });
}
```

### Mocking a Cubit for Widget Tests

```dart
// Use mocktail — stubs state stream and state getter
class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

// Use FakeCubit for simple state emission
class FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  FakeAuthCubit() : super(const AuthState.initial());

  @override
  Future<void> login(String email, String password) async {
    emit(const AuthState.loading());
  }
}
```

### Screen Integration Test

```dart
class MockGoRouter extends Mock implements GoRouter {}

void main() {
  testWidgets('navigates to home after successful login', (tester) async {
    final mockCubit = MockAuthCubit();
    final mockRouter = MockGoRouter();

    when(() => mockCubit.state).thenReturn(const AuthState.initial());
    whenListen(
      mockCubit,
      Stream.fromIterable([
        const AuthState.loading(),
        AuthState.authenticated(fakeUser),
      ]),
    );

    await tester.pumpWidget(
      InheritedGoRouter(
        goRouter: mockRouter,
        child: BlocProvider<AuthCubit>.value(
          value: mockCubit,
          child: const MaterialApp(home: LoginScreen()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    verify(() => mockRouter.go('/')).called(1);
  });
}
```

### Golden Test

```dart
void main() {
  testGoldens('LoginScreen renders correctly', (tester) async {
    final mockCubit = MockAuthCubit();
    when(() => mockCubit.state).thenReturn(const AuthState.initial());

    await tester.pumpWidgetBuilder(
      BlocProvider<AuthCubit>.value(
        value: mockCubit,
        child: const LoginScreen(),
      ),
      surfaceSize: const Size(390, 844), // iPhone 14 Pro
    );

    await screenMatchesGolden(tester, 'login_screen_initial');
  });
}
```
