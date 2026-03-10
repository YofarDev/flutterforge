---
name: flutter-architecture
description: Use when creating new Flutter features, refactoring existing Flutter code, setting up project structure, implementing BLoC patterns, code reviews, or when users mention Flutter best practices, clean architecture, or maintainability concerns. Also use when adding LLM agent tools, wiring new cubits, modifying service_locator.dart, or any time a change might affect multiple features. Triggers include: "create feature", "refactor this", "project structure", "BLoC pattern", "code review", "best practices", "add tool", "new cubit", "dependency injection".
license: MIT
---

# Flutter Architecture & Coding Standards

## Quick Reference

| Task | Standard |
|------|----------|
| Features | Layered: `data/ → domain/ → presentation/` |
| State | **Cubit default**; BLoC only for debounce/throttle |
| Listeners | **Always `MultiBlocListener`** — never nest |
| Files | Widgets: 300, Services: 400, BLoCs: 300 lines |
| Models | `freezed` — immutable, sealed, exhaustive |
| Errors | `Either<Failure, T>` from repos — use **`fpdart`** (not dartz) |
| DI | `get_it` — **all wiring in `service_locator.dart` only** |
| Cubit deps | **Cubits never depend on other cubits** — use domain services |
| Agent tools | One file per tool, self-describing, registered in `tool_registry.dart` only |

---

## Core Structure

```
lib/
├── main.dart              # runApp() only — no wiring, no logic
├── app.dart               # MaterialApp.router + MultiBlocProvider (reads getIt only)
├── core/
│   ├── agent/             # LLM agent layer — first-class, not buried in services/
│   │   ├── agent.dart              # AgentInterface
│   │   ├── agent_result.dart       # sealed: text | tool_call | error
│   │   ├── tool_registry.dart      # ONLY file that changes when adding a tool
│   │   └── tools/                  # one file per tool
│   │       ├── weather_tool.dart
│   │       ├── search_tool.dart
│   │       └── ...
│   ├── audio/             # TTS, playback, amplitude — all audio in one place
│   ├── avatar/            # Animation service, avatar state
│   ├── di/
│   │   └── service_locator.dart   # Single source of truth for all wiring
│   ├── llm/               # LLM services, streaming, config
│   ├── router/
│   │   ├── app_router.dart
│   │   └── route_constants.dart
│   ├── models/            # Shared domain models only (freezed)
│   └── utils/
└── features/
    └── [feature]/
        ├── data/
        │   ├── datasources/
        │   └── repositories/      # implementations
        ├── domain/
        │   ├── models/            # feature-specific models (freezed)
        │   ├── repositories/      # interfaces only
        │   └── services/          # domain coordination logic
        └── presentation/
            ├── bloc/              # cubits + states
            ├── screens/
            └── widgets/
```

**Dependencies flow inward only:** `presentation → domain → data`

**Cross-feature rule:** Features never import from each other. All shared code lives in `core/`.

---

## The Two Wiring Rules (Most Important)

These two rules prevent the majority of "add a feature, break something else" regressions.

### Rule 1: One place for DI — service_locator.dart only

`main.dart` and `app.dart` must only **read** from `getIt`. They never construct cubits or services manually.

```dart
// ✅ CORRECT — app.dart
MultiBlocProvider(
  providers: [
    BlocProvider(create: (_) => getIt<ChatCubit>()..init()),
    BlocProvider(create: (_) => getIt<SettingsCubit>()),
  ],
  child: MaterialApp.router(...),
)

// ❌ WRONG — constructing manually bypasses DI and drifts from service_locator
BlocProvider(
  create: (context) => ChatMessageCubit(
    chatAudioCubit: getIt<ChatAudioCubit>(),       // now wired in two places
    chatStreamingCubit: context.read<ChatStreamingCubit>(),
  ),
)
```

### Rule 2: Cubits never depend on other cubits

If two cubits need to coordinate, that coordination belongs in a **domain service**, not as a direct constructor dependency between cubits. This is the #1 source of fragility in LLM-assisted codebases because agents will always find the shortest path — and the shortest path is usually adding a cubit dependency.

```dart
// ❌ WRONG — ChatTtsCubit depending on TalkingCubit
class ChatTtsCubit extends Cubit<ChatTtsState> {
  final TalkingCubit _talkingCubit; // cross-cubit dependency = fragile
}

// ✅ CORRECT — both cubits depend on a shared domain service
class TalkingCoordinatorService {
  void onTtsStarted() { ... }
  void onTtsStopped() { ... }
}

class ChatTtsCubit extends Cubit<ChatTtsState> {
  final TalkingCoordinatorService _coordinator;
}

class TalkingCubit extends Cubit<TalkingState> {
  final TalkingCoordinatorService _coordinator;
}
```

---

## State Pattern (freezed — always)

```dart
@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = _Initial;
  const factory AuthState.loading() = _Loading;
  const factory AuthState.authenticated(User user) = _Authenticated;
  const factory AuthState.failure(String message) = _Failure;
}

// Compiler enforces exhaustive handling
state.when(
  initial: () => const LoginForm(),
  loading: () => const CircularProgressIndicator(),
  authenticated: (user) => HomeScreen(user: user),
  failure: (msg) => ErrorBanner(message: msg),
);
```

