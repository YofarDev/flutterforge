import '../utils/logger.dart';

/// Example Service demonstrating dependency injection pattern.
///
/// ## THIS IS AN EXAMPLE SERVICE
///
/// When building your app, you can:
/// - **DELETE THIS FILE** if you don't need it
/// - **USE AS REFERENCE** to create your own services
/// - **RENAME AND MODIFY** for your needs
///
/// ## How to Use This Pattern
///
/// 1. Create your service class in `lib/core/services/`
/// 2. Register it in `lib/core/di/service_locator.dart`:
///    ```dart
///    getIt.registerLazySingleton<ExampleService>(() => ExampleService());
///    ```
/// 3. Access it in your BLoCs/Cubits:
///    ```dart
///    final exampleService = getIt<ExampleService>();
///    ```
///
/// ## Service vs Repository
///
/// - **Service**: Use for specialized logic (API calls, execution, parsing)
/// - **Repository**: Use for data orchestration from multiple sources
///
/// Example:
/// ```dart
/// // Service - Single responsibility
/// class ApiService { Future<Data> fetchData(); }
///
/// // Repository - Combines multiple sources
/// class UserRepository {
///   final ApiService _api;
///   final LocalDatabase _local;
///   Future<User> getUser() => _api.fetch().catchError(() => _local.fetch());
/// }
/// ```
class ExampleService {
  ExampleService() {
    // Constructor logic - e.g., initialize clients
    AppLogger.info('ExampleService initialized');
  }

  /// Example method showing async operation.
  ///
  /// Replace with your actual service logic.
  Future<String> fetchData() async {
    // Simulate API call
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return 'Example data';
  }

  /// Example method showing dependency on another service.
  ///
  /// You can access other registered services via get_it:
  /// ```dart
  /// Future<void> doWork() async {
  ///   final otherService = getIt<OtherService>();
  ///   return otherService.help();
  /// }
  /// ```
  Future<void> performAction() async {
    // Your service logic here
  }
}
