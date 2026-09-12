import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/counter/presentation/bloc/counter_cubit.dart';
import '../../features/counter/presentation/screens/counter_screen.dart';
import '../../features/home/presentation/bloc/home_cubit.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../di/service_locator.dart';
import '../l10n/generated/app_localizations.dart';
import 'route_constants.dart';

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    debugLogDiagnostics: true,
    routes: <RouteBase>[
      GoRoute(
        path: Routes.home,
        name: 'Home',
        builder: (BuildContext context, GoRouterState state) {
          return BlocProvider<HomeCubit>(
            create: (_) => getIt<HomeCubit>()..initialize(),
            child: const HomeScreen(),
          );
        },
      ),
      GoRoute(
        path: Routes.counter,
        name: 'Counter',
        builder: (BuildContext context, GoRouterState state) {
          return BlocProvider<CounterCubit>(
            create: (_) => getIt<CounterCubit>(),
            child: const CounterScreen(),
          );
        },
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(l10n.errorTitle)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(l10n.pageNotFound),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go(Routes.home),
                child: Text(l10n.goHome),
              ),
            ],
          ),
        ),
      );
    },
  );
}
