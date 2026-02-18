---
name: flutter-architecture
description: "Use this skill for any Flutter project work involving architecture, code organization, state management with BLoC/Cubit, or adherence to coding standards. Triggers include: creating new Flutter features, refactoring existing Flutter code, setting up project structure, implementing BLoC patterns, code reviews, or when users mention Flutter best practices, clean architecture, or maintainability concerns. Apply these standards when writing Dart/Flutter code, organizing files, or making architectural decisions."
license: MIT
---

# Flutter Architecture & Coding Standards

This skill defines architectural patterns, file organization, and coding standards for Flutter projects to ensure maintainability, scalability, and code quality.

## Quick Reference

| Task | Standard Approach |
|------|------------------|
| Create new feature | Use standardized feature structure (bloc/, screens/, widgets/, models/, bloc/) |
| State management | BLoC/Cubit for business logic; setState only for local UI state |
| Side Effects | **ALWAYS** use `BlocListener` for navigation, dialogs, and snackbars |
| File size limit | Widgets/Screens: 300 lines; Services/Repos: 400 lines; BLoCs: 300 lines |
| Extract large widgets | Move to feature's `widgets/` subdirectory |
| Reusable components | Place in `lib/core/widgets/` |
| Data operations | Use Repositories (multi-source) or Services (specialized logic) |
| Models | Immutable; use `freezed` |

---

## 1. File Size Constraints

**Principle:** Keep files focused and readable by enforcing line count limits (including comments and imports).

### Size Limits

| File Type | Maximum Lines | Split Strategy |
|-----------|--------------|----------------|
| Widgets & Screens | 300 | Extract sub-widgets to `widgets/` subdirectory |
| Services & Repositories | 400 | Split by responsibility; extract helpers |
| BLoCs & Cubits | 300 | Always use separate state.dart and event.dart files |

### Example: Splitting an Oversized Widget

**Before (380 lines in script_editor_screen.dart):**
```dart
class ScriptEditorScreen extends StatelessWidget {
  // 380 lines of code including complex toolbar, editor, preview...
}
```

**After:**
```
lib/features/script_editor/
├── screens/
│   └── script_editor_screen.dart (150 lines - coordinates layout)
└── widgets/
    ├── script_toolbar.dart (80 lines)
    ├── code_editor_panel.dart (100 lines)
    └── preview_panel.dart (50 lines)
```

---

## 2. Component Responsibilities

### Screens (`lib/features/*/screens/`)

**Purpose:** Coordinate high-level layout and BLoC integration.

**DO:**
- Provide BLoC/Cubit instances via `BlocProvider`
- Compose major UI sections using feature widgets
- Handle navigation and routing
- **Use `BlocListener` for side effects (navigation, dialogs, snackbars)**

**DON'T:**
- Include complex business logic
- Use manual `setState` for global/shared data
- Embed large widget trees directly

**Example:**
```dart
class ScriptListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ScriptListCubit(
        repository: context.read<ScriptRepository>(),
      )..loadScripts(),
      child: Scaffold(
        appBar: ScriptListAppBar(),
        body: ScriptListBody(),
        floatingActionButton: CreateScriptButton(),
      ),
    );
  }
}
```

### Widgets (`lib/features/*/widgets/` or `lib/core/widgets/`)

**Purpose:** Focused, reusable UI components.

**DO:**
- Keep widgets "dumb" (presentation-focused)
- Use `BlocBuilder` to react to state
- Place feature-specific widgets in feature's `widgets/` directory
- Place reusable components in `lib/core/widgets/`

**DON'T:**
- Perform complex I/O or data processing
- Call services directly
- **Perform navigation or show dialogs inside `build()`**

**Example: Feature-Specific Widget**
```dart
// lib/features/script_editor/widgets/syntax_highlighter.dart
class SyntaxHighlighter extends StatelessWidget {
  final String code;
  final String language;
  
  const SyntaxHighlighter({
    required this.code,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      child: HighlightView(
        code,
        language: language,
        theme: atomOneDarkTheme,
      ),
    );
  }
}
```

### BLoCs & Cubits (`lib/features/*/bloc/`)

