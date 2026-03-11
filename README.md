# FlutterForge

A production-ready Flutter template with CLI tools and AI agent skills for robust development.

## What is FlutterForge?

FlutterForge is a template + toolkit that helps you:
- **Start new Flutter projects** with a solid, feature-based architecture. The goal is to provide a template that you can use as a starting point for your next Flutter project, with solid foundations for working with agents.
- **Speed up daily development** with utility scripts.
- **Get AI assistance** with Claude-powered development skills.

---

## Quick Start

```bash
# 1. Clone this template
git clone <this-repo> flutterforge
cd flutterforge

# 2. Create your new project
# This will create a new directory 'my_app' inside flutterforge
./create_flutter_project.sh --org=com.yourcompany my_app

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

## What's Included

### Template Features

| Feature | Implementation |
|---------|----------------|
| Architecture | Feature-based with data/domain/presentation layers |
| State Management | Cubit (flutter_bloc) |
| DI | get_it |
| Routing | go_router |
| Models | freezed + json_serializable |
| Testing | mocktail + bloc_test |
| Localization | flutter_localizations + intl |
| Theming | Material 3, light/dark |

### CLI Scripts

These scripts are automatically copied to your project's `./scripts` folder:

| Script | Purpose |
|--------|---------|
| `./scripts/fanal.sh` | Generate code audit report for LLM review |
| `./scripts/fbuild.sh` | Build AAB + IPA, auto-increment version |
| `./scripts/fstr.sh "key" "French" "English"` | Add localization string |
| `./scripts/fdead.sh` | Find orphaned (unused) files |
| `./scripts/fdead.sh --clean-dead` | Delete orphaned files |
| `./scripts/fimp.sh` | Auto-fix broken imports |
| `./scripts/fcheck.sh "pattern"` | Search code in lib/ |
| `./scripts/findstr.sh "pattern"` | Search code in lib/ + test/ |

### Claude Skills

The `.claude/` folder contains skills that help AI assistants work with your Flutter code:

- **flutter-architecture** - Enforces clean architecture, proper DI, file size limits.
- **flutter-testing** - Unit/widget test patterns with mocktail.
- **flutter-bloc-provider** - Fixes provider errors, dialog/sheet patterns.
- **flutter-audit** - Analyzes codebase for architecture violations.

These skills are automatically loaded when using Claude Code.

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
        │   └── repositories/       # Repository implementations
        ├── domain/
        │   ├── models/             # Feature models (freezed)
        │   ├── repositories/       # Repository interfaces
        │   └── services/           # Domain logic
        └── presentation/
            ├── bloc/               # Cubits + states
            ├── screens/
            └── widgets/
```

Each feature follows clean architecture with clear separation:
- **data/**: Repository implementations (concrete data sources).
- **domain/**: Business logic - interfaces, models, services.
- **presentation/**: UI layer - blocs, screens, widgets.

---

## Removing Example Code

After creating a new project, you can delete the demo features to start fresh with a single command:

```bash
.remove_counter.sh
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
dart run build_runner build       # Generate freezed models
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

---

## Customization

### Adding Packages

Edit `packages_to_add.json` in the template root before running `create_flutter_project.sh`:

```json
{
  "dependencies": ["package_name"],
  "dev_dependencies": ["dev_package_name"]
}
```

### Changing Default Org

```bash
./create_flutter_project.sh --org=com.mycompany my_app
```

Default org is `fr.yofardev`.

---

## License

MIT License - feel free to use in your projects.
