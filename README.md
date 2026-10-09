# FlutterForge

A production-ready Flutter template with CLI tools and AI agent skills for robust development.

## What is FlutterForge?

FlutterForge is a template + toolkit that helps you:

- **Start new Flutter projects** with a solid, feature-based architecture. The goal is to provide a template that you can use as a starting point for your next Flutter project, with solid foundations for working with agents.
- **Speed up daily development** with utility scripts.
- **Get AI assistance** with shared agent skills for Claude, Codex, and similar tools.

---

## Quick Start

```bash
# 1. Clone this template
git clone <this-repo> flutterforge
cd flutterforge

# 2. Create your new project
# This creates a new directory 'my_app'. The destination must NOT already
# exist: the generator refuses to overwrite an existing file, directory
# (empty included) or symlink, so retries can never destroy your work.
# Any standard 'flutter create' arguments are forwarded (e.g. --platforms).
dart create_project.dart --org=com.yourcompany --platforms=android,ios my_app

# 3. Start developing
cd my_app
flutter run
```

Your new project is automatically configured with:

- Feature-based architecture (BLoC/Cubit)
- Dependency injection (get_it)
- Routing (go_router)
- Localization (EN + FR)
- Freezed models & JSON serialization
- Mocktail for testing
- Inter font
- Example counter feature

---

## Generator CLI contract (`create_project.dart`)

```
dart create_project.dart [options] <destination>
```

| Option | Meaning |
| ------ | ------- |
| `--org=<org>` or `--org <org>` | Organization (default: `fr.yofardev`). |
| `--project-name=<name>` or `--project-name <name>` | Dart package name. Defaults to the final destination path component. |
| `--description=<desc>` or `--description <desc>` | Project description. A supplied description is kept verbatim; otherwise a default one is written. |
| `--platforms=<platforms>` | Comma-separated platform list forwarded to `flutter create`. |
| `--no-open` | Do not open the project in VS Code. VS Code (if requested) opens only after successful publication. |
| `-h`, `--help` | Show usage. |

Additional rules:

- **Destination.** Exactly one destination is accepted; ambiguous input
  (multiple paths, a missing option value) is rejected before `flutter create`
  runs. The destination must not exist — an existing file, an empty or
  non-empty directory, or a symlink (dangling included) is refused without
  being modified. Absolute and relative destinations work, including paths
  with spaces.
- **Package name.** The Dart package name is validated (`lowercase_with_underscores`,
  no Dart reserved identifiers) and is never derived from a filesystem path
  beyond its final component. Use `--project-name` when the directory name is
  not a valid package name.
- **Staging.** Generation happens in a hidden staging directory next to the
  destination; the app is analyzed and tested there, then published under its
  final name and re-resolved (`flutter pub get`) at the final path. This
  protects ordinary retries — it is not a guarantee against concurrent
  writers to the same destination.
- **Failures.** A failed generation exits non-zero and keeps the staging
  directory (its path is printed) for diagnosis. Nothing is ever deleted from
  a caller-supplied directory.
- **Template checks.** Required template files and the `flutter`, `dart` and
  `bash` executables are validated before anything is created; the template
  root is resolved from the generator script location, not your working
  directory.

---

## What's Included

### Template Features

| Feature          | Implementation                                     |
| ---------------- | -------------------------------------------------- |
| Architecture     | Feature-based with data/domain/presentation layers |
| State Management | Cubit (flutter_bloc)                               |
| DI               | get_it                                             |
| Routing          | go_router                                          |
| Models           | freezed + json_serializable                        |
| Testing          | mocktail + bloc_test                               |
| Localization     | flutter_localizations + intl                       |
| Theming          | Material 3, light/dark                             |

### CLI Scripts

These scripts are automatically copied to your project's `./scripts` folder:

| Script                                         | Purpose                                               |
| ---------------------------------------------- | ----------------------------------------------------- |
| `./scripts/fgen.sh "feature_name" [--with-service] [--with-dto]` | Generate new feature boilerplate (lean Clean Architecture by default; `--with-service` adds a placeholder domain service, `--with-dto` adds a transport DTO). Refuses to overwrite an existing feature. |
| `./scripts/fanal.sh`                         | Generate code audit report for LLM review             |
| `./scripts/fbuild.sh`                        | Build AAB + IPA, auto-increment version               |
| `./scripts/fstr.sh "key" "French" "English"` | Add localization string                               |
| `./scripts/fdead.sh`                         | Find orphaned (unused) files                          |
| `./scripts/fdead.sh --clean-dead`            | Delete orphaned files                                 |
| `./scripts/fimp.sh`                          | Auto-fix broken imports                               |
| `./scripts/fcheck.sh "pattern"`              | Search code in lib/                                   |
| `./scripts/fl10n.sh`                         | Find hardcoded user-facing strings needing l10n      |

### Agent Skills

The template copies `.agents/` (the canonical skill source) and `AGENTS.md` into generated projects — and `.codex/` too when a `.codex/` copy exists in the template root (it is an optional sync target; the canonical location is `.agents/skills/`):

- **flutter-architecture** - Enforces clean architecture, proper DI, file cohesion.
- **flutter-testing** - Unit/widget test patterns with mocktail.
- **flutter-audit** - Analyzes codebase for architecture violations.
- **flutter-bloc-provider** - Fixes provider errors, dialog/sheet patterns.
- **prepare-context** - Exports project files as `.txt` into a flat folder (`context-export/`) for external AI tools.

These instructions are available immediately in generated projects instead of recreating them by hand.

