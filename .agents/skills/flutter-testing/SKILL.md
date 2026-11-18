---
name: "flutter-testing"
description: "Use when writing tests for Flutter projects, including unit tests, widget tests, bloc tests, or when the user asks how to test specific components (cubits, repositories, screens, domain services). Triggers include: 'write tests for this', 'add unit tests', 'test my cubit', 'test my repository', 'write widget tests', 'improve test coverage', 'write a bloc_test', 'mock this dependency', 'add golden tests', 'how do I test X in Flutter', 'how should I test navigation', 'how do I test a freezed state', 'should I use mockito or mocktail', 'test my domain service'. Always use alongside flutter-architecture when writing tests for existing features."
---

# Flutter Testing

## What to Write (same rules as `test/README.md`)

| Kind | Where | Covers |
| --- | --- | --- |
| Architecture gate | `architecture_test.dart` | Layering rules (one test; keep it green) |
| DI smoke | `core/di/service_locator_test.dart` | Every registration resolves |
| Repository | `features/<f>/data/repositories/` | Success, and exceptions/malformed payloads becoming a typed `Failure` |
| Cubit | `features/<f>/presentation/bloc/` | The state transitions this cubit owns (success, failure, its own rules) |
| Screen | `features/<f>/presentation/screens/` | What each state renders, and user actions |
| Flow | `features/<f>/<f>_flow_test.dart` | The module's real registrations and route over a fake data source |
| Shared mechanism | `core/` | Tested once where it is defined (exception mapper, `LatestRequestWins`, `localizeFailure`) |

Do not write:

- tests of framework or config (theme brightness, "uses Material 3");
- tests that a widget or provider exists ("renders XView", "provides XCubit"): flow and behavior tests already fail if it is missing;
- forwarding tests ("service delegates to repository", "arguments forwarded");
- per-feature copies of shared mechanics.

Repository, cubit and screen tests are added only when real mapping, rules or interaction logic lands; for scaffolded/forwarding code the one flow test is enough (prefer it over per-layer tests).

Rules:

- **Never wait on the clock**: no `Future.delayed`/`sleep` in tests. Await the real future, inject the I/O seam, use `pump(duration)` or `fakeAsync` for timers.
- **Never mock pure domain logic**: use the real service and fake only I/O seams (data sources, platform channels).
- **No global-state leaks**: full runs group many test files into one shared isolate per shard. `await getIt.reset()` in tearDown, restore `AppLogger`/`debugPrint` overrides, no static mutable state.

## Running Tests

- While iterating: `./scripts/ftest.sh <paths>` (machine-wide queue, failures-only output).
- Before optimizing speed: `./scripts/ftest.sh --slowest[=N]` prints the slowest files/tests; per-file compile usually dominates, so fewer files beat faster tests.
- Once before finishing: `./scripts/fverify.sh --fix`.

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
        ├── auth_flow_test.dart
        ├── data/repositories/auth_repository_impl_test.dart
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

Cover the state transitions the cubit owns (success, failure, its own rules), not every public method.

### Cubits with domain services

Use the real service (it is pure logic) and fake only the repository or data source. Do not mock the service or `verify` calls on it; assert the resulting states.

## Repository Test

A repository test proves correct mapping and correct failure translation. Fake the data source; do not assert call forwarding.

```dart
test('maps API dto to domain user on success', () async {
  when(() => mockApi.login(
    email: any(named: 'email'),
    password: any(named: 'password'),
  )).thenAnswer((_) async => fakeUserDto);

  final result = await repo.login('user@ex.com', 'pass');

  result.fold(
    (_) => fail('Expected Right(User)'),
    (user) {
      expect(user.id, fakeUserDto.id);
      expect(user.email, fakeUserDto.email);
    },
  );
});

test('translates ApiException into a typed Failure', () async {
  when(() => mockApi.login(
    email: any(named: 'email'),
    password: any(named: 'password'),
  )).thenThrow(ApiException(message: 'Unauthorized'));

  final Either<Failure, User> result = await repo.login('user@ex.com', 'wrong');

  result.fold(
    (failure) => expect(failure, isA<FailureUnauthorized>()),
    (_) => fail('Expected Left(Failure)'),
  );
  // `Failure` has no user-facing message by design: assert the *category*,
  // not a display string. Diagnostic fields are for logs only.
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

  fakeCubit.pushState(const AuthState.failure(failure: Failure.networkError()));
  await tester.pump();

  // The screen localizes the typed failure at build time
  // (localizeFailure(AppLocalizations.of(context), failure)); assert the
  // localized text for the test locale, never a diagnostic message.
  expect(find.text(l10n.failureNetwork), findsOneWidget);
});
```

