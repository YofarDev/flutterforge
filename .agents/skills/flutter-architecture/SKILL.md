---
name: "flutter-architecture"
description: "Use when creating new Flutter features, refactoring existing Flutter code, setting up project structure, implementing BLoC patterns, or when users mention Flutter best practices, clean architecture, dependency injection, or maintainability concerns while actively changing code. Also use when wiring new cubits, modifying service_locator.dart, or any time a change might affect multiple features. For deep audits, architecture reviews, or migration plans, use flutter-audit instead. Triggers include: \"create feature\", \"refactor this\", \"project structure\", \"BLoC pattern\", \"new cubit\", \"dependency injection\", \"clean architecture\", \"service locator\"."
---

# Flutter Architecture & Coding Standards

Core rules. Details, long examples and rationale live in
[reference.md](reference.md) (read the section you need) and
[examples.md](examples.md) (routing, before/after corrections).

## Quick Reference

| Task | Standard |
|------|----------|
| Layers | `presentation → domain ← data`; dependencies point inward only |
| New feature | `./scripts/fgen.sh name [--with-service] [--with-dto]` — scaffolds, wires, tests |
| Cross-feature | Import only the other feature's barrel `lib/features/<f>/<f>.dart` |
| DI | `get_it`; app-wide in `service_locator.dart`, per feature in `<f>_module.dart` |
| State | Cubit by default; BLoC when events/concurrency transformers clarify the flow |
| State shape | Union state for load lifecycles; flat `copyWith` state for interactive state |
| Models | `freezed` (v3: `sealed`/`abstract` classes) |
| Errors | Repos return `Either<Failure, T>` (fpdart); unknown exceptions → `mapExceptionToFailure` |
| Reads in cubits | `LatestRequestWins` mixin (`core/bloc/`) — never hand-rolled request ids |
| Cubit deps | Cubits never depend on cubits — share a domain service |
| Gate | `./scripts/fverify.sh --fix` before finishing |

## Structure

```
lib/
├── main.dart              # await setupServiceLocator(); runApp(...) — nothing else
├── app.dart               # MaterialApp.router + app-scoped providers
├── core/
│   ├── bloc/              # LatestRequestWins
│   ├── di/service_locator.dart   # app-wide registrations + one call per feature module
│   ├── router/            # app_router.dart (spreads module routes), route_constants.dart
│   ├── errors/ l10n/ models/ theme/ utils/
└── features/<f>/
    ├── <f>.dart           # public barrel: domain models/contracts/services only
    ├── <f>_module.dart    # registerXFeature(GetIt, {overrides}) + xRoutes(GetIt)
    ├── data/              # datasources/, models/ (DTOs), repositories/ (impls)
    ├── domain/            # models/, repositories/ (interfaces), services/
    └── presentation/      # bloc/, screens/, widgets/
```

`core/` is infrastructure, not a dumping ground: shared *business* logic gets
its own feature/module with a barrel. Extract a package only when it has a
stable API or is reused across apps.

## Wiring

- **Registration** happens only in `service_locator.dart` (app-wide
  infrastructure) and feature modules. A module receives the `GetIt`, registers
  its data source (with an optional override for tests), repository, services
  and cubits, and returns its routes. `fgen` inserts new modules at the
  `// fgen:` markers; keep those markers.
- **Resolution** (`getIt<T>()`) happens only in composition roots: `app.dart`,
  `app_router.dart`, `service_locator.dart`, feature modules (route builders).
  Everything else gets dependencies through constructors.
- **Lifetimes:** `registerLazySingleton` for data sources, repositories and
  shared services; `registerFactory`/`registerFactoryParam` for cubits.
- **Provider scope:** the route builder provides a screen's cubit
  (`BlocProvider(create: (_) => getIt<XCubit>()..load())`); screens only
  consume. App-wide providers only for truly app-wide state.
