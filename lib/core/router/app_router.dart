import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/counter/screens/counter_screen.dart';
import '../../features/home/screens/home_screen.dart';

/// Application router configuration using go_router.
///
/// Add routes with: GoRoute(path: '/route', builder: ...)
/// Navigate with: context.go('/route') or context.push('/route')
class AppRouter {
  AppRouter._();

  // Route paths
  static const String _homePath = '/';
  static const String _counterPath = '/counter';

  /// The go_router configuration.
  static final GoRouter router = GoRouter(
    debugLogDiagnostics: true, // Set to false in production
    routes: <RouteBase>[
      // Home Route
      GoRoute(
        path: _homePath,
        name: 'Home',
        builder: (BuildContext context, GoRouterState state) {
          return const HomeScreen();
        },
      ),

      // Counter Route (DEMO - delete this block and counter feature)
      GoRoute(
        path: _counterPath,
        name: 'Counter',
        builder: (BuildContext context, GoRouterState state) {
          return const CounterScreen();
        },
      ),

      // Add routes here: GoRoute(path: '/route', name: 'Route', builder: ...)
    ],

    // Error page for invalid routes
    errorBuilder: (BuildContext context, GoRouterState state) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Error'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('Page not found'),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go(_homePath),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
