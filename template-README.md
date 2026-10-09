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
├── main.dart              # bootstrap (await setupServiceLocator()) + runApp — no other wiring
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
| `./scripts/fverify.sh` | **Quality Gate** (non-mutating): `dart format` check (never rewrites files — run `dart format .` yourself first), then `flutter analyze` + `flutter test` in one command. Run before finishing any change. |
| `./scripts/fgen.sh "name" [--with-service] [--with-dto]` | **Generate New Feature**: Creates Clean Architecture boilerplate (lean by default; optional layers via flags) and runs code generation. Refuses to overwrite an existing feature; snake_case or camelCase names. |
| `./scripts/fstr.sh "key" "FR" "EN"` | **Add Localization**: Adds a new key to both French and English `.arb` files. |
| `./scripts/fl10n.sh` | **Find Unlocalized Strings**: Scans `lib/` for hardcoded user-facing strings that should use `AppLocalizations`. |
| `./scripts/fanal.sh` | **Audit**: Generates a code quality and architecture report. |
| `./scripts/fdead.sh` | **Dead Code**: Identifies unused files in the project. |
| `./scripts/fimp.sh` | **Fix Imports**: Repairs broken imports after files are moved or renamed. |
| `./scripts/sync_skills.sh` | **Sync Skills**: Pushes `.agents/skills` (canonical) to project targets that exist — `.codex/skills/` (optional; skipped when absent) — and, with `--user`, the user-level skill folders. `--check` reports drift across present targets only. |

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
./scripts/fgen.sh my_new_feature                           # lean default
./scripts/fgen.sh my_new_feature --with-service            # + placeholder domain service
./scripts/fgen.sh my_new_feature --with-dto                # + transport DTO + serialization
./scripts/fgen.sh my_new_feature --with-service --with-dto # full layout
./scripts/fgen.sh myNewFeature                             # camelCase also works
```

Layout is proportional to complexity:

- **Lean default** — only what a simple feature needs: freezed domain model
  (no JSON serialization), repository interface, placeholder data source (the
  external-I/O seam; it returns the domain model directly and does NOT
  represent a real transport schema), repository implementation with typed
  results and the exception mapper, cubit depending on the repository
  interface, union state, a single screen widget, and repository/cubit/screen
  tests.
- **`--with-dto`** — additionally generates the transport DTO (with JSON
  serialization), the DTO→domain conversion, and DTO mapping tests. Use it
  when a real transport representation exists (API payloads, cache schemas).
- **`--with-service`** — additionally inserts a placeholder domain service
  between the cubit and the repository, with tests. The placeholder must gain
  actual rules/coordination or be removed — a forwarding service is NOT
  mandatory architecture (compare `CounterService`, which owns real step and
  bounds behavior).

Generation contract:

- The script must run inside this application; the app root is resolved by
  walking up from the current directory (`pubspec.yaml` + `lib/`). There is no
  fallback project name.
- Feature names are normalized to snake_case and validated as Dart identifiers:
  empty values, path separators, `..`, punctuation, invalid starting
  characters and Dart reserved identifiers are rejected, and nothing is
  written for an invalid name.
- It refuses to run if the feature's `lib/features/<name>` or
  `test/features/<name>` directory already exists (symlinks included) — an
  existing feature is never partially overwritten.
- Files are rendered into a temporary directory and published only after
  validation. Screen localization keys are then added via `scripts/fstr.sh`
  (with a key-collision check); if that or `build_runner` fails, the published
  feature is kept, the incomplete state is reported, and the script exits
  non-zero.

After generation, follow the steps the script prints: register the dependencies in
`lib/core/di/service_locator.dart`, add the route in `lib/core/router/app_router.dart`
(the route builder provides the cubit — the generated screen is a pure consumer),
update `test/core/di/service_locator_test.dart`, and replace the placeholder data
source with real I/O. Note that a scaffold passing its unit tests is not a routed
feature — it appears in the app only after the DI and route steps are applied, so
run `fverify` after wiring.

Features generated with the previous full layout keep working as-is; no
migration is required.

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
