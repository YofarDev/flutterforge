# Flutter Architecture Examples

## Cubit vs BLoC Examples

### When to use Cubit (90% of cases)
```dart
// Forms, auth, CRUD - just call methods
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repo) : super(const AuthState.initial());

  final IAuthRepository _repo;

  Future<void> login(String email, String password) async {
    emit(const AuthState.loading());
    final result = await _repo.login(email, password);
    result.fold(
      (failure) => emit(AuthState.failure(failure.message)),
      (user) => emit(AuthState.authenticated(user)),
    );
  }
}
```

### When to use BLoC (explicit events or concurrency)
```dart
// Search-as-you-type - needs debounce + cancellation semantics
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc(this._repo) : super(const SearchState.initial()) {
    on<QueryChanged>(
      _onQueryChanged,
      transformer: (events, mapper) => events
          .debounceTime(const Duration(milliseconds: 300))
          .switchMap(mapper),
    );
  }

  final ISearchRepository _repo;

  Future<void> _onQueryChanged(
    QueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    emit(const SearchState.loading());
    final result = await _repo.search(event.query);
    result.fold(
      (failure) => emit(SearchState.failure(failure.message)),
      (results) => emit(SearchState.results(results)),
    );
  }
}
```

## State with freezed

```dart
@freezed
class AuthState with _$AuthState {
  const factory AuthState.initial() = _Initial;
  const factory AuthState.loading() = _Loading;
  const factory AuthState.authenticated(User user) = _Authenticated;
  const factory AuthState.failure(String message) = _Failure;
}

// In widget - compiler enforces all cases
state.when(
  initial: () => const LoginForm(),
  loading: () => const CircularProgressIndicator(),
  authenticated: (user) => HomeScreen(user: user),
  failure: (msg) => ErrorBanner(message: msg),
);
```

## MultiBlocListener Pattern

```dart
// CORRECT - flat, readable
MultiBlocListener(
  listeners: [
    BlocListener<AuthCubit, AuthState>(
      listener: (context, state) => state.whenOrNull(
        authenticated: (_) => context.push('/'),
        failure: (msg) => showErrorSnackBar(context, msg),
      ),
    ),
    BlocListener<ThemeCubit, ThemeState>(
      listenWhen: (prev, curr) => prev.themeMode != curr.themeMode,
      listener: (context, state) {
        // Only fires on themeMode change
      },
    ),
  ],
  child: Scaffold(
    appBar: AppBar(title: const Text('Home')),
    body: BlocBuilder<ChatsCubit, ChatsState>(
      builder: (context, state) => ChatsList(chats: state.chats),
    ),
  ),
)
```

## Dependency Injection

```dart
// lib/core/di/service_locator.dart
final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // Data layer
  getIt.registerLazySingleton<AuthApi>(() => AuthApi());
  getIt.registerLazySingleton<IAuthRepository>(
    () => AuthRepositoryImpl(getIt<AuthApi>()),
  );

  // Presentation layer
  getIt.registerFactory<AuthCubit>(
    () => AuthCubit(getIt<IAuthRepository>()),
  );

  // Route-scoped cubit with runtime parameter
  getIt.registerFactoryParam<ProfileCubit, String, void>(
    (userId, _) => ProfileCubit(
      userId: userId,
      repo: getIt<IProfileRepository>(),
    ),
  );
}
```

```dart
// In a route builder or screen composition root
BlocProvider(
  create: (_) => getIt<AuthCubit>(),
  child: const LoginScreen(),
)
```

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

## Repository with Typed Errors

```dart
import 'package:fpdart/fpdart.dart';

// Repository interface (domain layer)
abstract class IAuthRepository {
  Future<Either<Failure, User>> login(String email, String password);
}

// Implementation (data layer)
class AuthRepositoryImpl implements IAuthRepository {
  AuthRepositoryImpl(this._api);

  final AuthApi _api;

  @override
  Future<Either<Failure, User>> login(String email, String password) async {
    try {
      final userDto = await _api.login(email: email, password: password);
      return Right(userDto.toDomain());
    } on ApiException catch (e) {
      return Left(Failure(e.message));
    } catch (_) {
      return Left(const Failure('Unexpected error'));
    }
  }
}
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

## Minimum Architecture Tests

```dart
void main() {
  test('AuthRepositoryImpl maps ApiException to Failure', () async {
    // Arrange / Act / Assert
  });

  blocTest<AuthCubit, AuthState>(
    'emits loading then authenticated on successful login',
    build: () => AuthCubit(mockRepo),
    act: (cubit) => cubit.login('a@b.com', 'secret'),
    expect: () => [
      const AuthState.loading(),
      AuthState.authenticated(testUser),
    ],
  );
}
```
