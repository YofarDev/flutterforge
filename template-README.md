# flutter_template

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
├── app.dart               # MaterialApp.router configuration
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
| `./scripts/fverify.sh` | **Quality Gate**: `flutter analyze` + `flutter test` in one command. Run before finishing any change. |
| `./scripts/fgen.sh "name"` | **Generate New Feature**: Creates all Clean Architecture boilerplate and runs code generation. |
| `./scripts/fstr.sh "key" "FR" "EN"` | **Add Localization**: Adds a new key to both French and English `.arb` files. |
| `./scripts/fl10n.sh` | **Find Unlocalized Strings**: Scans `lib/` for hardcoded user-facing strings that should use `AppLocalizations`. |
| `./scripts/fanal.sh` | **Audit**: Generates a code quality and architecture report. |
| `./scripts/fdead.sh` | **Dead Code**: Identifies unused files in the project. |
| `./scripts/fimp.sh` | **Fix Imports**: Repairs broken imports after files are moved or renamed. |
| `./scripts/sync_skills.sh` | **Sync Skills**: Pushes `.agents/skills` (canonical) to `.claude/`, `.codex/`, and with `--user` the user-level skill folders. `--check` reports drift. |

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

> The `fstr`, `fl10n`, and `fimp` scripts require [uv](https://docs.astral.sh/uv/) on your PATH.

## Adding a New Feature

To add a new feature, use the generation script:

```bash
./scripts/fgen.sh my_new_feature
```

After generation, follow the steps the script prints: register the dependencies in
`lib/core/di/service_locator.dart`, add the route in `lib/core/router/app_router.dart`
(the route builder provides the cubit — the generated screen is a pure consumer),
update `test/core/di/service_locator_test.dart`, and localize the screen strings.

## Guardrails

- `test/architecture_test.dart` enforces the layering rules at test time (no cross-feature
  imports into internals, presentation never imports `data/`, no cubit-to-cubit fields,
  `core/` stays infrastructure-only outside the composition roots).
- `test/core/di/service_locator_test.dart` smoke-tests every DI registration.
- State idioms: union states for load-lifecycle screens (`features/home`), flat `copyWith`
  states for persistent interactive state (`features/counter`). See the `flutter-architecture`
  skill for the full rules.

## Removing Example Code

If this project was just created, you can remove the example Counter feature by running:

```bash
./remove_counter.sh
```