## Golden Test

Uses the plain `testWidgets` API with the built-in `matchesGoldenFile` matcher —
no extra package is installed (there is no `testGoldens` from
`flutter_test`; that API belongs to `alchemist`/`golden_toolkit`, which this
template does not depend on).

```dart
testWidgets('renders correctly', (tester) async {
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

## Architecture Boundary Tests

The layering rules from `flutter-architecture` as executable gates, enforced by the analyzer-based
checker in `test/support/architecture_checker.dart` (driven from `test/architecture_test.dart`,
fail-closed on resolution errors): inward dependencies, domain purity, cross-feature access via
public barrels only, `core` ↛ features, no cubit/bloc stored as a field, `getIt` resolved only from
the composition-root allowlist, registrations only in `service_locator.dart` and feature modules. The checker sees
statically-visible imports and declarations only — dynamic coupling, sizing, naming, and rebuild
scope remain review guidance, so a green run proves the enforced rules, not "all architecture".
When you add a rule to the skill, extend the checker **and** add a negative fixture (code that
must fail it); negative tests are part of the contract. The checker's regression fixtures live in
the FlutterForge template repository under `tools/checker_tests/`. A rule that is not tested is a suggestion.

## Feature-Flow Tests (real components over fake I/O)

Isolated tests (cubit, repository, widget-with-fake-cubit) fake their
direct dependencies. Feature-flow tests are the opposite by design: they
pump the real dependency chain (real DI composition, real router, real
repositories/services/cubits) and replace only the **data-source seam** with a
scripted fake. For one feature, pass the fake to its module on a fresh
locator (`registerXFeature(GetIt.asNewInstance(), remoteDataSource: fake)`) and
route with `xRoutes(getIt)` (what `fgen` generates); across features, use the
data-source override parameters of `setupServiceLocator()`. Never re-register
the graph by hand. Each test
gets a fresh router (`AppRouter.createRouter()`), disposes it in teardown, and
`await getIt.reset()`. Flow tests are in-process widget tests of navigation and
lifetimes — the naming does not claim device-level coverage. See
`test/README.md` for the full patterns.

## DI Smoke Test

Every registration (in `service_locator.dart` and the feature modules it calls) must resolve, and
cubit factories must return fresh instances. This catches missing registrations and unresolvable
constructor arguments at test time instead of at first navigation. The template ships it at
`test/core/di/service_locator_test.dart`; `fgen` adds each generated feature at its marker — add a
line yourself for hand-written registrations.

## Coverage Checklist

**Cubit/BLoC:**
- [ ] Happy path
- [ ] Error path
- [ ] Exact state order where it matters
- [ ] No assertions on another cubit's state

**Repository:**
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

## Anti-Patterns

| ❌ Wrong | ✅ Fix |
|---------|-------|
| Test private vars | Test public state + behavior |
| Real repositories in *isolated* cubit tests | Fake the repository via constructor; domain services stay real; flow tests use real components over fake I/O |
| `pumpAndSettle()` / `Future.delayed` to wait | Await the real future, or `pump(duration)` / `fakeAsync` |
| Mocking a domain service | Use the real one; fake only I/O seams |
| `getIt` or logger state left behind | `await getIt.reset()` and restore overrides in tearDown |
| `state.runtimeType` | Use `isA<StateType>()` or assert a concrete state value |
| Repository test only checks `isRight()` | Assert mapped value and failure translation |
| Skip error paths | Test failure translation once at the repository boundary; the mapper is tested in `core/errors/` |
| Use `mockito` by default | Prefer `mocktail` to avoid generation unless the project already standardizes on something else |
| Assert on another cubit's state in a cubit test | Test each cubit in isolation |
| Call `emit()` directly from the test body | Use `whenListen`, `MockCubit`, or a fake helper like `pushState()` |
| Test framework/config ("uses Material 3", theme brightness) | Delete — it tests Flutter, not the app |
| Test that a service forwards to its repository | Test only the rules the service owns (forwarding tests are forbidden) |
| Re-test a shared mechanism in every feature (request ordering, close safety, failure copy) | Test it once where it is defined (`LatestRequestWins`, `localizeFailure`) |

## See Also
- `mocktail-cheatsheet.md` — Reference snippets and complete examples
