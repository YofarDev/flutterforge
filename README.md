# Flutter Project Template

A well-structured Flutter project template following best practices for feature-based architecture, state management, localization, and more.

## Table of Contents

- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Features](#features)
- [Localization (L10n)](#localization-l10n)
- [Routing](#routing)
- [State Management](#state-management)
- [Logger](#logger)
- [Theming](#theming)

## Project Structure

```
lib/
├── core/                          # Core application functionality
│   ├── l10n/                      # Localization files
│   │   ├── app_localizations_en.arb
│   │   ├── app_localizations_fr.arb
│   │   └── README.md
│   ├── router/                    # App routing configuration
│   │   └── app_router.dart
│   ├── theme/                     # App theming
│   │   └── app_theme.dart
│   └── utils/                     # Utility functions
│       └── logger.dart
├── features/                      # Feature modules
│   ├── home/                      # Home feature
│   │   ├── bloc/
│   │   │   ├── home_cubit.dart
│   │   │   └── home_state.dart
│   │   └── home_page.dart
│   └── counter/                   # Counter demo feature (can be deleted)
│       ├── bloc/
│       │   ├── counter_cubit.dart
│       │   └── counter_state.dart
│       └── counter_screen.dart
└── main.dart                      # App entry point
```

## Architecture

This template uses a **feature-based architecture** where each feature is self-contained with its own BLoC/Cubit, state, and UI. This approach:

- Keeps related code together
- Makes features easy to add or remove
- Improves code organization and maintainability
- Facilitates team collaboration

Each feature typically contains:

- **bloc/** - State management (Cubit/Bloc)
  - `feature_cubit.dart` - Business logic
  - `feature_state.dart` - State data
- **models/** - Data models (if needed)
- **screens/** - Screen widgets
- **widgets/** - Reusable feature widgets (if needed)

## Getting Started

### Prerequisites

- Flutter SDK (3.19.0 or higher recommended)
- Dart SDK

### Installation

1. Clone or copy this template
2. Install dependencies:

```bash
flutter pub get
```

3. Generate localization files:

```bash
flutter gen-l10n
```

4. Run the app:

```bash
flutter run
```

## Features

### Home Feature

The main entry point of the application. Extend this feature to build your app's main interface.

### Counter Feature (Demo)

A demonstration feature showing how to implement state management with BLoC/Cubit.

**To remove this demo feature:**

1. Delete the `/lib/features/counter` directory:

```bash
rm -rf lib/features/counter
```

2. Remove the counter route from `/lib/core/router/app_router.dart`:

```dart
// Delete this GoRoute block
GoRoute(
  path: '/counter',
  name: 'Counter',
  builder: (BuildContext context, GoRouterState state) {
    return const CounterScreen();
  },
),
```

3. Remove the import statement:

```dart
// Remove this line
import '../../features/counter/counter_screen.dart';
```

## Adding New Features

Follow these steps to add a new feature:

### 1. Create the Feature Directory

```bash
mkdir -p lib/features/my_feature/bloc
```

### 2. Create the State File

**File:** `lib/features/my_feature/bloc/my_feature_state.dart`

```dart
part of 'my_feature_cubit.dart';

class MyFeatureState extends Equatable {
  final String data;

  const MyFeatureState({this.data = ''});

  MyFeatureState copyWith({String? data}) {
    return MyFeatureState(data: data ?? this.data);
  }

  @override
  List<Object> get props => <Object>[data];
}
```

### 3. Create the Cubit File

**File:** `lib/features/my_feature/bloc/my_feature_cubit.dart`

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'my_feature_state.dart';

class MyFeatureCubit extends Cubit<MyFeatureState> {
  MyFeatureCubit() : super(const MyFeatureState());

  // Add your methods here
  void fetchData() {
    // Your logic here
  }
}
```

### 4. Create the Screen

**File:** `lib/features/my_feature/my_feature_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/my_feature_cubit.dart';

class MyFeatureScreen extends StatelessWidget {
  const MyFeatureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MyFeatureCubit>(
      create: (BuildContext context) => MyFeatureCubit(),
      child: const MyFeatureView(),
    );
  }
}

class MyFeatureView extends StatelessWidget {
  const MyFeatureView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Feature'),
      ),
      body: BlocBuilder<MyFeatureCubit, MyFeatureState>(
        builder: (context, state) {
          return Center(child: Text(state.data));
        },
      ),
    );
  }
}
```

### 5. Add the Route

Update `/lib/core/router/app_router.dart`:

1. Add the import:

```dart
import '../../features/my_feature/my_feature_screen.dart';
```

2. Add the route:

```dart
GoRoute(
  path: '/my-feature',
  name: 'MyFeature',
  builder: (BuildContext context, GoRouterState state) {
    return const MyFeatureScreen();
  },
),
```

### 6. Add Translations (Optional)

Update the `.arb` files in `/lib/core/l10n/`:

**app_localizations_en.arb:**

```json
{
  "myFeature": {
    "title": "My Feature",
    "description": "Feature description"
  }
}
```

**app_localizations_fr.arb:**

```json
{
  "myFeature": {
    "title": "Ma Fonctionnalité",
    "description": "Description de la fonctionnalité"
  }
}
```

Then regenerate:

```bash
flutter gen-l10n
```

## Localization (L10n)

The app supports multiple languages out of the box. Currently configured:

- English (en)
- French (fr)

### Configuration

Localization is configured via `l10n.yaml` in the project root, which specifies:

- ARB file location (`lib/core/l10n/`)
- Template file (`app_localizations_en.arb`)
- Output location for generated code

### Important Notes

**The `AppLocalizations` class is automatically generated.** Do not manually edit `app_localizations.dart` - it will be regenerated when you run:

```bash
flutter gen-l10n
```

Or automatically when you build/run the app (if `generate: true` is set in pubspec.yaml).

### Adding New Translations

1. Edit the `.arb` files in `/lib/core/l10n/`
2. Run `flutter gen-l10n` to generate the localization code
3. Use translations in your code:

```dart
import 'core/l10n/generated/app_localizations.dart';

final l10n = AppLocalizations.of(context);
Text(l10n.homeTitle)
```

For more details, see [/lib/core/l10n/README.md](lib/core/l10n/README.md).

## Routing

The app uses [go_router](https://pub.dev/packages/go_router) for navigation.

### Navigating to a Route

```dart
// Navigate and replace
context.go('/counter');

// Navigate and add to stack
context.push('/counter');

// Navigate with parameters
context.go('/user/123');

// Navigate with query parameters
context.go('/search?q=flutter');
```

For route configuration, see [/lib/core/router/app_router.dart](lib/core/router/app_router.dart).

## State Management

The app uses [flutter_bloc](https://pub.dev/packages/flutter_bloc) for state management.

### Using a Cubit

```dart
// Access the cubit
context.read<MyFeatureCubit>().someMethod();

// Watch state changes
BlocBuilder<MyFeatureCubit, MyFeatureState>(
  builder: (context, state) {
    return Text(state.data);
  },
)
```

## Logger

A simple logger utility is provided at [/lib/core/utils/logger.dart](lib/core/utils/logger.dart).

### Usage

```dart
import 'core/utils/logger.dart';

void main() {
  AppLogger.debug('Debug message');
  AppLogger.info('Info message');
  AppLogger.warning('Warning message');
  AppLogger.error('Error message');
}
```

The logger includes timestamps and log levels for better debugging.

## Theming

The app uses Material 3 design with light and dark themes. Customize theming in [/lib/core/theme/app_theme.dart](lib/core/theme/app_theme.dart).

### Using Theme Colors

```dart
// Primary color
Theme.of(context).colorScheme.primary

// Background color
Theme.of(context).colorScheme.surface

// Text styles
Theme.of(context).textTheme.headlineMedium
```

## Packages Used

- **flutter_bloc** - State management
- **go_router** - Routing and navigation
- **equatable** - Value equality
- **freezed** - Immutable data classes
- **flutter_localizations** - Localization support
- **intl** - Internationalization

## Best Practices

1. **Keep features independent** - Each feature should be self-contained
2. **Use const constructors** - Improve performance
3. **Add comments** - Document complex logic
4. **Follow Dart style guidelines** - Use `dart analyze` to check
5. **Write tests** - Add unit and widget tests
6. **Keep files small** - Split large files into smaller, focused ones
7. **Use type annotations** - Always specify types for public APIs

## Development Commands

```bash
# Analyze code
flutter analyze

# Run tests
flutter test

# Format code
dart format .

# Generate code (freezed, l10n, etc.)
flutter pub run build_runner build

# Clean build
flutter clean
```

## License

This template is open source and available under the MIT License.
