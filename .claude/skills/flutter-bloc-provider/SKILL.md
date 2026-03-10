---
name: flutter-bloc-provider
description: Use only when diagnosing or fixing a 'Could not find Provider' runtime error, when writing dialog/bottom sheet code that needs a cubit, or when using Navigator.push (not go_router) with a cubit. For all other cubit/BLoC work, use flutter-architecture instead.
license: MIT
---

# Flutter BLoC/Cubit Provider Skill

## Goal
Generate code that **never** causes:
```
Error: Could not find the correct Provider<XCubit> above this Widget
```

## The Golden Rule

**Always provide BlocProvider ABOVE the widget that uses it.**

| Cubit Scope | Where to Provide |
|-------------|------------------|
| App-wide (auth, theme) | `main.dart` → `MultiBlocProvider` |
| Route-specific | Route builder in `router.dart` or `Navigator.push` |
| Dialog | Inside `showDialog`/`showModalBottomSheet` builder |
| Sub-widget | Parent's `build()` using `builder:` callback |

## Root Causes & Fixes

### Cause 1: Provider Below Consumer

**❌ WRONG:**
```dart
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MyCubit(),
      child: Text(context.watch<MyCubit>().state.toString()), // Same context!
    );
  }
}
```

**✅ FIX 1: Use builder callback**
```dart
BlocProvider(
  create: (_) => MyCubit(),
  builder: (context, child) {  // New context
    return Text(context.watch<MyCubit>().state.toString());
  },
)
```

**✅ FIX 2: Provide at route level (PREFERRED)**
```dart
// In router.dart
GoRoute(
  path: '/home',
  builder: (context, state) => BlocProvider(
    create: (_) => MyCubit(),
    child: const HomeScreen(),  // Screen just consumes
  ),
)

// Screen consumes only
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(context.watch<MyCubit>().state.toString());
  }
}
```

### Cause 2: Cross-Route Access

Providers are **scoped to subtree**. Route A's provider ≠ Route B's.

**Fix:** Re-provide in each route OR provide higher up (if shared).

### Cause 3: Async Gap

**❌ WRONG:**
```dart
Future<void> _doSomething() async {
  await someAsyncOperation();
  context.read<MyCubit>().doThing();  // May throw!
}
```

**✅ CORRECT:**
```dart
Future<void> _doSomething() async {
  final cubit = context.read<MyCubit>();  // Capture first
  await someAsyncOperation();
  cubit.doThing();  // Safe
}
```

## Code Generation Checklist

- [ ] Provider **above** consuming widget in tree
- [ ] Route cubits in router/navigator call, not in screen's `build()`
- [ ] Global cubits in `main.dart`
- [ ] `context.read()` captures **before** `await`
- [ ] If providing in `build()`, use `builder:` callback
- [ ] GoRouter routes provide in their `builder`

## Quick Patterns

**App-wide (main.dart):**
```dart
void main() {
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AuthCubit()),
        BlocProvider(create: (_) => ThemeCubit()),
      ],
      child: const MyApp(),
    ),
  );
}
```

**Route-scoped (router.dart):**
```dart
GoRoute(
  path: '/profile',
  builder: (context, state) => BlocProvider(
    create: (_) => ProfileCubit(),
    child: const ProfileScreen(),
  ),
)
```

**Navigator.push:**
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

## context.read vs context.watch

| Method | Use In | Purpose |
|--------|--------|---------|
| `context.watch` | `build()` | Rebuilds on state change |
| `context.read` | Callbacks | Calls methods, no rebuild |

```dart
@override
Widget build(BuildContext context) {
  final state = context.watch<MyCubit>().state;  // ✅ Rebuilds
  return ElevatedButton(
    onPressed: () => context.read<MyCubit>().doSomething(),  // ✅ No rebuild
    child: Text(state.toString()),
  );
}
```

## Common Mistakes

1. ❌ BlocProvider inside screen it provides (unless using `builder:`)
2. ❌ Assume parent route's cubit in pushed route (re-provide it)
3. ❌ `context.read` after `await` (capture first)
4. ❌ Provide same cubit twice in same subtree
5. ❌ `context.watch` outside `build()` (use `context.read`)

## See Also
- `examples.md` — Complete before/after examples, feature scaffolding template
