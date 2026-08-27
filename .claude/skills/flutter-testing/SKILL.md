---
name: "flutter-testing"
description: "Use when writing tests for Flutter projects, including unit tests, widget tests, bloc tests, or when the user asks how to test specific components (cubits, repositories, screens, domain services). Triggers include: 'write tests for this', 'add unit tests', 'test my cubit', 'test my repository', 'write widget tests', 'improve test coverage', 'write a bloc_test', 'mock this dependency', 'add golden tests', 'how do I test X in Flutter', 'how should I test navigation', 'how do I test a freezed state', 'should I use mockito or mocktail', 'test my domain service'. Always use alongside flutter-architecture when writing tests for existing features."
---

# Flutter Testing

## Quick Reference

| Test Type | Tool | What to Test |
|-----------|------|--------------|
| Cubits/BLoCs | `bloc_test` | Public methods, state order, error paths |
| Repositories | `mocktail` | Parameter forwarding, DTO mapping, failure translation |
| Domain services | `flutter_test` + `mocktail` | Coordination logic, edge cases, no cubit deps |
| Widgets | `flutter_test` | UI branches, interactions, provider wiring |
| Screens | `flutter_test` | Integration with fake or mock cubits |

**Read `flutter-architecture` first** — tests should mirror the intended boundaries and lifecycles.

## Setup

Add `bloc_test` and `mocktail` when they are not already present. Golden tests use the built-in `matchesGoldenFile` matcher — no extra package needed. Match the repository's existing version constraints instead of introducing pinned versions from this skill.

## Test Structure (Mirrors `lib/`)

```text
test/
├── core/
│   └── services/
│       └── session_service_test.dart
└── features/
    └── auth/
        ├── data/auth_repository_test.dart
        ├── domain/login_use_case_test.dart
        └── presentation/
            ├── bloc/auth_cubit_test.dart
            └── screens/login_screen_test.dart
```

## Cubit Test (`bloc_test`)

```dart
blocTest<AuthCubit, AuthState>(
  'emits [loading, authenticated] on success',
  build: () {
    when(() => mockRepo.login(any(), any()))
        .thenAnswer((_) async => Right(fakeUser));
    return cubit;
  },
  act: (c) => c.login('user@ex.com', 'pass'),
  expect: () => [
    const AuthState.loading(),
    AuthState.authenticated(fakeUser),
  ],
);
```

**Test every public method, every meaningful state transition, and every error path.**

### Testing that a cubit uses a domain service

When a cubit delegates to a domain service, verify the delegation here and test the service's
internal coordination in its own test file.

```dart
class MockSessionService extends Mock implements SessionService {}

blocTest<AuthCubit, AuthState>(
  'notifies session service on login',
  build: () {
    when(() => mockSession.onUserLoggedIn(any())).thenReturn(null);
    return AuthCubit(repo: mockRepo, session: mockSession);
  },
  act: (c) => c.login('user@ex.com', 'pass'),
  verify: (_) {
    verify(() => mockSession.onUserLoggedIn(any())).called(1);
  },
);
```

## Repository Test

A repository test should prove three things: correct API call, correct mapping, and correct failure translation.

```dart
test('maps API dto to domain user on success', () async {
  when(() => mockApi.login(
    email: any(named: 'email'),
    password: any(named: 'password'),
  )).thenAnswer((_) async => fakeUserDto);

  final result = await repo.login('user@ex.com', 'pass');

  verify(() => mockApi.login(
    email: 'user@ex.com',
    password: 'pass',
  )).called(1);

  result.fold(
    (_) => fail('Expected Right(User)'),
    (user) {
      expect(user.id, fakeUserDto.id);
      expect(user.email, fakeUserDto.email);
    },
  );
});

test('translates ApiException into Failure', () async {
  when(() => mockApi.login(
    email: any(named: 'email'),
    password: any(named: 'password'),
  )).thenThrow(ApiException(message: 'Unauthorized'));

  final result = await repo.login('user@ex.com', 'wrong');

  result.fold(
    (failure) => expect(failure.message, 'Unauthorized'),
    (_) => fail('Expected Left(Failure)'),
  );
});
```

## Domain Service Test

Domain services hold coordination logic extracted from cubits. Test them in isolation:
no widgets, no providers, no `blocTest` unless the service itself is a bloc.

```dart
void main() {
  late SessionService service;

  setUp(() => service = SessionService());

  group('SessionService', () {
    test('marks user as logged in', () {
      service.onUserLoggedIn(testUser);
      expect(service.currentUser, testUser);
    });

    test('clears user on logout', () {
      service.onUserLoggedIn(testUser);
      service.onUserLoggedOut();
      expect(service.currentUser, isNull);
    });

    test('logout is idempotent when already logged out', () {
      expect(() => service.onUserLoggedOut(), returnsNormally);
    });
  });
}
```

## Widget Test

For widgets driven by a cubit, either use `MockCubit` + `whenListen` or a fake cubit that exposes a test-only helper method.

```dart
class FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  FakeAuthCubit() : super(const AuthState.initial());

  void pushState(AuthState nextState) => emit(nextState);

  @override
  Future<void> login(String e, String p) async {}
}

testWidgets('shows error on failure', (tester) async {
  final fakeCubit = FakeAuthCubit();
  addTearDown(fakeCubit.close);

  await tester.pumpWidget(
    BlocProvider.value(
      value: fakeCubit,
      child: const MaterialApp(home: LoginForm()),
    ),
  );

  fakeCubit.pushState(const AuthState.failure('Error'));
  await tester.pump();

  expect(find.text('Error'), findsOneWidget);
});
```

## Golden Test

Uses the built-in `matchesGoldenFile` matcher — no extra package needed.

```dart
testGoldens('renders correctly', (tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    BlocProvider.value(
      value: mockCubit,
      child: const MaterialApp(home: LoginScreen()),
    ),
  );

  await expectLater(
    find.byType(LoginScreen),
    matchesGoldenFile('goldens/login_screen.png'),
  );
});
```

## Coverage Checklist

**Cubit/BLoC:**
- [ ] Happy path
- [ ] Error path
- [ ] Exact state order where it matters
- [ ] Delegation to domain services verified
- [ ] No assertions on another cubit's state

**Repository:**
- [ ] Arguments forwarded correctly
- [ ] DTO mapped to domain entity/value object
- [ ] `Left(Failure)` produced on errors
- [ ] Failure message/type translated correctly

**Domain service:**
- [ ] Core coordination logic
- [ ] Edge cases (idempotency, empty input, repeated calls)
- [ ] No cubit imports in the test file

**Widget/Screen:**
- [ ] Each relevant UI branch
- [ ] User interactions
- [ ] Provider wiring for the expected subtree

## Anti-Patterns

| ❌ Wrong | ✅ Fix |
|---------|-------|
| Test private vars | Test public state + behavior |
| Real repos in tests | Inject mocks/fakes via constructor |
| `pumpAndSettle()` everywhere | Prefer targeted `pump()` calls; use `pumpAndSettle()` only when you truly need it |
| `state.runtimeType` | Use `isA<StateType>()` or assert a concrete state value |
| Repository test only checks `isRight()` | Assert mapped value and failure translation |
| Skip error paths | Every `try/catch` needs a test |
| Use `mockito` by default | Prefer `mocktail` to avoid generation unless the project already standardizes on something else |
| Assert on another cubit's state in a cubit test | Test each cubit in isolation |
| Call `emit()` directly from the test body | Use `whenListen`, `MockCubit`, or a fake helper like `pushState()` |

## See Also
- `mocktail-cheatsheet.md` — Reference snippets and complete examples
