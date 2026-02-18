# Flutter Project Template

A professional Flutter project template with feature-based architecture, state management (BLoC/Cubit), dependency injection, and localization.

## 🚀 Quick Start: Building Your App

### ✅ Keep These (Core Infrastructure)

| File/Folder | Purpose |
|-------------|---------|
| `lib/core/di/` | Dependency injection |
| `lib/core/utils/` | Utilities (logger, etc.) |
| `lib/core/theme/` | App theming |
| `lib/core/router/` | Routing configuration |
| `lib/core/l10n/` | Localization files |
| `lib/main.dart` | App entry point |
| `lib/features/home/` | Home screen |

### 🗑️ Remove These (Example Code)

| File/Folder | Action |
|-------------|--------|
| `lib/features/counter/` | Delete entire folder |
| `lib/core/services/example_service.dart` | Delete file |

**After removing examples:** Clean app with home screen and core infrastructure.

---

## Project Structure

```
lib/
├── core/                      # ✅ Core functionality
│   ├── di/                    # ✅ Dependency injection
│   ├── l10n/                  # ✅ Localization
│   ├── router/                # ✅ App routing
│   ├── services/              # ⚠️ Your services (example: delete)
│   ├── theme/                 # ✅ Theming
│   └── utils/                 # ✅ Utilities
├── features/                  # ✅ Feature modules
│   ├── home/                  # ✅ Keep
│   └── counter/               # 🗑️ Demo - delete
└── main.dart
```

Each feature contains: `bloc/` (state), `models/` (data), `screens/` (UI), `widgets/` (reusable).

---

## Getting Started

```bash
flutter pub get           # Install dependencies
flutter gen-l10n          # Generate localization
flutter run               # Run app
```

---

## Architecture

**Feature-based**: Each feature is self-contained with BLoC/Cubit, state, and UI. Keeps code organized and easy to maintain.

---

## Adding New Features

See `/lib/features/counter/` for a complete working example.

**Quick steps:**
1. Create feature directory: `lib/features/my_feature/bloc/`
2. Create state + cubit files
3. Create screen widget
4. Add route in `app_router.dart`
5. Add translations (optional)

---

## Dependency Injection

Uses [get_it](https://pub.dev/packages/get_it). Configure in `lib/core/di/service_locator.dart`.

```dart
// Register service
getIt.registerLazySingleton<MyService>(() => MyService());

// Use anywhere
final service = getIt<MyService>();
```

| Type | Use Case |
|------|----------|
| `registerLazySingleton` | Services (created on first use) |
| `registerFactory` | BLoCs/Cubits (new instance each time) |
| `registerSingleton` | Single instance objects |

---

## State Management (BLoC/Cubit)

Uses [flutter_bloc](https://pub.dev/packages/flutter_bloc).

```dart
// Access cubit
context.read<MyCubit>().doSomething();

// Watch state
BlocBuilder<MyCubit, MyState>(
  builder: (context, state) => Text(state.data),
)
```

### Side Effects (BlocListener)

**IMPORTANT**: Use `BlocListener` for navigation, dialogs, snackbars - never in `build()` or `BlocBuilder`.

```dart
BlocListener<MyCubit, MyState>(
  listener: (context, state) {
    if (state.showError) {
      ScaffoldMessenger.showSnackBar(...);
    }
  },
  child: YourWidget(),
)
```

See example in `lib/features/counter/screens/counter_screen.dart`.

---

## Routing

Uses [go_router](https://pub.dev/packages/go_router).

```dart
context.go('/route');        // Navigate and replace
context.push('/route');      // Add to stack
```

Configure routes in `lib/core/router/app_router.dart`.

---

## Localization (L10n)

English + French included. Add more in `lib/core/l10n/`.

```bash
flutter gen-l10n    # Generate after editing .arb files
```

```dart
final l10n = AppLocalizations.of(context);
Text(l10n.myKey)
```

See [lib/core/l10n/README.md](lib/core/l10n/README.md).

---

## Models & Freezed

Uses [freezed](https://pub.dev/packages/freezed) for immutable models.

```dart
@freezed
class User with _$User {
  const factory User({
    required String id,
    required String name,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

Generate code:
```bash
dart run build_runner build --delete-conflicting-outputs
```

See example in `lib/features/counter/models/counter_settings.dart`.

---

## Theming

Material 3 with light/dark themes. Edit in `lib/core/theme/app_theme.dart`.

```dart
Theme.of(context).colorScheme.primary
Theme.of(context).textTheme.headlineMedium
```

---

## Packages

| Package | Purpose |
|---------|---------|
| flutter_bloc | State management |
| go_router | Navigation |
| get_it | Dependency injection |
| freezed | Immutable models |
| equatable | Value equality |

---

## Development Commands

```bash
flutter analyze                    # Analyze code
flutter test                       # Run tests
dart format .                      # Format code
dart run build_runner build        # Generate code (freezed)
flutter gen-l10n                   # Generate localization
flutter clean                      # Clean build
```

---

## Best Practices

1. Keep features independent and self-contained
2. Use `const` constructors for performance
3. Use `BlocListener` for side effects, `BlocBuilder` for UI
4. Add type annotations for public APIs
5. Keep files small and focused

---

## License

MIT License.
