# Flutter Architecture Anti-Patterns

## Anti-Patterns and Fixes

| ❌ Anti-Pattern | ✅ Fix |
|----------------|-------|
| Navigate in `build()` method | Use `BlocListener` for navigation |
| Nested `BlocListener` widgets | Use `MultiBlocListener` |
| `TextEditingController` in BLoC | Keep in widget, pass string to cubit |
| Features importing each other | Route through `core/` only |
| `try/catch` returning `null` | Return `Either<Failure, T>` |
| Services instantiated in widgets | Inject via `get_it` |
| Giant screen files (>300 lines) | Extract to `widgets/` subdirectory |
| Raw `GoRouter.of(context).go()` in build | Navigate in `BlocListener` |

## Common Mistakes

### Mistake 1: Providing Cubit Inside Screen

```dart
// ❌ WRONG
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MyCubit(),
      child: Text(context.watch<MyCubit>().state.toString()), // Same context!
    );
  }
}

// ✅ CORRECT - provide at route level
// In router.dart:
GoRoute(
  path: '/myscreen',
  builder: (context, state) => BlocProvider(
    create: (_) => MyCubit(),
    child: const MyScreen(),
  ),
)

// Screen just consumes:
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(context.watch<MyCubit>().state.toString());
  }
}
```

### Mistake 2: BlocBuilder Wrapping Entire Scaffold

```dart
// ❌ WRONG - entire screen rebuilds
BlocBuilder<ChatsCubit, ChatsState>(
  builder: (context, state) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Column(
        children: [
          HeavyStaticWidget(), // Rebuilds needlessly!
          ChatsList(chats: state.chats),
        ],
      ),
    );
  },
)

// ✅ CORRECT - only widget that needs state rebuilds
Scaffold(
  appBar: AppBar(title: const Text('Home')),
  body: Column(
    children: [
      const HeavyStaticWidget(), // Never rebuilds
      BlocBuilder<ChatsCubit, ChatsState>(
        builder: (context, state) => ChatsList(chats: state.chats),
      ),
    ],
  ),
)
```

### Mistake 3: Widget Helper Methods

```dart
// ❌ WRONG - rebuilds every time parent rebuilds
class MyScreen extends StatelessWidget {
  Widget _buildHeader() => const Text('Header');

  @override
  Widget build(BuildContext context) {
    return Column(children: [_buildHeader()]);
  }
}

// ✅ CORRECT - Flutter can skip rebuild with const
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
  Widget build(BuildContext context) => const Text('Header');
}
```

### Mistake 4: Context Read After Await

```dart
// ❌ WRONG - widget may be disposed
Future<void> _doSomething() async {
  await someAsyncOperation();
  context.read<MyCubit>().doThing(); // Throws!
}

// ✅ CORRECT - capture before await
Future<void> _doSomething() async {
  final cubit = context.read<MyCubit>(); // Capture first
  await someAsyncOperation();
  cubit.doThing(); // Safe
}
```

### Mistake 5: Cross-Feature Imports

```dart
// ❌ WRONG - features importing each other
// lib/features/auth/screens/login_screen.dart
import '../../../chat/data/chat_api.dart'; // Violates boundary

// ✅ CORRECT - route through core
// lib/core/services/api_service.dart - shared service
// lib/features/auth/screens/login_screen.dart
import '../../../core/services/api_service.dart';
```

## Layer Boundary Violations

### Presentation Importing Data Directly

```dart
// ❌ WRONG
// lib/features/auth/presentation/screens/login_screen.dart
import '../../../data/auth_api.dart'; // Skips domain layer

// ✅ CORRECT
// Use cubit to abstract data layer
// lib/features/auth/presentation/screens/login_screen.dart
// Just imports bloc/auth_cubit.dart - no data imports
```

### Business Logic in Widgets

```dart
// ❌ WRONG - business logic in widget
class LoginScreen extends StatelessWidget {
  Future<void> _login(String email, String password) async {
    // API call directly in widget!
    final response = await http.post(...);
    // Validation logic here too
  }
}

// ✅ CORRECT - logic in cubit
class LoginScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LoginForm(
      onLogin: (email, password) {
        context.read<AuthCubit>().login(email, password);
      },
    );
  }
}
```
