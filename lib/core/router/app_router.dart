import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/counter/counter_screen.dart';
import '../../features/home/home_page.dart';

/// The application router configuration.
///
/// This file sets up the routing using go_router.
/// All routes should be defined here for centralized navigation management.
///
/// ## Adding a New Route
///
/// 1. Import your screen at the top of this file:
/// ```dart
/// import '../../features/my_feature/my_screen.dart';
/// ```
///
/// 2. Add a route constant (optional but recommended):
/// ```dart
/// const String _myRoute = '/my-route';
/// ```
///
/// 3. Add the route to the [GoRouter] routes list:
/// ```dart
/// GoRoute(
///   path: _myRoute,
///   name: 'MyRoute',
///   builder: (BuildContext context, GoRouterState state) {
///     return const MyScreen();
///   },
/// ),
/// ```
///
/// 4. Use the route in your app:
/// ```dart
/// // Navigate to the route
/// context.go(_myRoute);
///
/// // Or use push to add to the navigation stack
/// context.push(_myRoute);
/// ```
///
/// ## Removing a Route
///
/// 1. Remove the route constant (if exists)
/// 2. Remove the GoRoute from the routes list
/// 3. Remove any unused imports
/// 4. Remove the feature directory if no longer needed
///
/// ## Route Parameters
///
/// To pass parameters to a route:
/// ```dart
/// GoRoute(
///   path: '/user/:userId',
///   name: 'UserDetail',
///   builder: (BuildContext context, GoRouterState state) {
///     final userId = state.pathParameters['userId'] ?? '';
///     return UserDetailScreen(userId: userId);
///   },
/// ),
/// ```
///
/// ## Query Parameters
///
/// To access query parameters:
/// ```dart
/// GoRoute(
///   path: '/search',
///   name: 'Search',
///   builder: (BuildContext context, GoRouterState state) {
///     final query = state.uri.queryParameters['q'] ?? '';
///     return SearchScreen(query: query);
///   },
/// ),
/// ```
class AppRouter {
  AppRouter._();

  // Route paths
  static const String _homePath = '/';
  static const String _counterPath = '/counter';

  /// The go_router configuration.
  static final GoRouter router = GoRouter(
    debugLogDiagnostics: true, // Set to false in production
    routes: <RouteBase>[
      /// Home Route
      ///
      /// The main entry point of the application.
      GoRoute(
        path: _homePath,
        name: 'Home',
        builder: (BuildContext context, GoRouterState state) {
          return const HomePage();
        },
      ),

      /// Counter Route (Demo Feature)
      ///
      /// DEMO: This is a demonstration route that can be removed.
      /// To remove: Delete this GoRoute block and the counter feature.
      GoRoute(
        path: _counterPath,
        name: 'Counter',
        builder: (BuildContext context, GoRouterState state) {
          return const CounterScreen();
        },
      ),

      /// Add more routes here
      /// Example:
      /// GoRoute(
      ///   path: '/settings',
      ///   name: 'Settings',
      ///   builder: (BuildContext context, GoRouterState state) {
      ///     return const SettingsScreen();
      ///   },
      /// ),
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
