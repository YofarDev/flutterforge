---
name: flutter-architecture
description: Use when creating new Flutter features, refactoring existing Flutter code, setting up project structure, implementing BLoC patterns, code reviews, or when users mention Flutter best practices, clean architecture, or maintainability concerns. Also use when wiring new cubits, modifying service_locator.dart, or any time a change might affect multiple features. Triggers include: "create feature", "refactor this", "project structure", "BLoC pattern", "code review", "best practices", "new cubit", "dependency injection".
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

---

## Core Structure

```
lib/
├── main.dart              # runApp() only — no wiring, no logic
├── app.dart               # MaterialApp.router + MultiBlocProvider (reads getIt only)
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

**Dependencies flow inward only:** `presentation → domain → data`

**Cross-feature rule:** Features never import from each other. All shared code lives in `core/`.

---

## The Two Wiring Rules

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

// ❌ WRONG — constructing manually bypasses DI and creates a second wiring layer
BlocProvider(
  create: (context) => MyCubit(
    repo: getIt<MyRepository>(),
    other: context.read<OtherCubit>(), // now wired in two places
  ),
)
```

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

Use **Cubit** by default (90% of cases). Only use full BLoC when you need event transformers.

```dart
// Use BLoC only when you need debounce / switchMap / throttle
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

## Singleton vs Factory in service_locator.dart

The choice must be explicit and consistent:

```dart
// Singleton — shared mutable state, single source of truth
getIt.registerLazySingleton<TtsService>(() => TtsService());

// Factory — fresh instance per screen/widget lifecycle
getIt.registerFactory<AuthCubit>(() => AuthCubit(getIt<IAuthRepository>()));
```

---

## Service → UI Communication (streams, not cubit refs)

When a domain service needs to trigger UI state changes, the dependency arrow must point
**inward only** — the cubit knows about the service, never the reverse.

The pattern: the service exposes a **broadcast stream**, the cubit subscribes to it.

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
> the dependency arrow is pointing the wrong way. Flip it with a stream.

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
| Service holding a cubit ref (even via interface) | Expose a stream; cubit subscribes |

---

## Adding a New Feature — Checklist

1. **New feature folder or extension of existing?** — decide before writing any code
2. **Design the freezed state first** — what does the UI actually need?
3. **Define the repository interface before the implementation**
4. **Does the new cubit need to react to another cubit?** — if yes, extract a domain service instead
5. **Register in `service_locator.dart` only** — never wire in `app.dart` or screens

---

## See Also
- `examples.md` — Cubit vs BLoC, DI setup, routing examples
- `anti-patterns.md` — Common mistakes with before/after fixes
