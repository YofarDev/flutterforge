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
| State shape | **Union states** for load-lifecycle screens; **flat `copyWith` state** for persistent interactive state |
| Listeners | One listener → a single `BlocListener` is fine; multiple → flatten with `MultiBlocListener`, never nest |
| Files | Split when a file has **more than one reason to change**, not by line count |
| Models | `freezed` preferred; plain sealed immutable models/states are acceptable when exhaustive |
| Errors | `Either<Failure, T>` from repos — use **`fpdart`** (not dartz); classify unknown exceptions via `mapExceptionToFailure` (`core/errors/exception_mapper.dart`) |
| DI | `get_it` — registrations in `service_locator.dart`; resolve from app/route composition roots |
| Cubit deps | **Cubits never depend on other cubits** — use domain services |

---

## Core Structure

```
lib/
├── main.dart              # bootstrap (setupServiceLocator) + runApp — no other wiring
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

**Composition root:** `main.dart` performs bootstrap (`await setupServiceLocator()`) and then `runApp(...)` — it is not "runApp only". Dependency registration has exactly one owner: `service_locator.dart` (main.dart may import it solely to call the bootstrap). Resolving from `getIt` is additionally allowed in `app.dart`, `app_router.dart`, and `service_locator.dart` itself — that allowlist is exactly what `test/architecture_test.dart` enforces.

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

Pick the idiom by screen behavior — don't mix idioms within one screen:

- **Union states** for **load-lifecycle screens** (fetch, submit, connect): one variant active at a time, exhaustive `when()` in the UI, and failure is a visible state — never a swallowed branch.
- **Flat `copyWith` states** for **persistent interactive state** (a counter, a form, filter selections): many independent fields evolving over time.

The template demonstrates both deliberately: `home` uses the union idiom, `counter` the flat one.

```dart
@freezed
sealed class AuthState with _$AuthState {
  const factory AuthState.initial() = _Initial;
  const factory AuthState.loading() = _Loading;
  const factory AuthState.authenticated(User user) = _Authenticated;
  const factory AuthState.failure({required Failure failure}) = _Failure;
}

// Compiler enforces exhaustive handling. The failure state carries the typed
// Failure; the widget derives localized text with localizeFailure().
state.when(
  initial: () => const LoginForm(),
  loading: () => const CircularProgressIndicator(),
  authenticated: (user) => HomeScreen(user: user),
  failure: (failure) =>
      ErrorBanner(message: localizeFailure(AppLocalizations.of(context), failure)),
);
```

Use `freezed` by default for union ergonomics such as `when`, `map`, and `copyWith`. Plain Dart sealed states are also acceptable when they stay immutable and the UI handles them exhaustively. Either way, a screen that loads data must expose a failure state — swallowing an error branch (or falling back silently without logging) is not an option.

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
// ✅ A single BlocListener is fine; when you have several, flatten them with
//    MultiBlocListener — never nest BlocListeners
MultiBlocListener(
  listeners: [
    BlocListener<AuthCubit, AuthState>(
      listener: (context, state) => state.whenOrNull(
        authenticated: (_) => context.push('/home'),
        failure: (failure) => showErrorSnackBar(
          context,
          // Localize the typed failure; never show diagnostic messages.
          localizeFailure(AppLocalizations.of(context), failure),
        ),
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
  AuthRepositoryImpl(this._api);

  final AuthApi _api;

  @override
  Future<Either<Failure, User>> login(String email, String password) async {
    try {
      final AuthDto dto = await _api.login(email: email, password: password);
      return Right<Failure, User>(dto.toDomain());
    } on ApiException catch (e) {
      // KNOWN errors are classified deliberately, first: this repository
      // knows its API's error taxonomy, so each variant maps to a specific
      // Failure here — not in the generic mapper.
      return Left<Failure, User>(_mapApiException(e));
    } catch (e, st) {
      // Catch-all fallback: timeouts, malformed DTOs (FormatException,
      // TypeError from toDomain()), anything this repository does not
      // specifically know. Nothing escapes the Either<Failure, T> contract.
      // `mapExceptionToFailure` classifies TimeoutException as
      // Failure.networkError and everything else as Failure.unexpected, and
      // logs error + stack trace exactly once at this boundary.
      return Left<Failure, User>(
        mapExceptionToFailure(e, stackTrace: st, tag: 'AuthRepository'),
      );
    }
  }

  Failure _mapApiException(ApiException e) => switch (e) {
    ApiNotFoundException() => const Failure.unauthorized(),
    ApiAuthException() => const Failure.unauthorized(),
    _ => Failure.serverError(message: e.message), // diagnostic; logged only
  };
}
```

