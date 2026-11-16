import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_constants.dart';
import 'data/datasources/counter_local_datasource.dart';
import 'data/repositories/counter_repository_impl.dart';
import 'domain/repositories/counter_repository.dart';
import 'domain/services/counter_service.dart';
import 'presentation/bloc/counter_cubit.dart';
import 'presentation/screens/counter_screen.dart';

/// Composition root of the counter feature: its registrations and routes.
/// Only `service_locator.dart` and `app_router.dart` import this file.
void registerCounterFeature(
  GetIt getIt, {
  ICounterLocalDataSource? localDataSource,
}) {
  getIt.registerLazySingleton<ICounterLocalDataSource>(
    () => localDataSource ?? CounterLocalDataSource(),
  );
  getIt.registerLazySingleton<ICounterRepository>(
    () => CounterRepository(getIt<ICounterLocalDataSource>()),
  );
  getIt.registerLazySingleton<CounterService>(
    () => CounterService(getIt<ICounterRepository>()),
  );
  getIt.registerFactory<CounterCubit>(
    () => CounterCubit(getIt<CounterService>()),
  );
}

List<RouteBase> counterRoutes(GetIt getIt) => <RouteBase>[
  GoRoute(
    path: Routes.counter,
    name: 'Counter',
    builder: (BuildContext context, GoRouterState state) =>
        BlocProvider<CounterCubit>(
          create: (_) => getIt<CounterCubit>(),
          child: const CounterScreen(),
        ),
  ),
];
