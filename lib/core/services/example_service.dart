import '../utils/logger.dart';

/// Example service demonstrating the DI pattern — delete, rename, or use as a
/// reference when building your own services.
///
/// Register it in `lib/core/di/service_locator.dart`:
/// ```dart
/// getIt.registerLazySingleton<ExampleService>(() => ExampleService());
/// ```
/// then resolve it where needed (usually as a cubit/repository constructor
/// dependency). Services hold specialized logic; repositories orchestrate
/// data from multiple sources.
class ExampleService {
  ExampleService() {
    AppLogger.info('ExampleService initialized');
  }

  /// Replace with your actual service logic.
  Future<String> fetchData() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return 'Example data';
  }

  /// Replace with your actual service logic.
  Future<void> performAction() async {}
}