**The repository error boundary is exhaustive by construction.** The known-type `catch` maps only the errors the repository deliberately classifies; the bare `catch` guarantees every other exception (timeout, malformed DTO, unexpected) becomes a typed `Failure` instead of escaping. Example tests:

```dart
// test/features/auth/data/repositories/auth_repository_impl_test.dart
group('AuthRepositoryImpl.login error mapping', () {
  test('a known API error maps to its specific failure variant', () async {
    when(() => api.login(
      email: any(named: 'email'),
      password: any(named: 'password'),
    )).thenThrow(const ApiAuthException(message: 'bad credentials'));

    final Either<Failure, User> result =
        await repository.login('a@b.c', 'wrong');

    expect(
      result.fold((l) => l, (_) => fail('expected Left')),
      isA<FailureUnauthorized>(),
    );
  });

  test('a timeout maps to Failure.networkError via the generic mapper', () async {
    when(() => api.login(
      email: any(named: 'email'),
      password: any(named: 'password'),
    )).thenThrow(TimeoutException('timeout', const Duration(seconds: 5)));

    final Either<Failure, User> result =
        await repository.login('a@b.c', 'pw');

    expect(
      result.fold((l) => l, (_) => fail('expected Left')),
      isA<FailureNetwork>(),
    );
  });

  test('a malformed DTO maps to Failure.unexpected instead of escaping', () async {
    when(() => api.login(
      email: any(named: 'email'),
      password: any(named: 'password'),
    )).thenAnswer(
      // A syntactically valid response whose toDomain() conversion throws
      // (e.g. DateTime.parse on 'not-a-date').
      (_) async => const AuthDto(name: 'Ada', createdAt: 'not-a-date'),
    );

    final Either<Failure, User> result =
        await repository.login('a@b.c', 'pw');

    expect(
      result.fold((l) => l, (_) => fail('expected Left')),
      isA<FailureUnexpected>(),
    );
  });
});
```

**Typed failures:** `Failure` is a pure immutable model (`serverError` with a diagnostic `message`, `networkError`, `unauthorized`, `unexpected`). Diagnostic messages are for logs/telemetry only — never displayed. Presentation text is derived at build time via `localizeFailure(AppLocalizations.of(context), failure)` in `core/l10n/failure_localization.dart`, which is exhaustive over the variants; the app follows the device locale (there is no locale-preference state).

---

## Async Lifecycle in Cubits (ordering, disposal, reset, streams)

Reads use **latest-request-wins**: each accepted request captures a monotonically increasing request id before awaiting; after the await, the cubit re-checks the id (and `isClosed`) before emitting success *or* failure, so a slow older response can never overwrite a newer one. Note the limits:

- **Ignoring a stale result is not cancelling the request.** The underlying network call still runs to completion; only its emission is discarded. True cancellation is a separate decision (e.g. a BLoC with `switchMap`, or a cancellable data-source API).
- **Read ordering and write ordering are different decisions.** The counter deliberately has *no* ordered persistent-write queue: an increment that fails persistence keeps the optimistic in-memory value and falls back per its documented settings-failure policy. If your feature needs last-writer-wins on disk or serialized writes, say so explicitly in the cubit's doc comment and test it.
- **Reset invalidation** uses a generation counter: bumping it on reset makes any in-flight result from before the reset drop its emission, so a reset cannot be undone by a late response.
- **Disposal:** every emit after an `await` must be guarded by `isClosed` (emitting on a closed cubit throws a `StateError`). Cancel owned `StreamSubscription`s in `close()` and **await** the cancellation — it is asynchronous. Close owned `StreamController`s and `GoRouter` instances (tests dispose the router in teardown).

---

## Scaffolding Proportional to Complexity

`fgen` generates a **lean** feature by default: freezed domain model (no JSON serialization), repository interface, placeholder data source (the external-I/O seam — it returns the domain model directly and is not a transport schema), repository implementation with typed failures, a cubit depending on the repository interface, union state, one screen, and tests. Add optional layers only when their criteria hold:

- **`--with-dto`**: add a transport DTO when a *real* external representation exists (API payload, cache schema) that differs from the domain model.
- **`--with-service`**: add a domain service when two or more cubits share rules, or the cubit accumulates coordination logic. The placeholder must grow real rules or be **removed** — a forwarding service is not mandatory architecture (compare `CounterService`, which owns real step/bounds behavior; `HomeCubit` correctly talks to `IHomeRepository` directly).

After generation, register dependencies in `service_locator.dart`, add the route in `app_router.dart`, update the DI smoke test, then run `fverify`. A scaffold passing its unit tests is **not** a routed feature — compiling proves neither the route nor the DI registration; only wiring plus the flow tests do.

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
// ✅ CORRECT — service owns the stream, knows nothing about cubits.
//
// OWNERSHIP: the service's OWNER disposes the service — the composition
// root that registered it (service_locator teardown / the owning object's
// dispose), never a consumer cubit. The service is shared: a cubit closing
// it would cut the stream for every other subscriber.
class AvatarAnimationService {
  final _controller = StreamController<AvatarAnimation>.broadcast();

