# Testing Structure

This directory contains all tests for the Flutter application.

## Directory Structure

The test directory mirrors the `lib/` structure for easy navigation:

```
test/
├── features/             # Feature-specific tests
│   ├── counter/
│   │   ├── bloc/
│   │   │   └── counter_cubit_test.dart
│   │   ├── data/
│   │   │   └── repositories/
│   │   │       └── counter_repository_test.dart
│   │   ├── domain/
│   │   │   └── services/
│   │   │       └── counter_service_test.dart
│   │   └── presentation/
│   │       └── screens/
│   │           └── counter_screen_test.dart
│   └── home/
│       ├── bloc/
│       │   └── home_cubit_test.dart
│       ├── data/
│       │   └── repositories/
│       │       └── home_repository_test.dart
│       ├── domain/
│       │   └── services/
│       │       └── home_service_test.dart
│       └── presentation/
│           └── screens/
│               └── home_screen_test.dart
├── core/                 # Core module tests
│   └── theme/
│       └── app_theme_test.dart
├── app_test.dart         # Integration/smoke tests
└── README.md            # This file
```

## Test Types

### 1. Unit Tests (Cubit/BLoC Tests)

Located in: `test/features/<feature>/bloc/`

These test the business logic in isolation using `bloc_test` package.

**What to test:**
- Initial state
- State transitions
- Business logic methods
- Error handling

**Example:**
```dart
blocTest<CounterCubit, CounterState>(
  'emits [count: 1] when increment is called',
  build: () => counterCubit,
  act: (cubit) => cubit.increment(),
  expect: () => [const CounterState(count: 1)],
);
```

**Best Practices:**
- Always close cubits in `tearDown()`
- Test edge cases (empty states, error states)
- Use `seed` to set initial state for specific scenarios
- Group related tests with `group()`

### 2. Widget Tests

Located in: `test/features/<feature>/`

These test UI components and their interactions.

**What to test:**
- Widget renders correctly
- User interactions (taps, inputs)
- State changes reflect in UI
- Navigation

**Example:**
```dart
testWidgets('increments count when + button is tapped', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider<CounterCubit>.value(
        value: counterCubit,
        child: const CounterView(),
      ),
    ),
  );

  await tester.tap(find.byIcon(Icons.add));
  await tester.pumpAndSettle();

  expect(find.text('1'), findsOneWidget);
});
```

**Best Practices:**
- Always wrap widgets with `MaterialApp` and localization delegates
- Create a helper function `buildTestableWidget()` for consistent setup
- Use `pumpAndSettle()` for async operations
- Close cubits in `tearDown()`

### 3. Repository Tests

Located in: `test/features/<feature>/data/repositories/`

These test data layer: API calls, DTO mapping, error wrapping.

**What to test:**
- `Right(value)` on success
- `Left(Failure)` on errors
- DTO → domain mapping
- Exceptions wrapped in Failure

**Example:**
```dart
test('returns Right(User) on success', () async {
  when(() => mockApi.login(
    email: any(named: 'email'),
    password: any(named: 'password'),
  )).thenAnswer((_) async => fakeUserDto);

  final result = await repo.login('user@ex.com', 'pass');

  expect(result.isRight(), true);
});
```

**Best Practices:**
- Use `registerFallbackValue()` in `setUpAll()` for any() matchers
- Verify mock calls with `verify(() => ...).called(1)`
- Test error paths — exceptions should become `Left(Failure)`

### 4. Domain Service Tests

Located in: `test/features/<feature>/domain/services/`

These test coordination logic extracted from cubits — pure isolation, no cubits.

**What to test:**
- Service methods return correct values
- Edge cases (boundary values, empty input)
- Delegation to repository verified

**Example:**
```dart
test('clamps value above maximum', () {
  const settings = CounterSettings(minValue: 0, maxValue: 100);

  expect(service.clampValue(105, settings), 100);
});
```

**Best Practices:**
- No `blocTest` needed — regular `test()`
- No cubit imports in service tests
- Test every code path in the service

### 5. Integration Tests

Located in: `test/app_test.dart`

These test the app as a whole, verifying navigation and end-to-end flows.

**What to test:**
- App starts without errors
- Navigation between screens works
- Complete user flows

**Example:**
```dart
testWidgets('app starts and shows home screen', (tester) async {
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle(const Duration(milliseconds: 600));

  expect(find.text('Home'), findsOneWidget);
});
```

**Best Practices:**
- Wait for async initialization (e.g., `pumpAndSettle(Duration(milliseconds: 600))`)
- Test critical user paths

### Integration Tests with Service Locator