**Purpose:** Handle business logic and state transitions.

**DO:**
- Encapsulate all asynchronous operations
- Interact with Repositories and Services
- Emit states for UI updates
- Use separate files: `cubit.dart`, `state.dart` (or `bloc.dart`, `event.dart`, `state.dart`)

**DON'T:**
- Access `BuildContext`
- **Accept UI Controllers (TextEditingController, ScrollController) as arguments**
- Perform UI-related operations
- Exceed 300 lines in any single file

**Example Structure:**
```
lib/features/script_execution/bloc/
├── script_execution_cubit.dart    (business logic, ~200 lines)
└── script_execution_state.dart    (state classes, ~80 lines)
```

**Example: Cubit**
```dart
// lib/features/script_execution/bloc/script_execution_cubit.dart
class ScriptExecutionCubit extends Cubit<ScriptExecutionState> {
  final PythonExecutionService _executionService;
  final ScriptRepository _repository;

  ScriptExecutionCubit({
    required PythonExecutionService executionService,
    required ScriptRepository repository,
  })  : _executionService = executionService,
        _repository = repository,
        super(ScriptExecutionInitial());

  Future<void> executeScript(String scriptId) async {
    try {
      emit(ScriptExecutionLoading());
      
      final script = await _repository.getScript(scriptId);
      final result = await _executionService.execute(script.code);
      
      emit(ScriptExecutionSuccess(result: result));
    } catch (e) {
      emit(ScriptExecutionFailure(error: e.toString()));
    }
  }

  Future<void> cancelExecution() async {
    await _executionService.cancel();
    emit(ScriptExecutionInitial());
  }
}
```

### Repositories & Services (`lib/core/repositories/` or `lib/core/services/`)

**Repositories:** Orchestrate data from multiple sources (API, Local DB, File System).

**DO:**
- Combine data from multiple sources
- Implement caching strategies
- Handle data synchronization
- Return domain models

**Services:** Handle specialized logic (e.g., execution, LLM calls, parsing).

**DO:**
- Focus on a single domain concern
- Extract complex transformations to utility classes
- Keep methods focused and testable

---

## 2.5 Core Utilities

The template includes helpful utilities in `lib/core/utils/`:

### AppLogger

A structured logger with:
- Log levels (debug, info, warning, error)
- Automatic source location tracking (file:line)
- Optional tags for filtering by feature/service
- Runtime log level filtering
- Release build optimization (auto-disables debug logs)

**Usage:**
```dart
AppLogger.debug('Detailed debug info');
AppLogger.info('User action completed', tag: 'AuthService');
AppLogger.warning('API response slow');
AppLogger.error('Operation failed', error: e, stackTrace: stackTrace);
```

**Output:**
```
[10:30:45] DEBUG [api_service.dart:42] [AuthService]: Fetching user data
[10:30:46] INFO [auth_service.dart:78]: User logged in
[10:30:47] ERROR [database.dart:15]: Query failed
  Error: NetworkException
```

**Runtime filtering:**
```dart
// Show only warnings and errors in production
AppLogger.minimumLevel = LogLevel.warning;
```

---

## 2.6 Widget Organization Best Practices

### Single Responsibility
Each widget should do one thing. If a widget is getting long or managing too much state, break it into smaller sub-widgets.

### File Organization

**Naming:** Use `snake_case` and be descriptive:
- `user_profile_card.dart` (good)
- `card2.dart` (bad - not descriptive)

**One widget per file** for anything non-trivial. Small helper widgets can stay in the same file if under ~50 lines.

### Extract Widget Classes (Not Methods)

**Always extract to widget classes rather than helper methods.** This is critical for Flutter's optimization:

```dart
// Bad - Method causes unnecessary rebuilds
class MyScreen extends StatelessWidget {
  Widget _buildHeader() => Text('Header'); // Rebuilds every time
  
  @override
  Widget build(BuildContext context) {
    return Column(children: [_buildHeader()]);
  }
}

// Good - Widget class enables const optimization
class MyScreen extends StatelessWidget {
  const MyScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return const Column(children: [Header()]);
  }
}

class Header extends StatelessWidget {
  const Header({super.key});
  
  @override
  Widget build(BuildContext context) => Text('Header');
}
```

