---
name: "flutter-architecture"
description: "Use when creating new Flutter features, refactoring existing Flutter code, setting up project structure, implementing BLoC patterns, or when users mention Flutter best practices, clean architecture, dependency injection, or maintainability concerns while actively changing code. Also use when wiring new cubits, modifying service_locator.dart, or any time a change might affect multiple features. For deep audits, architecture reviews, or migration plans, use flutter-audit instead. Triggers include: \"create feature\", \"refactor this\", \"project structure\", \"BLoC pattern\", \"new cubit\", \"dependency injection\", \"clean architecture\", \"service locator\"."
---

# Flutter Architecture & Coding Standards

## Quick Reference

| Task | Standard |
|------|----------|
| Features | Layers: `presentation/ → domain/ ← data/` |
| State | **Cubit default**; use BLoC when explicit events or concurrency policies improve clarity |
| Listeners | **Always `MultiBlocListener`** — never nest |
| Files | Split when a file has **more than one reason to change**, not by line count |
| Models | `freezed` preferred; plain sealed immutable models/states are acceptable when exhaustive |
| Errors | `Either<Failure, T>` from repos — use **`fpdart`** (not dartz) |
| DI | `get_it` — registrations in `service_locator.dart`; resolve from app/route composition roots |
| Cubit deps | **Cubits never depend on other cubits** — use domain services |

---

## Core Structure

```
lib/
├── main.dart              # runApp() only — no wiring, no logic
├── app.dart               # MaterialApp.router + app-scoped providers (reads getIt only)
├── core/
│   ├── di/
│   │   └── service_locator.dart   # Single source of truth for all wiring
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

**Dependencies flow inward only:** `presentation → domain ← data`

`domain` owns business rules, entities, and repository contracts. `data` depends on `domain` to implement those contracts.

**Cross-feature rule:** Features should not import each other's internals. Shared infrastructure can live in `core/`; shared business capabilities should expose a small public API or move to a dedicated module/package instead of turning `core/` into a dumping ground.

## Modularity Beyond Folders

Start with feature folders inside one app package. Extract a feature into a Dart/Flutter package only when it has a stable public API, meaningful independent tests, or needs to be reused across apps.

Use these module boundaries:
- `core/` for app-wide infrastructure: DI, routing, networking, theming, logging, shared primitives
- feature modules for business capabilities and UI flows
- dedicated shared modules/packages for business logic reused by multiple features

When one module depends on another, depend on its public contract only. Never import another module's `presentation/` layer or private `data/` internals.

---

## The Two Wiring Rules

These two rules prevent the majority of "add a feature, break something else" regressions.

### Rule 1: One place for dependency registration — `service_locator.dart`

`service_locator.dart` is the single source of truth for registrations and lifetimes. Composition roots such as `app.dart`, route builders, and tests may **resolve** from `getIt`, but they should not manually assemble repository/service graphs.

```dart
// ✅ CORRECT — app-scoped provider resolved from DI
MultiBlocProvider(
  providers: [
    BlocProvider(create: (_) => getIt<ChatCubit>()..init()),
    BlocProvider(create: (_) => getIt<SettingsCubit>()),
  ],
  child: MaterialApp.router(...),
)

// ✅ CORRECT — route-scoped provider with runtime parameter
BlocProvider(
  create: (_) => getIt<ProfileCubit>(param1: userId)..load(),
  child: const ProfileScreen(),
)

// ❌ WRONG — manual construction bypasses DI and creates a second wiring layer
BlocProvider(
  create: (context) => MyCubit(
    repo: getIt<MyRepository>(),
    other: context.read<OtherCubit>(), // now wired in two places
  ),
)
```

App-scoped providers are for truly app-wide state. Screen and flow state should usually stay route-scoped so it resets naturally with navigation.

### Rule 2: Cubits never depend on other cubits

If two cubits need to coordinate, that coordination belongs in a **domain service**, not as a direct constructor dependency. This is the #1 source of fragility in LLM-assisted codebases — agents always find the shortest path, and the shortest path is usually a cubit dependency.

```dart
// ❌ WRONG — direct cubit-to-cubit dependency
class NotificationCubit extends Cubit<NotificationState> {
  final AuthCubit _authCubit; // fragile cross-cubit coupling
}

