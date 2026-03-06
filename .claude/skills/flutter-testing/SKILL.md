---
name: flutter-testing
description: Use when writing tests for Flutter projects, including unit tests, widget tests, bloc tests, or when the user asks how to test specific components (cubits, repositories, screens). Triggers include: 'write tests for this', 'add unit tests', 'test my cubit', 'test my repository', 'write widget tests', 'improve test coverage', 'write a bloc_test', 'mock this dependency', 'add golden tests', 'how do I test X in Flutter', 'how should I test navigation', 'how do I test a freezed state', 'should I use mockito or mocktail'. Always use alongside flutter-architecture when writing tests for existing features.
license: MIT
---

# Flutter Testing

## Quick Reference

| Test Type | Tool | What to Test |
|-----------|------|--------------|
| Cubits/BLoCs | `bloc_test` | Every method, all states, error paths |
| Repositories | `mocktail` | API calls, mapping, errors |
| Widgets | `flutter_test` | States, taps, inputs |
| Screens | `flutter_test` | Integration with fake cubits |

**Read `flutter-architecture` first** — tests must mirror architecture.

## Setup

```yaml
dev_dependencies:
  bloc_test: ^9.1.0
  mocktail: ^1.0.0
  golden_toolkit: ^0.15.0
```

## Test Structure (Mirrors lib/)

```
test/features/auth/
├── data/auth_repository_test.dart
├── domain/login_use_case_test.dart
└── presentation/
    ├── bloc/auth_cubit_test.dart
    └── screens/login_screen_test.dart
```

## Cubit Test (bloc_test)

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

**Test every method, every state, every error path.**

## Repository Test

```dart
test('returns Right(User) on success', () async {
  when(() => mockApi.login(
    email: any(named: 'email'),
    password: any(named: 'password'),
  )).thenAnswer((_) async => fakeUserDto);

  final result = await repo.login('user@ex.com', 'pass');

  expect(result.isRight(), true);
});
```

## Widget Test

```dart
testWidgets('shows error on failure', (tester) async {
  final fakeCubit = FakeAuthCubit();

  await tester.pumpWidget(
    BlocProvider.value(
      value: fakeCubit,
      child: const MaterialApp(home: LoginForm()),
    ),
  );

  fakeCubit.emit(const AuthState.failure('Error'));
  await tester.pump();

  expect(find.text('Error'), findsOneWidget);
});

// Use FakeCubit for simple state emission
class FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  FakeAuthCubit() : super(const AuthState.initial());
  @override
  Future<void> login(String e, String p) async {}
}
```

## Golden Test

```dart
testGoldens('renders correctly', (tester) async {
  await tester.pumpWidgetBuilder(
    BlocProvider.value(
      value: mockCubit,
      child: const LoginScreen(),
    ),
    surfaceSize: const Size(390, 844),
  );

  await screenMatchesGolden(tester, 'login');
});
```

## Coverage Checklist

**Cubit/BLoC:**
- [ ] Happy path (correct states in order)
- [ ] Error path (failure emitted, not swallowed)
- [ ] Loading state emitted first
- [ ] `expect()` list is exact

**Repository:**
- [ ] DTO → entity mapping
- [ ] `Right(value)` on success
- [ ] `Left(Failure)` on errors
- [ ] Exceptions wrapped

**Widget:**
- [ ] Each relevant state
- [ ] User interactions
- [ ] All UI branches

## Anti-Patterns

| ❌ Wrong | ✅ Fix |
|---------|-------|
| Test private vars | Test public state + behavior |
| Real repos in tests | Inject mocks via constructor |
| `pumpAndSettle()` everywhere | Use `pump(duration)` |
| `state.runtimeType` | Use `isA<StateType>()` |
| Skip error paths | Every `try/catch` needs test |
| Use `mockito` | Use `mocktail` (no generation) |

## See Also
- `mocktail-cheatsheet.md` — Full mocktail API reference, complete examples
