import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/counter/counter_module.dart';
import '../../features/home/home_module.dart';
import '../di/service_locator.dart';
import '../l10n/generated/app_localizations.dart';
import 'route_constants.dart';

class AppRouter {
  const AppRouter._();

  /// One router per app instance (never a static: tests need their own,
  /// disposable router). Each feature contributes its routes through its
  /// module; `fgen` adds new ones at the marker.
  static GoRouter createRouter() => GoRouter(
    debugLogDiagnostics: true,
    routes: <RouteBase>[
      ...homeRoutes(getIt),
      ...counterRoutes(getIt),
      // fgen:routes
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