// ✅ CORRECT — both cubits depend on a shared domain service
class SessionService {
  void onUserLoggedIn(User user) { ... }
  void onUserLoggedOut() { ... }
}

class NotificationCubit extends Cubit<NotificationState> {
  final SessionService _session;
}

class AuthCubit extends Cubit<AuthState> {
  final SessionService _session;
}
```

> **Signal:** If you find yourself writing a comment like *"must be singleton so both X and Y use the same instance"* — that's a hidden coupling. Extract a domain service instead.

---

## State Pattern (`freezed` default; sealed states acceptable)

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

Use `freezed` by default for union ergonomics such as `when`, `map`, and `copyWith`. Plain Dart sealed states are also acceptable when they stay immutable and the UI handles them exhaustively.

---

## Cubit Sizing

Split by **user-visible state boundaries**, not by SRP micro-splits. Too many micro-cubits creates coordination complexity that is worse than the problem it solves.

```
// ❌ TOO GRANULAR — hidden coordination deps between 5+ cubits
chat_audio_cubit.dart
chat_message_cubit.dart
chat_streaming_cubit.dart
chat_title_cubit.dart
chat_tts_cubit.dart

// ✅ BETTER — split along visible UI concerns
chat_cubit.dart          # the conversation: messages, streaming, title
chat_media_cubit.dart    # media input: audio recording, image picking
```

Coordination logic that previously lived *between* micro-cubits moves *into* the cubit or into a domain service.

---

## Cubit vs BLoC

Use **Cubit** by default (90% of cases). Reach for full **BLoC** when explicit events make the workflow clearer or when you need concurrency control such as debounce, throttle, cancellation, restartable work, or droppable events.

```dart
// Use BLoC when explicit events and event transformers clarify the workflow
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc(this._repo) : super(const SearchState.initial()) {
    on<QueryChanged>(
      _onQueryChanged,
      transformer: (events, mapper) => events
          .debounceTime(const Duration(milliseconds: 300))
          .switchMap(mapper),
    );
  }
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
      listener: (context, state) { /* side effect */ },
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
      return Right(dto.toDomain());
    } on ApiException catch (e) {
      return Left(Failure(e.message));
    } catch (e) {
      return Left(const Failure('Unexpected error'));
    }
  }
}
```

---

## Singleton vs Factory in service_locator.dart

The choice must be explicit and consistent:

```dart
// Singleton — shared mutable state, single source of truth
getIt.registerLazySingleton<TtsService>(() => TtsService());

// Factory — fresh instance per screen/widget lifecycle
getIt.registerFactory<AuthCubit>(() => AuthCubit(getIt<IAuthRepository>()));
```

Prefer `registerFactory` or `registerFactoryParam` for cubits unless the state is intentionally app-wide and long-lived.

---

## Service → UI Communication (domain events, not cubit refs)

When a domain service needs to trigger UI state changes, the dependency arrow must point
**inward only** — the cubit knows about the service, never the reverse.

For event-like signals, the service can expose a stream and the cubit subscribes to it. For durable state, prefer a service or repository that exposes current state plus updates instead of a fire-and-forget event bus.

```dart
// ✅ CORRECT — service owns the stream, knows nothing about cubits
class AvatarAnimationService {
  final _controller = StreamController<AvatarAnimation>.broadcast();

  Stream<AvatarAnimation> get animations => _controller.stream;

  void triggerAnimation(AvatarAnimation animation) {
    _controller.add(animation);
  }

  void dispose() => _controller.close();
}

// Cubit subscribes — dependency flows inward
class AvatarCubit extends Cubit<AvatarState> {
  final AvatarAnimationService _animationService;
  late final StreamSubscription _sub;

  AvatarCubit(this._animationService) : super(const AvatarState.initial()) {
    _sub = _animationService.animations.listen(_onAnimation);
  }