**Benefits:**
- Flutter can optimize rebuilds with `const` constructors
- Better code organization
- Easier to test in isolation
- Prevents context-related bugs

### Co-locate Related Widgets

Keep local widgets that aren't reused elsewhere near their parent:

```
lib/features/home/
├── screens/
│   ├── home_screen.dart       # Main screen
│   └── widgets/               # Local widgets used only here
│       ├── home_header.dart
│       ├── home_stats_card.dart
│       └── home_empty_state.dart
```

Only move to `lib/core/widgets/` if used across multiple features.

### Avoid Deep Nesting

Deeply nested widget trees are hard to read. Extract subtrees early, even if they're only used once, for readability.

**Rule of thumb:** If you have more than 3-4 levels of nesting, extract.

```dart
// Bad - Deep nesting, hard to read
return Scaffold(
  body: SafeArea(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  Icon(Icons.person),
                  SizedBox(width: 8),
                  Text('Name'),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

// Good - Flattened with extracted widgets
return Scaffold(
  body: SafeArea(
    child: const HomeContent(),
  ),
);

class HomeContent extends StatelessWidget {
  const HomeContent({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: const [
          UserCard(),
        ],
      ),
    );
  }
}
```

### Keep Widgets "Dumb"

Separate logic from UI:
- Business logic belongs in BLoCs/Cubits
- Widgets should only display data and handle user input
- Pass callbacks to BLoCs rather than calling methods directly in build

```dart
// Good - Widget is dumb, delegates to BLoC
class CounterButton extends StatelessWidget {
  const CounterButton({super.key});
  
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => context.read<CounterCubit>().increment(),
      child: const Text('Increment'),
    );
  }
}
```

---

## 3. Feature Structure

Every feature in `lib/features/` follows this standardized structure:

```
feature_name/
├── bloc/          # Cubit/BLoC, events, and states
│   ├── feature_cubit.dart
│   └── feature_state.dart
├── screens/       # High-level page widgets
│   └── feature_screen.dart
├── widgets/       # Feature-specific extracted sub-widgets
│   ├── feature_header.dart
│   └── feature_list_item.dart
├── models/        # Data models unique to this feature (use freezed)
│   └── feature_model.dart
└── data/          # (Optional) Feature-specific repositories or providers
    └── feature_local_provider.dart
```

**Note:** The Page/View pattern is also acceptable where screen files are placed
directly in the feature directory (e.g., `home_page.dart` with internal `HomeView` class).
Choose one approach and be consistent across your project.

---

## 4. State Management & Data Flow

### State Management Rules

**Use BLoC/Cubit for:**
- Asynchronous data operations
- State shared across multiple widgets
- Business logic and data transformations
- Navigation with state

**Use `setState` ONLY for:**
- Simple, local UI toggles (expanding/collapsing panels)
- Checkbox/radio button selections (if not part of form state)
- Local animation states
- Widget-internal UI updates with no business logic

### Dependency Injection

**DO:**
- Use `BlocProvider` or service locator (e.g., `get_it`)
- Inject dependencies through constructors
- Access services via `context.read<T>()` in BLoCs

**DON'T:**
- Instantiate services directly in widgets
- Use global singletons (except for DI container itself)
- Pass `BuildContext` to BLoCs or services

---

## 5. Coding Standards

### Naming Conventions

