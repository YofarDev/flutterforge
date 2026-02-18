import 'package:get_it/get_it.dart';

/// Global service locator for dependency injection.
/// Access services: final service = getIt<MyService>();
final GetIt getIt = GetIt.instance;

/// Initializes all services. Call before runApp().
///
/// Register services: getIt.registerLazySingleton<MyService>(() => MyService());
/// Access services: getIt<MyService>()
Future<void> setupServiceLocator() async {
  // Register your services here
  // getIt.registerLazySingleton<ApiService>(() => ApiService());
}