  void _onAnimation(AvatarAnimation animation) {
    emit(state.copyWith(currentAnimation: animation));
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
```

```dart
// ❌ WRONG — service holds a cubit reference, dependency arrow reversed
class AvatarAnimationService {
  final AvatarCubit _cubit; // service depending on presentation layer
  void triggerAnimation(AvatarAnimation a) => _cubit.playAnimation(a);
}

// ❌ ALSO WRONG — interface trick doesn't fix the direction
class AvatarAnimationService {
  final AvatarAnimationController _controller; // still a cubit at runtime
}
```

> **Rule:** If registering a service requires passing `getIt<SomeCubit>()` as an argument,
> the dependency arrow is pointing the wrong way. Flip it with a stream or another domain-facing abstraction.

Use broadcast streams for ephemeral events such as animations, toasts, or one-off external triggers. If late subscribers must receive the latest value, expose current state separately or use a stateful stream abstraction at the domain layer.

---

## Anti-Patterns (Never Do)

| ❌ Wrong | ✅ Fix |
|---------|-------|
| Navigate in `build()` | Use `BlocListener` |
| Nested `BlocListener`s | Use `MultiBlocListener` |
| Services instantiated in widgets | Inject via `get_it` |
| Cross-feature imports into internals | Depend on a public contract, shared module/package, or `core/` infrastructure |
| Helper methods in widgets (`_buildX()`) | Extract only when the piece has a clear, standalone name and purpose; otherwise a small local helper is fine |
| Splitting a file just to reduce line count | Only extract when the piece has a clear, standalone name and purpose — a 600-line cubit handling one coherent feature is better than three 150-line cubits that depend on each other |
| `BlocBuilder` wrapping entire `Scaffold` | Wrap only the widget that needs state |
| Manual cubit construction in composition roots | Resolve via `getIt<MyCubit>()`; keep registrations in `service_locator.dart` |
| Cubit depending on another cubit | Extract shared logic to domain service |
| `context.read` after `await` | Capture reference before the `await` |
| `try/catch` returning `null` | Return `Either<Failure, T>` |
| Service holding a cubit ref (even via interface) | Publish domain events or durable domain state; cubit subscribes/reads |
| Everything shared goes in `core/` | Keep `core/` for infrastructure; extract stable shared business logic into a dedicated module/package |

---

## File Cohesion — When to Split

Split a file when it has **more than one reason to change** — not when it crosses an arbitrary line count. A long file with a single, coherent purpose is fine. A short file that owns two unrelated concerns is not.

Ask this before extracting: *"Does the piece I'm about to extract have a clear, standalone name and purpose?"* If you can't name it clearly, don't split it.

```
// ❌ WRONG — splitting to hit a line limit
// chat_cubit.dart is 550 lines but handles one feature coherently
// → mechanically split into chat_message_cubit.dart + chat_ui_cubit.dart
// → now they need to call each other, creating hidden coupling

// ✅ RIGHT — splitting along a real boundary
// chat_cubit.dart: conversation state (messages, streaming, title)
// chat_media_cubit.dart: media input (audio recording, image picking)
// These have independent lifecycles and different reasons to change
```

Signs a file genuinely needs splitting:
- You're scrolling past unrelated logic to find what you need
- Different team members need to edit it for unrelated reasons
- It imports from two different layers or domains

Signs a file does **not** need splitting:
- It's long but all lines serve the same state machine
- The only motivation is the line count
- Splitting would require the two new files to call each other

---

## Adding a New Feature — Checklist

1. **New feature folder or extension of existing?** — decide before writing any code
2. **Design the freezed state first** — what does the UI actually need?
3. **Run codegen after adding freezed classes** — `dart run build_runner build --delete-conflicting-outputs`; without it the `_$` part files don't exist and nothing compiles. Use `watch` during iterative work.
4. **Define the repository interface before the implementation**
5. **Does the new cubit need to react to another cubit?** — if yes, extract a domain service instead
6. **Register dependencies in `service_locator.dart`** — keep registration and lifetimes in one place
7. **Choose provider scope deliberately** — app-wide only for shared global state; otherwise prefer route/screen scope
8. **Add architecture tests** — repository mapping/failure tests, cubit/bloc state tests, and a DI smoke test for new registrations

## Minimum Architecture Tests

- repository tests for DTO-to-domain mapping and failure translation
- cubit/bloc tests for the important state transitions
- widget tests for critical screens with their providers/listeners wired
- a DI smoke test for new registrations or `registerFactoryParam` flows

---

## See Also
- `examples.md` — Cubit vs BLoC, DI setup, routing, and common anti-pattern corrections
