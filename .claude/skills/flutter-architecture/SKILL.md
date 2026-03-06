---
name: flutter-architecture
description: Use when creating new Flutter features, refactoring existing Flutter code, setting up project structure, implementing BLoC patterns, code reviews, or when users mention Flutter best practices, clean architecture, or maintainability concerns. Triggers include: "create feature", "refactor this", "project structure", "BLoC pattern", "code review", "best practices".
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
| Errors | `Either<Failure, T>` from repos |
| DI | `get_it` — all in `injection.dart` |

## Core Structure

```
lib/
├── core/          # Shared: di/, router/, models/, services/
└── features/
    └── auth/
        ├── data/      # API, local, repository impl
        ├── domain/    # Interfaces, entities
        └── presentation/  # bloc/, screens/, widgets/
```

**Dependencies flow inward only** — presentation → domain → data.

## Key Patterns

### State with freezed
```dart
@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = _Initial;
  const factory AuthState.loading() = _Loading;
  const factory AuthState.authenticated(User user) = _Authenticated;
  const factory AuthState.failure(String message) = _Failure;
}

// Compiler enforces all cases
state.when(
  initial: () => const LoginForm(),
  loading: () => const CircularProgressIndicator(),
  authenticated: (user) => HomeScreen(user: user),
  failure: (msg) => ErrorBanner(message: msg),
);
```

### MultiBlocListener (Never Nest)
```dart
MultiBlocListener(
  listeners: [
    BlocListener<AuthCubit, AuthState>(
      listener: (context, state) => state.whenOrNull(
        authenticated: (_) => context.push('/'),
        failure: (msg) => showErrorSnackBar(context, msg),
      ),
    ),
  ],
  child: Scaffold(...),
)
```

### Dependency Injection
```dart
// lib/core/di/injection.dart
final getIt = GetIt.instance;

void configureDependencies() {
  getIt.registerLazySingleton<IAuthRepository>(
    () => AuthRepository(getIt<AuthApi>()),
  );
  getIt.registerFactory(() => AuthCubit(getIt<IAuthRepository>()));
}

// In screen
BlocProvider(create: (_) => getIt<AuthCubit>())
```

## Anti-Patterns (Never Do)

| ❌ Wrong | ✅ Fix |
|---------|-------|
| Navigate in `build()` | Use `BlocListener` |
| Nested BlocListeners | Use `MultiBlocListener` |
| Services in widgets | Inject via `get_it` |
| Cross-feature imports | Route through `core/` |
| Helper methods in widgets | Extract to widget classes |
| BlocBuilder wrapping Scaffold | Wrap only dependent widgets |

## See Also
- `examples.md` — Cubit vs BLoC, DI setup, routing examples
- `anti-patterns.md` — Common mistakes with before/after fixes