- **Cubits never depend on cubits** (fields, constructor args, or a service
  holding a cubit, even via an interface). Coordination goes in a domain
  service both depend on; service → UI signals go through a stream the cubit
  subscribes to. See reference.md → Service → UI Communication.

```dart
// ❌ second wiring layer, cubit-to-cubit coupling
BlocProvider(create: (context) => MyCubit(repo: getIt<MyRepo>(), other: context.read<OtherCubit>()))
// ✅ resolved from DI, coordination via a domain service
BlocProvider(create: (_) => getIt<MyCubit>()..load())
```

## State

```dart
@freezed
sealed class ProfileState with _$ProfileState {
  const factory ProfileState.initial() = _Initial;
  const factory ProfileState.loading() = _Loading;
  const factory ProfileState.loaded(Profile profile) = _Loaded;
  const factory ProfileState.failure({required Failure failure}) = _Failure;
}
// UI: exhaustive state.when(...); failure text = localizeFailure(l10n, failure)
```

- A screen that loads data **must** expose a failure state — never swallow an
  error branch. The state carries the typed `Failure`, never a message string;
  diagnostic text is for logs only.
- Don't mix idioms in one screen. Split cubits along user-visible state
  boundaries, not SRP micro-splits (reference.md → Cubit Sizing).
- Listeners: one `BlocListener` is fine, several → `MultiBlocListener`, never
  nested. Navigate from listeners, never from `build()`. `BlocBuilder` wraps
  only what needs the state.

## Repositories and errors

```dart
Future<Either<Failure, User>> login(String email, String password) async {
  try {
    final AuthDto dto = await _api.login(email: email, password: password);
    return Right<Failure, User>(dto.toDomain()); // conversion inside the try
  } on ApiException catch (e) {
    return Left<Failure, User>(_mapApiException(e)); // known errors first
  } catch (e, st) {
    return Left<Failure, User>(mapExceptionToFailure(e, stackTrace: st, tag: 'AuthRepository'));
  }
}
```

Nothing escapes the `Either` contract; `mapExceptionToFailure` logs once at
this boundary. Full example and its tests: reference.md → Repository Pattern.

## Async in cubits

- Reads: `with LatestRequestWins<S>` and `runLatest(request, onStart: ...,
  onResult: ...)` — stale results and post-close results are dropped (not
  cancelled). Tested once in core; don't re-test it per cubit.
- Every `emit` after an `await` is guarded by `isClosed` (the mixin does it
  for reads). Writes and resets need their own explicit policy (see
  `CounterCubit` and reference.md → Async Lifecycle).
- Capture `context.read<T>()` before an `await`; cancel owned subscriptions
  and await the cancellation in `close()`; never dispose shared services from
  a cubit.

## Adding or changing a feature

1. New feature → `./scripts/fgen.sh` (lean by default; `--with-dto` only for a
   real transport schema, `--with-service` only for real shared rules — a
   forwarding service must grow logic or be deleted).
2. Design the state first; define the repository interface before the impl.
3. Run codegen after touching freezed/JSON classes:
   `dart run build_runner build --delete-conflicting-outputs`.
4. Another feature's data needed? Import its barrel; if the barrel lacks it,
   export the domain contract there — never reach into `data/`/`presentation/`.
5. Split a file when it has more than one reason to change, not by line count.
6. Tests: repository mapping/failures, cubit transitions it owns, screen
   states/actions, the feature flow test, DI smoke (`test/README.md`).
7. `./scripts/fverify.sh --fix`; keep `test/architecture_test.dart` green.

## Enforced vs review guidance

`test/architecture_test.dart` fails on: outward dependencies, impure domain
(also through re-export chains), cross-feature imports other than barrels,
barrels exposing data/presentation, feature dependency cycles, core importing
features outside composition roots, stored cubit fields, get_it use outside
composition roots/modules, registrations outside `service_locator.dart` and
modules. Naming, cubit sizing, listener nesting, rebuild scope and lifetimes
are review guidance. Add a negative test with any new rule (reference.md →
Executable Rules).
