import 'package:flutter/material.dart';

/// Application theme configuration.
///
/// This class provides theme definitions for the app.
/// Customize colors, typography, and other theme properties here.
///
/// The app uses Material 3 design.
/// Learn more: https://m3.material.io/
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

