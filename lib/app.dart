import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Root application widget. Without an injected [router] it creates one
/// router per element, keeps it across rebuilds and disposes it; an injected
/// router (tests) stays owned and disposed by the caller.
class MyApp extends StatefulWidget {
  const MyApp({super.key, this.router});

  final GoRouter? router;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  GoRouter? _ownedRouter;

  GoRouter get _effectiveRouter =>
      widget.router ?? (_ownedRouter ??= AppRouter.createRouter());

  @override
  void dispose() {
    // Only the owned router; an injected one belongs to the caller.
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
      // No forced `locale:`: the app follows the device locale.
    );
  }
}
