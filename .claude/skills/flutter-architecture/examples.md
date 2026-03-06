# Flutter Architecture Examples

## Cubit vs BLoC Examples

### When to use Cubit (90% of cases)
```dart
// Forms, auth, CRUD - just call methods
class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repo;

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

### When to use BLoC (event transformers needed)
```dart
// Search-as-you-type - needs debounce
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc(this._repo) : super(const SearchState.initial()) {
    on<QueryChanged>(
      _onQueryChanged,
      transformer: (events, mapper) => events
          .debounceTime(const Duration(milliseconds: 300))
          .switchMap(mapper),
    );
  }

  Future<void> _onQueryChanged(QueryChanged event, Emitter emit) async {
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
// ✅ CORRECT - flat, readable
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
// lib/core/di/injection.dart
final getIt = GetIt.instance;

void configureDependencies() {
  // Data layer - singletons
  getIt.registerLazySingleton<AuthApi>(() => AuthApi());
  getIt.registerLazySingleton<IAuthRepository>(
    () => AuthRepository(getIt<AuthApi>()),
  );

  // Presentation layer - factories (new instance each time)
  getIt.registerFactory(() => AuthCubit(getIt<IAuthRepository>()));
}

// In screen
BlocProvider(create: (_) => getIt<AuthCubit>())
```

## Routing with go_router

```dart
// lib/core/router/app_router.dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(
      path: '/profile/:id',
      builder: (_, state) => ProfileScreen(
        id: state.pathParameters['id']!,
      ),
    ),
  ],
  redirect: (context, state) {
    final isAuthed = getIt<AuthCubit>().state is _Authenticated;
    if (!isAuthed && state.uri.path != '/login') return '/login';
    return null;
  },
);
```

## Repository with Typed Errors

```dart
// Repository interface (domain layer)
abstract class IAuthRepository {
  Future<Either<Failure, User>> login(String email, String password);
}

// Implementation (data layer)
class AuthRepository implements IAuthRepository {
  final AuthApi _api;

  @override
  Future<Either<Failure, User>> login(String email, String password) async {
    try {
      final userDto = await _api.login(email: email, password: password);
      return Right(User.fromDto(userDto));
    } on ApiException catch (e) {
      return Left(Failure(e.message));
    } catch (e) {
      return Left(const Failure('Unexpected error')));
    }
  }
}
```
