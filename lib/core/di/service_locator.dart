import 'package:get_it/get_it.dart';

import '../../features/counter/data/datasources/counter_local_datasource.dart';
import '../../features/counter/data/repositories/counter_repository_impl.dart';
import '../../features/counter/domain/repositories/counter_repository.dart';
import '../../features/counter/domain/services/counter_service.dart';
import '../../features/counter/presentation/bloc/counter_cubit.dart';
import '../../features/home/data/datasources/home_remote_datasource.dart';
import '../../features/home/data/repositories/home_repository_impl.dart';
import '../../features/home/domain/repositories/home_repository.dart';
import '../../features/home/domain/services/home_service.dart';
import '../../features/home/presentation/bloc/home_cubit.dart';

final GetIt getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  // --- Data Sources ---
  getIt.registerLazySingleton<ICounterLocalDataSource>(
    () => CounterLocalDataSource(),
  );
  getIt.registerLazySingleton<IHomeRemoteDataSource>(
    () => HomeRemoteDataSource(),
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
  getIt.registerLazySingleton<HomeService>(
    () => HomeService(getIt<IHomeRepository>()),
  );

  // --- Cubits (Factories) ---
  getIt.registerFactory<CounterCubit>(() => CounterCubit(getIt<CounterService>()));
  getIt.registerFactory<HomeCubit>(() => HomeCubit(getIt<HomeService>()));
}
