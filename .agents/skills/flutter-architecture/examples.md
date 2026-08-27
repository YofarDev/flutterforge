# Flutter Architecture Examples

Companion to `SKILL.md`. Only content not already covered there: routing, and
concrete before/after corrections for the most common mistakes.

## Routing with go_router

```dart
// lib/core/router/app_router.dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(
      path: '/profile/:id',
      builder: (_, state) {
        final userId = state.pathParameters['id']!;
        return BlocProvider(
          create: (_) => getIt<ProfileCubit>(param1: userId)..load(),
          child: const ProfileScreen(),
        );
      },
    ),
  ],
  redirect: (_, state) {
    final session = getIt<SessionService>();
    final isAuthed = session.currentUser != null;
    if (!isAuthed && state.uri.path != '/login') return '/login';
    return null;
  },
);
```

## Common Anti-Pattern Corrections

### Provide the cubit above the consumer
```dart
// WRONG - same build context tries to consume immediately
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<MyCubit>(),
      child: Text(context.watch<MyCubit>().state.toString()),
    );
  }
}

// CORRECT - provide at the route boundary
GoRoute(
  path: '/myscreen',
  builder: (_, __) => BlocProvider(
    create: (_) => getIt<MyCubit>(),
    child: const MyScreen(),
  ),
)
```

### Keep `BlocBuilder` narrow
```dart
// WRONG - entire screen rebuilds
BlocBuilder<ChatsCubit, ChatsState>(
  builder: (context, state) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Column(
        children: [
          HeavyStaticWidget(),
          ChatsList(chats: state.chats),
        ],
      ),
    );
  },
)

// CORRECT - only the dependent widget rebuilds
Scaffold(
  appBar: AppBar(title: const Text('Home')),
  body: Column(
    children: [
      const HeavyStaticWidget(),
      BlocBuilder<ChatsCubit, ChatsState>(
        builder: (context, state) => ChatsList(chats: state.chats),
      ),
    ],
  ),
)
```

### Extract focused widgets instead of helper methods when the piece has a clear standalone role
```dart
// OK for tiny local structure, but not a separate concept yet
class MyScreen extends StatelessWidget {
  Widget _buildHeader() => const Text('Header');

  @override
  Widget build(BuildContext context) {
    return Column(children: [_buildHeader()]);
  }
}

// BETTER when the extracted piece has its own clear responsibility
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

### Capture `context.read()` before `await`
```dart
// WRONG
Future<void> _doSomething() async {
  await someAsyncOperation();
  context.read<MyCubit>().doThing();
}

// CORRECT
Future<void> _doSomething() async {
  final cubit = context.read<MyCubit>();
  await someAsyncOperation();
  cubit.doThing();
}
```

### Presentation talks to state, not data
```dart
// WRONG
import '../../data/auth_api.dart';

// CORRECT
import '../bloc/auth_cubit.dart';
```

### Business logic stays out of widgets
```dart
// WRONG - business logic in widget
class LoginScreen extends StatelessWidget {
  Future<void> _login(String email, String password) async {
    final response = await http.post(...);
  }
}

// CORRECT - delegate to cubit
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

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

### Cross-feature access uses contracts, not internals
```dart
// WRONG - feature importing another feature's internals
import '../../../chat/data/chat_api.dart';

// CORRECT - depend on a shared contract or shared module
import '../../../shared/messaging/domain/chat_gateway.dart';
```
