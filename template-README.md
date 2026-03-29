# {PROJECT_NAME}

A modern Flutter application built with Clean Architecture.

## Architecture

This project follows a **Feature-based Clean Architecture** pattern:

- **Data Layer**: DTOs, Data Sources, and Repository implementations.
- **Domain Layer**: Models, Repository interfaces, and Domain Services (Business Logic).
- **Presentation Layer**: Cubits (State Management), Screens, and Widgets.

Dependencies flow inward only: `presentation → domain ← data`.

## Project Structure

```text
lib/
├── main.dart              # runApp() only — no wiring, no logic
├── app.dart               # MaterialApp.router + app-scoped providers
├── core/
│   ├── di/
│   │   └── service_locator.dart   # All DI wiring
│   ├── router/
│   │   ├── app_router.dart
│   │   └── route_constants.dart
│   ├── models/            # Shared domain models only (freezed)
│   └── utils/
└── features/
    └── [feature_name]/
        ├── data/
        │   ├── datasources/       # Local/remote data sources
        │   ├── models/            # DTOs (data transfer objects)
        │   └── repositories/      # Repository implementations
        ├── domain/
        │   ├── models/            # Feature models (freezed)
        │   ├── repositories/      # Repository interfaces
        │   └── services/          # Domain coordination logic
        └── presentation/
            ├── bloc/               # Cubits + states
            ├── screens/
            └── widgets/
```

## CLI Tools

The following utility scripts are available in the `scripts/` folder:

| Script | Purpose |
|--------|---------|
| `./scripts/fgen.sh "name"` | **Generate New Feature**: Creates all Clean Architecture boilerplate and runs code generation. |
| `./scripts/fstr.sh "key" "FR" "EN"` | **Add Localization**: Adds a new key to both French and English `.arb` files. |
| `./scripts/fanal.sh` | **Audit**: Generates a code quality and architecture report. |
| `./scripts/fdead.sh` | **Dead Code**: Identifies unused files in the project. |
| `./scripts/fimp.sh` | **Fix Imports**: Automatically converts package imports to relative imports. |

## Development Commands

```bash
# Install dependencies
flutter pub get

# Generate localization files
flutter gen-l10n

# Run code generation (Freezed/JSON)
dart run build_runner build --delete-conflicting-outputs

# Run tests
flutter test

# Run the app
flutter run
```

## Adding a New Feature

To add a new feature, use the generation script:

```bash
./scripts/fgen.sh my_new_feature
```

After generation, register your new classes in `lib/core/di/service_locator.dart` and add routes in `lib/core/router/app_router.dart`.

## Removing Example Code

If this project was just created, you can remove the example Counter feature by running:

```bash
./remove_counter.sh
```
