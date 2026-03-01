---
name: flutter-architecture
description: "Use this skill for any Flutter project work involving architecture, code organization, state management with BLoC/Cubit, or adherence to coding standards. Triggers include: creating new Flutter features, refactoring existing Flutter code, setting up project structure, implementing BLoC patterns, code reviews, or when users mention Flutter best practices, clean architecture, or maintainability concerns."
license: MIT
---

# Flutter Architecture & Coding Standards

## Quick Reference

| Task | Standard |
|------|----------|
| New feature | Layered structure: `data/ → domain/ → presentation/` |
| State management | **Cubit by default**; BLoC only when event transformers are needed |
| Side effects | `BlocListener` for navigation, dialogs, snackbars |
| File size | Widgets/Screens: 300 lines; Services/Repos: 400 lines; BLoCs: 300 lines |
| Models & States | `freezed` (immutable, sealed, exhaustive matching) |
| Error handling | Typed `Result<T>` from repositories, try/catch in cubits |
| Routing | `go_router` — declarative, deep-link ready |
| DI | `get_it` — register all dependencies in `injection.dart` |
| Testing | `bloc_test` for cubits, `mocktail` for mocks |

---

## 1. Cubit vs BLoC

**Default to Cubit.** It covers 90%+ of use cases with less boilerplate and is easier to read and test.

**Upgrade to BLoC only when** you need an `EventTransformer` — debouncing, throttling, or switching concurrent events. The signal is clear: if your Cubit starts holding a `Timer` or a `CancelToken`, reach for BLoC instead.

```dart
// The canonical BLoC use case: search-as-you-type
on<QueryChanged>(
  _onQueryChanged,
  transformer: (events, mapper) => events
      .debounceTime(const Duration(milliseconds: 300))
      .switchMap(mapper), // cancels in-flight request, switches to latest
);
// Handler stays pure — just fetch + emit. No Timer, no CancelToken.
```

| Use Cubit | Use BLoC |
|-----------|----------|
| Forms, auth, CRUD, settings | Search-as-you-type |
| Simple async load + error | Throttled button presses |
| Most screens | Any event stream needing debounce / switchMap |

---

## 2. Layered Architecture

Each feature follows a strict 3-layer structure. **Dependencies only flow inward** — presentation depends on domain, domain depends on data, never the reverse. Features never import from each other; only from `core/`.

```
lib/
├── core/               # Shared across all features
│   ├── di/             # get_it registration (injection.dart)
│   ├── router/         # go_router configuration
│   ├── models/         # Shared freezed models
│   ├── services/       # Shared services (analytics, storage...)
│   ├── utils/          # AppLogger, extensions, helpers
│   └── widgets/        # Reusable UI components
└── features/
    └── auth/
        ├── data/       # API clients, local sources, repository impl
        ├── domain/     # Repository interfaces, entities, use cases
        └── presentation/
            ├── bloc/
            ├── screens/
            └── widgets/
```

---

## 3. Feature Structure Detail

```
auth/
├── data/
│   ├── auth_api.dart           # Raw HTTP / Firebase calls
│   ├── auth_local.dart         # Secure storage
│   └── auth_repository.dart    # Implements domain interface
├── domain/
│   ├── i_auth_repository.dart  # Abstract interface
│   ├── auth_entity.dart        # freezed entity
│   └── login_use_case.dart     # Optional: wraps repository call
└── presentation/
    ├── bloc/
    │   ├── auth_cubit.dart
    │   └── auth_state.dart
    ├── screens/
    │   └── login_screen.dart
    └── widgets/
        └── login_form.dart
```

---

## 4. State & Error Handling

### States with freezed (sealed, exhaustive)
```dart
@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial()                   = _Initial;
  const factory AuthState.loading()                   = _Loading;
  const factory AuthState.authenticated(User user)    = _Authenticated;
  const factory AuthState.failure(String message)     = _Failure;
}

// In widget — compiler enforces all cases
state.when(
  initial:         () => const LoginForm(),
  loading:         () => const CircularProgressIndicator(),
  authenticated:   (user) => HomeScreen(user: user),
  failure:         (msg) => ErrorBanner(message: msg),
);
```

### Typed Result from repositories
```dart
// Use fpdart or a simple custom type
typedef Result<T> = Either<Failure, T>;

// In repository
Future<Result<User>> login(String email, String password);

// In cubit — no silent failures
Future<void> login(String email, String password) async {
  emit(const AuthState.loading());
  final result = await _repository.login(email, password);
  result.fold(
    (failure) => emit(AuthState.failure(failure.message)),
    (user)    => emit(AuthState.authenticated(user)),
  );
}
```

