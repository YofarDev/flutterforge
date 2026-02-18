import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/l10n/generated/app_localizations.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Log app startup
  AppLogger.info('Application starting...');

  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Yofardev Flutter App',
      debugShowCheckedModeBanner: false,

      // Theme configuration
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Default to dark theme

      // Router configuration
      routerConfig: AppRouter.router,

      // Localization configuration
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate, // Generated localization delegate
        GlobalMaterialLocalizations.delegate, // Material localization
        GlobalWidgetsLocalizations.delegate, // Widgets localization
        GlobalCupertinoLocalizations.delegate, // Cupertino localization
      ],

      // Supported locales
      // Add new locales here when adding new translations
      supportedLocales: const <Locale>[
        Locale('en'), // English
        Locale('fr'), // French
      ],

      // Fallback locale if a specific locale is not found
      // This ensures the app always has a valid locale
      locale: const Locale('en'),
    );
  }
}