---

## Project Structure

```
lib/
├── main.dart                  # Entry point
├── app.dart                   # MaterialApp configuration
├── core/
│   ├── di/
│   │   └── service_locator.dart    # All DI wiring
│   ├── router/
│   │   ├── app_router.dart
│   │   └── route_constants.dart
│   ├── theme/
│   │   └── app_theme.dart
│   ├── l10n/                  # Localization (.arb files)
│   └── utils/
│       └── logger.dart
└── features/
    └── [feature]/
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

Each feature follows clean architecture with clear separation:

- **data/**: Repository implementations (concrete data sources).
- **domain/**: Business logic - interfaces, models, services.
- **presentation/**: UI layer - blocs, screens, widgets.

### Adding a New Feature

You can quickly generate boilerplate for a new feature; the scaffolding is
proportional to the feature's complexity:

```bash
./scripts/fgen.sh my_new_feature                           # lean default
./scripts/fgen.sh my_new_feature --with-service            # + placeholder domain service
./scripts/fgen.sh my_new_feature --with-dto                # + transport DTO + serialization
./scripts/fgen.sh my_new_feature --with-service --with-dto # full layout
./scripts/fgen.sh myNewFeature                             # camelCase also works
```

- **Lean default**: freezed domain model (no JSON serialization), repository
  interface, placeholder data source (the external-I/O seam — it returns the
  domain model directly and does not represent a real transport schema),
  repository implementation with typed results and the exception mapper, cubit
  depending on the repository interface, union state, a single screen widget,
  and repository/cubit/screen tests.
- **`--with-dto`**: adds the transport DTO with JSON serialization, the
  DTO→domain conversion, and DTO mapping tests — for real transport schemas.
- **`--with-service`**: inserts a placeholder domain service (with tests)
  between cubit and repository. It must gain actual rules/coordination or be
  removed — a forwarding service is not mandatory architecture.

Generation contract:

- The script must run inside a FlutterForge application; the app root is
  resolved by walking up from the current directory (no fallback project name).
- Feature names are normalized to snake_case and validated as Dart identifiers
  (empty values, separators, `..`, punctuation, invalid starting characters
  and Dart reserved identifiers are rejected).
- It refuses to run if the feature's `lib/` or `test/` directory already
  exists (symlinks included) — an existing feature is never partially
  overwritten.
- Files are rendered into a temporary directory and published only after
  validation. Screen localization keys are added via `fstr` (with a
  key-collision check); if that or `build_runner` fails, the published feature
  is kept and the script exits non-zero.

After running the script, follow the printed instructions to register your new
classes in `lib/core/di/service_locator.dart` and add the route in
`lib/core/router/app_router.dart`. A scaffold passing its unit tests is not a
routed feature — it appears in the app only after the DI and route steps are
applied, so run `fverify` after wiring. Features generated with the previous
full layout keep working as-is; no migration is required.

---

## Removing Example Code

After creating a new project, you can delete the demo features to start fresh with a single command:

```bash
./remove_counter.sh
```

This will automatically:

- Delete `lib/features/counter` and `test/features/counter`.
- Remove DI registrations from `service_locator.dart`.
- Remove routes from `app_router.dart`.
- Clean up navigation references in the Home screen.
- Update integration tests in `app_test.dart`.

---

## Development Commands

```bash
flutter pub get                    # Install dependencies
flutter gen-l10n                  # Generate localization
dart run build_runner build --delete-conflicting-outputs # Generate freezed models
flutter analyze                   # Lint code
flutter test                     # Run tests
dart format .                    # Format code
```

---

## Testing

Comprehensive testing documentation can be found in the [test/README.md](test/README.md) file. It covers:

- Unit, Widget, and Integration tests.
- Best practices for mocking with `mocktail`.
- Naming conventions and checklist.

## Testing the template itself

This repository ships its own verification harness (`tools/test_template.py`,
run with `uv`) with two documented levels:

```bash
./scripts/verify_template.sh          # fast: fake tools — refusals, argument
                                      # parsing, staging, shell contract (~seconds)
./scripts/verify_template.sh --full   # + real-Flutter smoke suite: generates
                                      # apps in throwaway directories, exercises
                                      # every fgen combination, wires DI/routes
                                      # for a generated feature, removes the
                                      # counter (twice), and records versions,
                                      # the template git revision and the
                                      # resolved pubspec.lock (minutes)
```

`verify_template.sh` is the template repository's gate; it is distinct from the
generated apps' `./scripts/fverify.sh` (format check + analyze + test inside an
app) and never invokes itself. The template root intentionally has **no
`pubspec.yaml`** — it is a generator and template source, not a runnable app —
so template-level checks run either against fake tools (fast level) or through
disposable generated apps (full smoke). CI
(`.github/workflows/template-verification.yml`) has been added and validated
locally only; it has not yet run remotely. It targets the fast suite plus the
full smoke on Linux (pinned 3.47.4 baseline and current stable) and macOS
(baseline). Supported SDK/tool prerequisites and the minimum-version policy are
documented in [docs/compatibility.md](docs/compatibility.md).

---

## Customization

### Adding Packages

Edit `packages_to_add.json` in the template root before running `create_project.dart`:

```json
{
  "dependencies": ["package_name"],
  "dev_dependencies": ["dev_package_name"]
}
```

### Changing Default Org

```bash
dart create_project.dart --org=com.mycompany my_app
```

Default org is `fr.yofardev`.

---

## License

MIT License - feel free to use in your projects.