---

## 5. Dependency Injection

All dependencies registered once in `lib/core/di/injection.dart`. **Never instantiate services in widgets.**

```dart
final getIt = GetIt.instance;

void configureDependencies() {
  // Data
  getIt.registerLazySingleton<AuthApi>(() => AuthApi());
  getIt.registerLazySingleton<IAuthRepository>(
    () => AuthRepository(getIt<AuthApi>()),
  );

  // Cubits (registerFactory = new instance each time)
  getIt.registerFactory(() => AuthCubit(getIt<IAuthRepository>()));
}

// In screen
BlocProvider(create: (_) => getIt<AuthCubit>())
```

---

## 6. Routing with go_router

Declare all routes in `lib/core/router/app_router.dart`. Guards via `redirect`.

```dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(
      path: '/profile/:id',
      builder: (_, state) => ProfileScreen(id: state.pathParameters['id']!),
    ),
  ],
  redirect: (context, state) {
    final isAuthed = getIt<AuthCubit>().state is _Authenticated;
    if (!isAuthed && state.uri.path != '/login') return '/login';
    return null;
  },
);
```

Navigation from `BlocListener`:
```dart
BlocListener<AuthCubit, AuthState>(
  listener: (context, state) {
    state.whenOrNull(
      authenticated: (_) => context.go('/'),
      failure: (msg) => ScaffoldMessenger.of(context).showSnackBar(...),
    );
  },
)
```

---

## 7. Component Rules

### Screens
- Provide BLoC via `BlocProvider(create: (_) => getIt<MyCubit>())`
- Compose major widgets, handle navigation via `BlocListener`
- No business logic, no deep widget trees

### Widgets
- Dumb/presentational; use `BlocBuilder` to read state
- Extract to widget classes (not methods) for `const` optimization
- Max nesting depth: 3–4 levels before extracting

### BLoCs / Cubits
- No `BuildContext`, no UI controllers (`TextEditingController` etc.)
- Always separate `cubit.dart` + `state.dart` files
- Wrap all async ops in try/catch, emit typed error states

---

## 8. Models & Serialization

Use `freezed` for all models, entities, and states.

```dart
@freezed
class User with _$User {
  const factory User({
    required String id,
    required String name,
    String? email,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

- Feature models → `features/*/domain/`
- Shared models → `core/models/`
- Never use mutable models

---

## 9. Testing

| Layer | Tool | What to test |
|-------|------|-------------|
| Cubit | `bloc_test` | Every method, all state transitions |
| Repository | `mocktail` | Data source calls, mapping, errors |
| Widget | `flutter_test` | Builder states, user interactions |
| UI regression | `golden_toolkit` | Critical screens |

```dart
// Cubit test example
blocTest<AuthCubit, AuthState>(
  'emits [loading, authenticated] on successful login',
  build: () {
    when(() => mockRepo.login(any(), any()))
        .thenAnswer((_) async => Right(fakeUser));
    return AuthCubit(mockRepo);
  },
  act: (cubit) => cubit.login('a@b.com', 'pass'),
  expect: () => [const AuthState.loading(), AuthState.authenticated(fakeUser)],
);
```

---

## 10. Coding Standards

- **Naming**: `UpperCamelCase` for classes/enums; `snake_case` for files; `lowerCamelCase` for variables
- **Imports**: relative within a feature, package imports across features
- **Colors/styles**: never hardcoded — use `Theme.of(context).colorScheme` or semantic constants
- **Strings**: never hardcoded — use `AppLocalizations`
- **Logging**: use `AppLogger` (not `print`/`debugPrint`); add `tag` for feature context

---

## 11. Anti-Patterns (Never Do)

| ❌ Anti-pattern | ✅ Fix |
|----------------|--------|
| Navigate in `build()` | Use `BlocListener` |
| `TextEditingController` in BLoC | Keep in widget, pass string value to cubit |
| Features importing each other | Route through `core/` only |
| `try/catch` returning `null` on failure | Return `Either<Failure, T>` |
| Services instantiated in widgets | Inject via `get_it` |
| Giant screen files | Extract to `widgets/` subdirectory |
| Raw `GoRouter.of(context).go()` in build | Navigate in `BlocListener` |