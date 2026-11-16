import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_constants.dart';
import 'data/datasources/home_remote_datasource.dart';
import 'data/repositories/home_repository_impl.dart';
import 'domain/repositories/home_repository.dart';
import 'presentation/bloc/home_cubit.dart';
import 'presentation/screens/home_screen.dart';

/// Composition root of the home feature: its registrations and routes.
/// Only `service_locator.dart` and `app_router.dart` import this file.
void registerHomeFeature(
  GetIt getIt, {
  IHomeRemoteDataSource? remoteDataSource,
}) {
  getIt.registerLazySingleton<IHomeRemoteDataSource>(
    () => remoteDataSource ?? HomeRemoteDataSource(),
  );
  getIt.registerLazySingleton<IHomeRepository>(
    () => HomeRepository(getIt<IHomeRemoteDataSource>()),
  );
  getIt.registerFactory<HomeCubit>(() => HomeCubit(getIt<IHomeRepository>()));
}

List<RouteBase> homeRoutes(GetIt getIt) => <RouteBase>[
  GoRoute(
    path: Routes.home,
    name: 'Home',
    builder: (BuildContext context, GoRouterState state) =>
        BlocProvider<HomeCubit>(
          create: (_) => getIt<HomeCubit>()..initialize(),
          child: const HomeScreen(),
        ),
  ),
];
