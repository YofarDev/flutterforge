import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Root application widget.
///
/// Router ownership:
/// - **Default (no [router] injected):** this widget's [State] creates exactly
///   one router lazily and keeps it across rebuilds — rebuilding the root
///   (locale/theme change above it, or a new `MyApp()` instance over the same
///   element) must never lose the current route or its state. The internally
///   owned router is disposed in [State.dispose].
/// - **Injected ([router] supplied):** the caller keeps ownership. Tests
///   inject an explicit router so each test gets an independent, disposable
///   one; this widget does NOT dispose it.
class MyApp extends StatefulWidget {
  const MyApp({super.key, this.router});

  /// Explicitly owned router. When `null`, an internally owned router is
  /// created once per [MyApp] element and disposed with it.
  final GoRouter? router;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  GoRouter? _ownedRouter;

  /// The injected router when present, otherwise the single internally owned
  /// router (created at most once per element, retained across rebuilds).
  GoRouter get _effectiveRouter =>
      widget.router ?? (_ownedRouter ??= AppRouter.createRouter());

  @override
  void dispose() {
    // Dispose only what this widget owns. An injected router belongs to its
    // caller, which disposes it. GoRouter.dispose is void in this version —
    // it must not be awaited.
    _ownedRouter?.dispose();
    _ownedRouter = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: _effectiveRouter,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('fr')],
      // No forced `locale:` — the app follows the device locale, resolved
      // against the supportedLocales above (en, fr). Error states re-localize
      // automatically because failure text is derived at build time.
    );
  }
}