Follow the official [Dart style guide](https://dart.dev/guides/language/effective-dart/style):

- **Classes, Enums, Typedefs:** `UpperCamelCase`
- **Libraries, Packages, Directories, Files:** `lowercase_with_underscores`
- **Variables, Constants, Parameters, Named params:** `lowerCamelCase`
- **Private members:** Prefix with `_`

### Models & Serialization
- Use `freezed` for all data models (included in template dependencies).
- **Always** implement `fromJson` and `toJson`.
- Models must be immutable (`final` fields).
- Place feature-specific models in `lib/features/*/models/`.
- Place shared models in `lib/core/models/`.

**Example:**
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

### Theming
- **Avoid hardcoded colors/styles.** Use `Theme.of(context).colorScheme` or `Theme.of(context).textTheme`.
- Define semantic constants (e.g., `AppColors.error`, `AppSpacing.medium`) rather than raw values.

### Localization
- **Never hardcode user-facing strings.** Use `AppLocalizations.of(context)`.
- All strings are defined in ARB files in `lib/core/l10n/`.
- Use the `tag` parameter in AppLogger to identify which feature/service is logging.

**Adding new translations:**
1. Add keys to `lib/core/l10n/app_localizations_en.arb` (with `@key` metadata)
2. Add translations to other locale files
3. Run `flutter gen-l10n`
4. Use in code: `AppLocalizations.of(context).myKey`

### Logging
- Use `AppLogger` instead of `debugPrint()`.
- Provides log levels, timestamps, source location, and tags.
- Automatically disabled in release builds.
- Example:
  ```dart
  AppLogger.info('User logged in', tag: 'AuthService');
  AppLogger.error('Failed to fetch data', error: e, stackTrace: stackTrace);
  ```

### Imports
- **Relative imports** for files within the same feature.
- **Package imports** for core/other features.

---

## 6. Error Handling

### In BLoCs/Cubits
**Always** wrap async operations in try-catch and emit appropriate error states.

### In Widgets
**Never** handle errors directly in widgets. Let BLoCs handle errors and emit error states:
```dart
// Good - Let BLoC handle errors
BlocBuilder<ScriptCubit, ScriptState>(
  builder: (context, state) {
    if (state is ScriptError) {
      return ErrorWidget(message: state.message);
    }
    // ...
  },
)
```

---

## 7. Common Anti-Patterns to Avoid

### ❌ Navigation/Dialogs in `build()`
```dart
// Bad - Crashes if state emits during build
BlocBuilder<AuthCubit, AuthState>(
  builder: (context, state) {
    if (state is AuthSuccess) {
      Navigator.pushNamed(context, '/home'); // ERROR
    }
    return Container();
  }
)
```
**Fix:** Use `BlocListener` for one-off side effects.

### ❌ UI Controllers in BLoC
```dart
// Bad
class SearchCubit extends Cubit<SearchState> {
  final TextEditingController textController; // ERROR: UI object in BLoC
}
```
**Fix:** Keep controllers in the Widget (StatefulWidget); pass the *string value* to the BLoC functions.

### ❌ Giant "God" Widgets
**Fix:** Extract to multiple focused widgets in `widgets/` subdirectory.

### ❌ Tight Coupling to Services
**Fix:** Inject services through BLoC or DI container.

---

## 8. Testing

The template includes a comprehensive test suite structure mirroring `lib/`:

```
test/
├── features/             # Feature-specific tests
│   ├── counter/
│   │   ├── bloc/counter_cubit_test.dart
│   │   └── counter_screen_test.dart
│   └── home/
│       ├── bloc/home_cubit_test.dart
│       └── home_screen_test.dart
├── core/                 # Core module tests
│   └── theme/app_theme_test.dart
├── app_test.dart         # Integration/smoke tests
└── README.md            # Testing documentation
```

### Test Coverage Requirements

- **Unit Tests:** All Cubit/BLoC methods must be tested
- **Widget Tests:** All screens and critical widgets must be tested
- **Integration Tests:** Critical user flows must be tested

### Running Tests

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/features/home/bloc/home_cubit_test.dart
```

See `test/README.md` for detailed testing guidelines and patterns.

---

## 9. Code Review Checklist

Before submitting code, verify:

- [ ] No file exceeds size limits (Widgets/Screens: 300, Services/Repos: 400, BLoCs: 300)
- [ ] Large widgets are extracted to `widgets/` subdirectory
- [ ] Business logic is in BLoCs/Cubits, not widgets
- [ ] **Navigation/Dialogs handled in `BlocListener`, NOT `build()`**
- [ ] **Models use `freezed` and are immutable**
- [ ] Dependencies injected via constructors
- [ ] `setState` only used for local UI state
- [ ] `dart format .` and `dart fix --apply` has been run
- [ ] No hardcoded colors/styles; used Theme or constants