  Stream<AvatarAnimation> get animations => _controller.stream;

  void triggerAnimation(AvatarAnimation animation) {
    _controller.add(animation);
  }

  // Asynchronous disposal returns Future<void> so the owner can await it.
  Future<void> dispose() => _controller.close();
}

// Cubit subscribes — dependency flows inward. The cubit owns ONLY its
// subscription, never the shared service.
class AvatarCubit extends Cubit<AvatarState> {
  final AvatarAnimationService _animationService;
  late final StreamSubscription<AvatarAnimation> _sub;

  AvatarCubit(this._animationService) : super(const AvatarState.initial()) {
    _sub = _animationService.animations.listen(_onAnimation);
  }

  void _onAnimation(AvatarAnimation animation) {
    emit(state.copyWith(currentAnimation: animation));
  }

  @override
  Future<void> close() async {
    // Cancel only what this cubit owns: its subscription. Cancellation is
    // asynchronous — await it before finishing teardown so no event fires
    // into a closed cubit. Do NOT dispose the shared service here.
    await _sub.cancel();
    await super.close();
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
| Nested `BlocListener`s | Flatten several listeners with `MultiBlocListener` (a single `BlocListener` is fine) |
| Services instantiated in widgets | Inject via `get_it` |
| Cross-feature imports into internals | Depend on a public contract, shared module/package, or `core/` infrastructure |
| Helper methods in widgets (`_buildX()`) | Extract only when the piece has a clear, standalone name and purpose; otherwise a small local helper is fine |
| Splitting a file just to reduce line count | Only extract when the piece has a clear, standalone name and purpose — a 600-line cubit handling one coherent feature is better than three 150-line cubits that depend on each other |
| `BlocBuilder` wrapping entire `Scaffold` | Wrap only the widget that needs state |
| Manual cubit construction in composition roots | Resolve via `getIt<MyCubit>()`; keep registrations in `service_locator.dart` |
| Cubit depending on another cubit | Extract shared logic to domain service |
| `context.read` after `await` | Capture reference before the `await` |
| `try/catch` returning `null` | Return `Either<Failure, T>` |
| Catch-all `Failure.serverError(message: e.toString())` | Classify known exceptions to specific variants and log once at the boundary via `mapExceptionToFailure`; never surface `e.toString()` in the UI |
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
7. **Choose provider scope deliberately** — app-wide only for shared global state; otherwise prefer route/screen scope (the route builder provides the cubit; the screen is a pure consumer)
8. **Add architecture tests** — repository mapping/failure tests, cubit/bloc state tests, and a DI smoke test for new registrations
9. **Run `fverify`** (format check + `flutter analyze` + `flutter test`) before finishing — the architecture checker enforces the rules listed below

## Executable Rules vs Review Guidance

`test/architecture_test.dart` uses an analyzer-based checker (`test/support/architecture_checker.dart`) that **fails closed** on resolution errors and enforces, on statically-visible imports and declarations:

- dependencies flow inward (`presentation → domain ← data`)
- domain purity (domain imports nothing from data/presentation)
- cross-feature access via a feature's public barrel only (barrels re-export nothing internal)
- `core/` never imports feature internals
- no cubit/bloc stored as a field of another cubit/bloc/service (type-based)
- `getIt` resolved only from the allowlist (`app.dart`, `service_locator.dart`, `app_router.dart`; `main.dart` may additionally *import* `service_locator.dart` for bootstrap)
- registrations (`register*`) appear only in `service_locator.dart`

**Scope limits (honest):** the checker sees only statically resolvable imports and declarations — dynamic coupling (e.g. a service receiving a cubit through an interface), naming quality, cubit sizing, listener nesting, rebuild scope, and singleton-vs-factory judgment are **review guidance**, not executable rules. A green suite proves the enforced rules only; it is not proof that "all architecture rules" hold. Negative fixtures (code that *should* fail the checker) are part of the contract — when you extend the checker with a rule from this skill, add the negative test alongside the positive one.

## Minimum Architecture Tests

- repository tests for DTO-to-domain mapping and failure translation
- cubit/bloc tests for the important state transitions — including the failure path
- widget tests for critical screens with their providers/listeners wired
- a DI smoke test for new registrations or `registerFactoryParam` flows
- architecture boundary tests (`test/architecture_test.dart`) stay green — extend them when you add a rule from this skill

---

## See Also
- `examples.md` — Cubit vs BLoC, DI setup, routing, and common anti-pattern corrections
