# Flutter BLoC Provider Examples

## Root Cause #1: Provider Below Consumer

### The Classic Mistake

```dart
// ❌ WRONG - provider at same level as consumer
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit(),
      child: Text(context.watch<HomeCubit>().state.toString()), // Same context!
    );
  }
}
```

**Fix 1: Use builder callback**
```dart
// ✅ CORRECT - builder provides new context
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit(),
      builder: (context, child) {  // New context has access to cubit
        return Text(context.watch<HomeCubit>().state.toString());
      },
    );
  }
}
```

**Fix 2: Provide at route level (PREFERRED)**
```dart
// ✅ BEST - provide BEFORE screen builds
// In router.dart:
GoRoute(
  path: '/home',
  builder: (context, state) => BlocProvider(
    create: (_) => HomeCubit(),
    child: const HomeScreen(),
  ),
)

// Screen just consumes:
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<HomeCubit>();  // Always found
    return Text(cubit.state.toString());
  }
}
```

## Root Cause #2: Cross-Route Access

**Problem:** Providers are scoped to their subtree. A cubit provided in Route A is NOT accessible in Route B.

```dart
// ❌ WRONG - tries to access cubit from different route
// Route A provides HomeCubit
// Route B tries to read HomeCubit - will throw!
```

**Fix options:**

1. **Re-provide in Route B** (if independent instances needed)
2. **Provide higher up** (if truly shared state)
3. **Use RepositoryProvider at top level** (for data layer)

```dart
// ✅ CORRECT - re-provide in each route
GoRoute(
  path: '/home',
  builder: (context, state) => BlocProvider(
    create: (_) => HomeCubit(),
    child: const HomeScreen(),
  ),
)

GoRoute(
  path: '/settings',
  builder: (context, state) => BlocProvider(
    create: (_) => HomeCubit(),  // New instance
    child: const SettingsScreen(),
  ),
)
```

## Root Cause #3: Async Gap

**Problem:** Using `context.read()` after `await` can throw if widget disposed.

```dart
// ❌ WRONG - widget may be gone after await
Future<void> _doSomething() async {
  await someAsyncOperation();
  context.read<HomeCubit>().doThing();  // Throws!
}
```

**Fix:** Capture cubit before await.

```dart
// ✅ CORRECT - capture first, use after await
Future<void> _doSomething() async {
  final cubit = context.read<HomeCubit>();  // Capture BEFORE await
  await someAsyncOperation();
  cubit.doThing();  // Safe
}
```

## App-Wide vs Route-Scoped

### App-Wide Cubits (auth, theme, locale)

**Provide in main.dart:**

```dart
void main() {
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>(
          create: (_) => AuthCubit(),
        ),
        BlocProvider<ThemeCubit>(
          create: (_) => ThemeCubit(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}
```

**Use anywhere:**
```dart
class AnyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    // AuthCubit available everywhere
  }
}
```

### Route-Scoped Cubits (screens, features)

**Provide in route:**

```dart
GoRoute(
  path: '/profile',
  builder: (context, state) => BlocProvider(
    create: (_) => ProfileCubit(
      userId: state.pathParameters['id']!,
    ),
    child: const ProfileScreen(),
  ),
)
```

**Use only in that route:**
```dart
class ProfileScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileCubit>().state;
    // ProfileCubit only available here
  }
}
```

## Multiple Screens, Same Cubit

**Scenario:** HomeScreen and SettingsScreen both need ThemeCubit.

**❌ WRONG:** Provide in each route (wasteful)
```dart
GoRoute(path: '/home', builder: (_, __) =>
  BlocProvider(create: (_) => ThemeCubit(), child: HomeScreen()))

GoRoute(path: '/settings', builder: (_, __) =>
  BlocProvider(create: (_) => ThemeCubit(), child: SettingsScreen()))
```

**✅ CORRECT:** Provide at app level
```dart
void main() {
  runApp(
    BlocProvider(
      create: (_) => ThemeCubit(),  // Single instance
      child: MaterialApp(
        routes: {
          '/': (_) => HomeScreen(),
          '/settings': (_) => SettingsScreen(),
        },
      ),
    ),
  );
}
```

## Feature Folder Template

When scaffolding a new feature, generate this structure:

```
lib/features/home/
├── cubit/
│   ├── home_cubit.dart       # extends Cubit<HomeState>
│   └── home_state.dart
└── screens/
    └── home_screen.dart      # ONLY consumes, never provides
```

**Route registration provides the cubit:**
```dart
// router.dart
GoRoute(
  path: '/home',
  builder: (context, state) => BlocProvider(
    create: (context) => HomeCubit(),
    child: const HomeScreen(),
  ),
)
```

**Screen never contains its own BlocProvider:**
```dart
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        // Use state here
      },
    );
  }
}
```

## Navigator.push with Provider

**❌ WRONG:** Navigate without provider

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const DetailScreen()),
)
// DetailScreen tries to read DetailCubit - throws!
```

**✅ CORRECT:** Provide in navigation call

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => BlocProvider(
      create: (_) => DetailCubit(),
      child: const DetailScreen(),
    ),
  ),
)
```

## Dialog/Bottom Sheet

**Provide inside the dialog builder:**

```dart
showDialog(
  context: context,
  builder: (dialogContext) => BlocProvider(
    create: (_) => DialogCubit(),
    child: AlertDialog(
      title: const Text('Confirm'),
      // Dialog can use DialogCubit
    ),
  ),
)
```

**Or reuse from parent context:**

```dart
showDialog(
  context: context,
  builder: (dialogContext) => BlocProvider.value(
    value: context.read<AuthCubit>(),  // Reuse parent's cubit
    child: AlertDialog(
      title: const Text('Confirm'),
    ),
  ),
)
```

## context.read vs context.watch

**context.watch** - Use in `build()` method
- Rebuilds widget when state changes
- Returns the current state

```dart
@override
Widget build(BuildContext context) {
  final state = context.watch<MyCubit>().state;  // ✅ Correct
  return Text(state.toString());
}
```

**context.read** - Use in callbacks, event handlers, methods
- Doesn't rebuild
- Use to call methods on cubit

```dart
ElevatedButton(
  onPressed: () {
    context.read<MyCubit>().doSomething();  // ✅ Correct
  },
  child: const Text('Do It'),
)
```

**❌ WRONG:** Using watch in callbacks
```dart
onPressed: () {
  final state = context.watch<MyCubit>().state;  // ❌ Don't do this
  // This won't rebuild and wastes resources
}
```

**❌ WRONG:** Using read in build when you need rebuilds
```dart
@override
Widget build(BuildContext context) {
  final state = context.read<MyCubit>().state;  // ❌ Won't rebuild on state change
  return Text(state.toString());
}
```
