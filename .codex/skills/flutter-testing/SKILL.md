---
name: "flutter-testing"
description: "Use when writing tests for Flutter projects, including unit tests, widget tests, bloc tests, or when the user asks how to test specific components (cubits, repositories, screens, domain services, agent tools). Triggers include: 'write tests for this', 'add unit tests', 'test my cubit', 'test my repository', 'write widget tests', 'improve test coverage', 'write a bloc_test', 'mock this dependency', 'add golden tests', 'how do I test X in Flutter', 'how should I test navigation', 'how do I test a freezed state', 'should I use mockito or mocktail', 'test my agent tool', 'test my domain service'. Always use alongside flutter-architecture when writing tests for existing features."
---

# Flutter Testing

## Quick Reference

| Test Type | Tool | What to Test |
|-----------|------|--------------|
| Cubits/BLoCs | `bloc_test` | Every method, all states, error paths |
| Repositories | `mocktail` | API calls, mapping, errors |
| Domain services | `flutter_test` + `mocktail` | Coordination logic, no cubit deps |
| Agent tools | `flutter_test` + `mocktail` | Schema, execute(), error paths |
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
test/
├── core/
│   ├── agent/
│   │   └── tools/
│   │       ├── weather_tool_test.dart   # one test file per tool
│   │       └── search_tool_test.dart
│   └── services/
│       └── talking_coordinator_service_test.dart
└── features/
    └── auth/
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

### Testing that a cubit uses a domain service (not another cubit)

When a cubit has been refactored to use a domain service instead of a cubit dependency,
verify delegation — not the coordinator's internal behavior (that belongs in the service's own test).

```dart
class MockTalkingCoordinatorService extends Mock
    implements TalkingCoordinatorService {}

blocTest<ChatTtsCubit, ChatTtsState>(
  'notifies coordinator when TTS starts',
  build: () {
    mockCoordinator = MockTalkingCoordinatorService();
    when(() => mockCoordinator.onTtsStarted()).thenReturn(null);
    return ChatTtsCubit(
      ttsQueueManager: mockTtsQueueManager,
      coordinator: mockCoordinator,
    );
  },
  act: (c) => c.startTts('Hello'),
  verify: (_) {
    verify(() => mockCoordinator.onTtsStarted()).called(1);
    // Do NOT assert on TalkingCubit state here — that belongs in coordinator tests
  },
);
```

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

## Domain Service Test

Domain services hold coordination logic extracted from cubits. Test them in
pure isolation — no cubits, no widgets, no `blocTest`.

```dart
// test/core/services/talking_coordinator_service_test.dart
void main() {
  late TalkingCoordinatorService service;

  setUp(() => service = TalkingCoordinatorService());

  group('TalkingCoordinatorService', () {
    test('marks talking as active when TTS starts', () {
      service.onTtsStarted();
      expect(service.isTalking, true);
    });

    test('marks talking as inactive when TTS stops', () {
      service.onTtsStarted();
      service.onTtsStopped();
      expect(service.isTalking, false);
    });

    test('onTtsStopped is idempotent when not talking', () {
      // Should not throw when called without a prior onTtsStarted
      expect(() => service.onTtsStopped(), returnsNormally);
    });
  });
}
```

## Agent Tool Test

Every `AgentTool` implementation gets its own test file. Three things to always test:
schema validity, happy path execution, and error handling.

```dart
// test/core/agent/tools/weather_tool_test.dart
class MockWeatherService extends Mock implements WeatherService {}

void main() {
  late WeatherTool tool;
  late MockWeatherService mockService;

  setUp(() {
    mockService = MockWeatherService();
    tool = WeatherTool(service: mockService);
  });

  group('WeatherTool', () {
    // 1. Schema — required fields are declared
    test('schema declares location as required', () {
      final required = tool.schema['required'] as List;
      expect(required, contains('location'));
    });

    // 2. Happy path — correct args produce correct result
    test('execute returns weather data for valid location', () async {
      when(() => mockService.getCurrent('Paris'))
          .thenAnswer((_) async => fakeWeatherData);

      final result = await tool.execute({'location': 'Paris'});

      expect(result, isA<AgentResultText>());
      verify(() => mockService.getCurrent('Paris')).called(1);
    });

    // 3. Error path — service failure returns AgentResultError, never throws
    test('execute returns error result when service fails', () async {
      when(() => mockService.getCurrent(any()))
          .thenThrow(Exception('API unavailable'));

      final result = await tool.execute({'location': 'Paris'});

      expect(result, isA<AgentResultError>());
    });
  });
}
```

**Rule:** Agent tool `execute()` must never throw — always return `AgentResultError`.
If a tool can throw, that's a bug; write the error-path test first to catch it.

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
- [ ] Delegation to domain service verified (if applicable)
- [ ] No assertions on other cubits' state

**Domain service:**
- [ ] Core coordination logic
- [ ] Edge cases (idempotent calls, empty input)
- [ ] No cubit imports in test file

**Agent tool:**
- [ ] Schema has required fields
- [ ] Happy path `execute()` returns correct `AgentResult` type
- [ ] Error path returns `AgentResultError` — never throws

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
| Skip error paths | Every `try/catch` needs a test |
| Use `mockito` | Use `mocktail` (no generation) |
| Assert on another cubit's state in a cubit test | Test each cubit in isolation |
| Agent tool `execute()` that throws | Return `AgentResultError` instead |

## See Also
- `mocktail-cheatsheet.md` — Full mocktail API reference, complete examples
