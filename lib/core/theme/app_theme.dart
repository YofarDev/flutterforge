import 'package:flutter/material.dart';

/// App theme configuration (Material 3).
/// Customize seedColor and other properties here.
class AppTheme {
  AppTheme._();

  /// Light theme configuration.
  ///
  /// Use this for light mode theming.
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
    );
  }

  /// Dark theme configuration.
  ///
  /// Use this for dark mode theming.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    );
  }
}