---

## Cubit Sizing — Split by User-Visible State, Not SRP Micro-Splits

Too many micro-cubits creates coordination complexity that is worse than the problem it solves. Split when a cubit handles two genuinely independent UI concerns, not just because a file is long.

```
// ❌ TOO GRANULAR — 7 cubits for one feature creates hidden coordination deps
chat_audio_cubit.dart
chat_list_cubit.dart
chat_message_cubit.dart
chat_streaming_cubit.dart
chat_title_cubit.dart
chat_tts_cubit.dart
chats_cubit.dart

// ✅ BETTER — split along visible UI state boundaries
chat_cubit.dart          # messages, streaming, title — the conversation
chat_media_cubit.dart    # audio recording, image picking — media input
```

Coordination logic that previously lived *between* micro-cubits moves *into* the cubit or into a domain service.

---

## Agent Tool Pattern

Adding a new capability should require touching **exactly one file** beyond the new tool itself.

```dart
// core/agent/tools/weather_tool.dart — self-contained
class WeatherTool implements AgentTool {
  @override
  String get name => 'getCurrentWeather';

  @override
  String get description => 'Get current weather for a location';

  @override
  Map<String, dynamic> get schema => {
    'type': 'object',
    'properties': {
      'location': {'type': 'string', 'description': 'City name'},
    },
    'required': ['location'],
  };

  @override
  Future<AgentResult> execute(Map<String, dynamic> args) async {
    final location = args['location'] as String;
    // implementation
  }
}

// core/agent/tool_registry.dart — THE ONLY FILE THAT CHANGES when adding a tool
class ToolRegistry {
  static final List<AgentTool> tools = [
    WeatherTool(),
    NewsTool(),
    SearchTool(),
    // Add new tool here — nothing else needs to change
  ];
}
```

---

## Listener Pattern

```dart
// ✅ Always flat — never nest BlocListeners
MultiBlocListener(
  listeners: [
    BlocListener<AuthCubit, AuthState>(
      listener: (context, state) => state.whenOrNull(
        authenticated: (_) => context.push('/home'),
        failure: (msg) => showErrorSnackBar(context, msg),
      ),
    ),
    BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (prev, curr) => prev.theme != curr.theme,
      listener: (context, state) { /* theme change side effect */ },
    ),
  ],
  child: Scaffold(...),
)
```

---

## Repository Pattern

```dart
// domain/repositories/auth_repository.dart — interface only
abstract class IAuthRepository {
  Future<Either<Failure, User>> login(String email, String password);
}

// data/repositories/auth_repository_impl.dart — implementation
class AuthRepositoryImpl implements IAuthRepository {
  final AuthApi _api;

  @override
  Future<Either<Failure, User>> login(String email, String password) async {
    try {
      final dto = await _api.login(email: email, password: password);
      return Right(User.fromDto(dto));
    } on ApiException catch (e) {
      return Left(Failure(e.message));
    } catch (e) {
      return Left(const Failure('Unexpected error'));
    }
  }
}
```

---

## Anti-Patterns (Never Do)

| ❌ Wrong | ✅ Fix |
|---------|-------|
| Navigate in `build()` | Use `BlocListener` |
| Nested `BlocListener`s | Use `MultiBlocListener` |
| Services instantiated in widgets | Inject via `get_it` |
| Cross-feature imports | Route through `core/` only |
| Helper methods in widgets (`_buildX()`) | Extract to separate widget classes |
| `BlocBuilder` wrapping entire `Scaffold` | Wrap only the widget that needs state |
| Manual cubit construction in `app.dart` | Always use `getIt<MyCubit>()` |
| Cubit depending on another cubit | Extract shared logic to domain service |
| `context.read` after `await` | Capture reference before the `await` |
| `try/catch` returning `null` | Return `Either<Failure, T>` |
| 8 cubits for one feature | Split by UI concern, move coordination to services |
| New agent tool scattered across files | One tool file + one line in `tool_registry.dart` |

---

## Singleton vs Factory Decision

In `service_locator.dart`, the choice must be explicit and documented:

```dart
// Singleton — shared mutable state, single source of truth
getIt.registerLazySingleton<TtsService>(() => TtsService());

// Factory — fresh instance per screen/widget lifecycle
getIt.registerFactory<AuthCubit>(() => AuthCubit(getIt<IAuthRepository>()));

// ⚠️ If you add a comment like "must be singleton so both X and Y use the same instance"
// — that is a signal that X and Y have a hidden coupling.
// Consider extracting the shared concern to a domain service instead.
```

---

## Adding a New Feature — Checklist

Before writing any code, answer these:

1. **Does this need a new feature folder, or does it extend an existing one?**
2. **What state does the UI need?** — Design the freezed state first
3. **What repository interface does the cubit call?** — Define the interface before the implementation
4. **Does the new cubit need to react to another cubit's state?** — If yes, extract a domain service instead of adding a cubit dependency
5. **If adding an agent tool:** create the tool file, add one line to `tool_registry.dart`, done

---

## See Also
- `examples.md` — Cubit vs BLoC, DI setup, routing examples
- `anti-patterns.md` — Common mistakes with before/after fixes
- `RED_TEST_SCENARIOS.md` — Test scenarios to validate architecture decisions
