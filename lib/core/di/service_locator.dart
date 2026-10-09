import 'package:get_it/get_it.dart';

import '../../features/counter/data/datasources/counter_local_datasource.dart';
import '../../features/counter/data/repositories/counter_repository_impl.dart';
import '../../features/counter/domain/repositories/counter_repository.dart';
import '../../features/counter/domain/services/counter_service.dart';
import '../../features/counter/presentation/bloc/counter_cubit.dart';
import '../../features/home/data/datasources/home_remote_datasource.dart';
import '../../features/home/data/repositories/home_repository_impl.dart';
import '../../features/home/domain/repositories/home_repository.dart';
import '../../features/home/presentation/bloc/home_cubit.dart';

final GetIt getIt = GetIt.instance;

/// Registers the application dependency graph.
///
/// Test overrides: only the two data-source seams may be replaced (narrow
/// overrides for the real-component flow tests — everything downstream stays
/// the real repository/service/cubit wiring). The full graph is never
/// duplicated in tests; this composition module stays its single home.
Future<void> setupServiceLocator({
  ICounterLocalDataSource? counterLocalDataSourceOverride,
  IHomeRemoteDataSource? homeRemoteDataSourceOverride,
}) async {
  // --- Data Sources ---
  getIt.registerLazySingleton<ICounterLocalDataSource>(
    () => counterLocalDataSourceOverride ?? CounterLocalDataSource(),
  );
  getIt.registerLazySingleton<IHomeRemoteDataSource>(
    () => homeRemoteDataSourceOverride ?? HomeRemoteDataSource(),
  );

  // --- Repositories ---
  getIt.registerLazySingleton<ICounterRepository>(
    () => CounterRepository(getIt<ICounterLocalDataSource>()),
  );
  getIt.registerLazySingleton<IHomeRepository>(
    () => HomeRepository(getIt<IHomeRemoteDataSource>()),
  );

  // --- Services ---
  getIt.registerLazySingleton<CounterService>(
    () => CounterService(getIt<ICounterRepository>()),
  );

  // --- Cubits (Factories) ---
  getIt.registerFactory<CounterCubit>(
    () => CounterCubit(getIt<CounterService>()),
  );
  getIt.registerFactory<HomeCubit>(() => HomeCubit(getIt<IHomeRepository>()));
}