When testing the full app that uses GetIt service locator, you need to properly setup mocks:

```dart
setUp(() async {
  mockCubit = MockCubit();
  
  // Reset and setup service locator
  getIt.reset();
  await setupServiceLocator();
  
  // Unregister real implementations and register mocks
  getIt.unregister<MyCubit>();
  getIt.registerFactory<MyCubit>(() => mockCubit);
});
```

**Important:**
- Always call `getIt.reset()` before `setupServiceLocator()` to clear previous registrations
- Use `getIt.unregister<T>()` after setup to replace real implementations with mocks
- Call `setupServiceLocator()` in `setUp()` (not `setUpAll()`) to avoid "Type already registered" errors

## Running Tests

### Run all tests:
```bash
flutter test
```

### Run specific test file:
```bash
flutter test test/features/counter/bloc/counter_cubit_test.dart
```

### Run tests with coverage:
```bash
flutter test --coverage
```

### Watch mode (re-run on file changes):
```bash
flutter test --watch
```

## Adding Tests for New Features

When adding a new feature, follow this structure:

1. **Create the feature directory:**
   ```
   test/features/my_feature/
   ├── bloc/
   │   └── my_feature_cubit_test.dart
   └── my_feature_screen_test.dart
   ```

2. **Write Cubit tests first** (test business logic):
   ```dart
   void main() {
     group('MyFeatureCubit', () {
       late MyFeatureCubit cubit;

       setUp(() => cubit = MyFeatureCubit());
       tearDown(() => cubit.close());

       test('initial state is correct', () {
         expect(cubit.state, const MyFeatureState());
       });

       // Add more tests...
     });
   }
   ```

3. **Write Widget tests** (test UI with mocked cubit):
   ```dart
   void main() {
     group('MyFeatureView', () {
       late MyFeatureCubit cubit;

       setUp(() => cubit = MyFeatureCubit());
       tearDown(() => cubit.close());

       Widget buildTestableWidget(Widget child) {
         return MaterialApp(
           localizationsDelegates: AppLocalizations.localizationsDelegates,
           supportedLocales: AppLocalizations.supportedLocales,
           home: BlocProvider<MyFeatureCubit>.value(
             value: cubit,
             child: child,
           ),
        );
       }

       testWidgets('renders correctly', (tester) async {
         await tester.pumpWidget(buildTestableWidget(const MyFeatureView()));
         expect(find.text('My Feature'), findsOneWidget);
       });
     });
   }
   ```

## Test Naming Convention

- **Unit tests:** `should <expected behavior> when <condition>`
  - Example: `emits [count: 1] when increment is called`
  
- **Widget tests:** `displays <what> when <condition>` or `<action> when <condition>`
  - Example: `displays loading indicator when isLoading is true`
  - Example: `increments count when + button is tapped`
  
- **Integration tests:** `<feature> <action> <expected result>`
  - Example: `app starts and shows home screen`

## Testing Checklist

Before submitting code, verify:

- [ ] All cubit methods have tests
- [ ] All UI states are tested (loading, error, empty, success)
- [ ] User interactions are tested (taps, inputs)
- [ ] Edge cases are covered
- [ ] Resources are cleaned up in `tearDown()`
- [ ] Tests pass: `flutter test`

## Common Patterns

### Testing Async Operations
```dart
blocTest<HomeCubit, HomeState>(
  'emits loading then success',
  build: () => cubit,
  act: (cubit) => cubit.fetchData(),
  wait: const Duration(milliseconds: 500),
  expect: () => [
    const HomeState(isLoading: true),
    const HomeState(isLoading: false, data: [...]),
  ],
);
```

### Testing Error States
```dart
blocTest<MyCubit, MyState>(
  'emits error state when fetch fails',
  build: () {
    when(() => mockRepository.fetch()).thenThrow(Exception('Failed'));
    return MyCubit(repository: mockRepository);
  },
  act: (cubit) => cubit.fetch(),
  expect: () => [
    const MyState(isLoading: true),
    const MyState(isLoading: false, error: 'Failed'),
  ],
);
```

### Testing with Mock Dependencies
```dart
import 'package:mocktail/mocktail.dart';

class MockRepository extends Mock implements MyRepository {}

void main() {
  late MockRepository mockRepository;

  setUp(() {
    mockRepository = MockRepository();
  });

  // Use mockRepository in your tests
}
```

## Debugging Tests

Run with verbose output:
```bash
flutter test -v
```

Run a single test:
```bash
flutter test --name "should increment counter"
```

Run tests matching a pattern:
```bash
flutter test --name "CounterCubit"
```
