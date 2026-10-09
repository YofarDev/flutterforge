---
name: "flutter-bloc-provider"
description: "Use only when diagnosing or fixing a 'Could not find Provider' runtime error, when writing dialog/bottom sheet code that needs a cubit, or when using Navigator.push (not go_router) with a cubit. For all other cubit/BLoC work, use flutter-architecture instead."
---

# Flutter BLoC/Cubit Provider Skill

## Goal
Generate code that **never** causes:
```text
Error: Could not find the correct Provider<XCubit> above this Widget
```

## The Golden Rule

**Provide the cubit above the consuming subtree, and choose intentionally whether you want a new instance or the existing one.**

| Cubit Scope | Where to Provide |
|-------------|------------------|
| App-wide (auth, theme, locale) | App composition root such as `app.dart`, resolved from `getIt` |
| Route-specific | `GoRoute` builder in `app_router.dart`, resolved from `getIt` |
| Pushed route (`Navigator.push`) | A cubit (or cubit factory) supplied by a composition root and injected via constructor — feature code never resolves `getIt` |
| Dialog / bottom sheet | Inside `showDialog` / `showModalBottomSheet` builder |
| Reused existing cubit | `BlocProvider.value(...)` in the new subtree |
| Sub-widget | Parent `build()` only when you truly need a local subtree scope |

**Locator policy (one consistent rule):** `getIt` may be resolved only in the
composition roots — `service_locator.dart`, `app.dart`, `app_router.dart`
(exactly what `test/architecture_test.dart` enforces). Feature presentation
code receives cubits, or cubit factories, through constructors.

## Root Causes & Fixes

### Cause 1: Provider Below Consumer

**❌ WRONG:**
```dart
class MyScreen extends StatelessWidget {
  MyScreen({super.key, required MyCubit Function() myCubitFactory})
      : _myCubitFactory = myCubitFactory;

  final MyCubit Function() _myCubitFactory;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => _myCubitFactory(),
      child: Text(context.watch<MyCubit>().state.toString()), // Same context!
    );
  }
}
```

**✅ FIX 1: Use a `Builder` for a local subtree**
```dart
// `myCubitFactory` is a constructor-injected factory supplied by a
// composition root — see the locator policy below.
BlocProvider(
  create: (_) => myCubitFactory(),
  child: Builder(
    builder: (context) {
      return Text(context.watch<MyCubit>().state.toString());
    },
  ),
)
```

**✅ FIX 2: Provide at the route / feature boundary (preferred)**
```dart
// GoRoute builders live in app_router.dart — an allowed composition root,
// where resolving from getIt is correct.
GoRoute(
  path: '/home',
  builder: (_, __) => BlocProvider(
    create: (_) => getIt<MyCubit>(),
    child: const HomeScreen(),
  ),
)

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(context.watch<MyCubit>().state.toString());
  }
}
```

### Cause 2: New Subtree, Wrong Instance Strategy

Providers are scoped to a subtree. A pushed route, dialog, or bottom sheet is a **new boundary**.

Choose one of these fixes:

**✅ New instance for the new boundary**

The pushed screen's cubit (or a factory for it) is supplied by an allowed
composition root and injected here via the constructor — the pushed-screen
builder itself never resolves `getIt` (that would violate the locator policy
enforced by `test/architecture_test.dart`):
```dart
// Feature widget: receives the cubit factory from a composition root.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.detailCubitFactory});

  final DetailCubit Function(String detailId) detailCubitFactory;

  void _openDetails(BuildContext context, String detailId) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider(
          create: (_) => detailCubitFactory(detailId)..load(),
          child: const DetailScreen(),
        ),
      ),
    );
  }
}

// app_router.dart (composition root): getIt is resolved HERE, then injected.
GoRoute(
  path: '/home',
  builder: (context, state) => HomeScreen(
    detailCubitFactory: (detailId) => getIt<DetailCubit>(param1: detailId),
  ),
)
```

**✅ Reuse the existing cubit instance**
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => BlocProvider.value(
      value: context.read<CartCubit>(),
      child: const CartDetailsScreen(),
    ),
  ),
)
```

Use `BlocProvider.value` only when the new subtree should share the **same existing instance**.

### Cause 3: Async Gap

**❌ WRONG:**
```dart
Future<void> _doSomething() async {
  await someAsyncOperation();
  context.read<MyCubit>().doThing();
}
```

**✅ CORRECT:**
```dart
Future<void> _doSomething() async {
  final cubit = context.read<MyCubit>();
  await someAsyncOperation();
  cubit.doThing();
}
```

## Code Generation Checklist

- [ ] Provider is **above** the consuming subtree
- [ ] Cubit lifetime is intentional: app-wide vs route-scoped vs local subtree
- [ ] New cubit instances are resolved from `getIt` only in a composition root (`app.dart`, `app_router.dart`, `service_locator.dart`); feature code receives cubits or cubit factories via constructors
- [ ] Existing cubits reused across a new subtree use `BlocProvider.value`
- [ ] `context.read()` is captured **before** `await`
- [ ] `GoRoute`, `Navigator.push`, dialogs, and bottom sheets all create an explicit provider boundary
- [ ] `main.dart` stays limited to bootstrap (`await setupServiceLocator()`) + `runApp(...)`; app-wide providers live in the app composition root

## Quick Patterns

App-wide and route-scoped (`GoRoute`) provider patterns are covered in
`flutter-architecture` — the patterns below are the ones specific to pushing
new boundaries.

**Navigator.push (new instance):** use the constructor-injected cubit
factory (see "New instance for the new boundary" above) — never `getIt`
inside the pushed-screen builder:
```dart
Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => BlocProvider(
      create: (_) => detailCubitFactory(detailId)..load(),
      child: const DetailScreen(),
    ),
  ),
)
```

**Dialog / bottom sheet (reuse existing):**
```dart
showDialog(
  context: context,
  builder: (_) => BlocProvider.value(
    value: context.read<AuthCubit>(),
    child: const ConfirmLogoutDialog(),
  ),
)
```

## `context.read` vs `context.watch`

| Method | Use In | Purpose |
|--------|--------|---------|
| `context.watch` | `build()` | Rebuilds on state change |
| `context.read` | Callbacks / async methods | Calls methods, no rebuild |

```dart
@override
Widget build(BuildContext context) {
  final state = context.watch<MyCubit>().state;
  return ElevatedButton(
    onPressed: () => context.read<MyCubit>().doSomething(),
    child: Text(state.toString()),
  );
}
```

## Common Mistakes

1. ❌ Providing below the consumer in the same `build()` context
2. ❌ Recreating a cubit when the new subtree should reuse the same instance
3. ❌ Assuming a parent route's provider is automatically visible in a pushed route/dialog
4. ❌ `context.read` after `await`
5. ❌ Manual cubit construction in feature code, or resolving `getIt` outside a composition root — receive a cubit/cubit factory via constructor instead
6. ❌ Making feature cubits app-wide just to silence a provider error

## See Also
- See ../flutter-architecture/SKILL.md for broader structure, layering, and DI guidance
