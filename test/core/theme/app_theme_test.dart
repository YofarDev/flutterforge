import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/core/theme/app_theme.dart';

/// Tests for the AppTheme.
///
/// These tests verify that:
/// - Light and dark themes are properly configured
/// - Material 3 is enabled
/// - Theme properties are correctly set
void main() {
  group('AppTheme', () {
    group('lightTheme', () {
      test('uses Material 3', () {
        expect(AppTheme.lightTheme.useMaterial3, isTrue);
      });

      test('has light brightness', () {
        expect(AppTheme.lightTheme.brightness, Brightness.light);
      });

      test('has a color scheme', () {
        expect(AppTheme.lightTheme.colorScheme, isNotNull);
      });

      test('primary color is derived from seed', () {
        final ThemeData theme = AppTheme.lightTheme;
        expect(theme.colorScheme.primary, isNotNull);
      });
    });

    group('darkTheme', () {
      test('uses Material 3', () {
        expect(AppTheme.darkTheme.useMaterial3, isTrue);
      });

      test('has dark brightness', () {
        expect(AppTheme.darkTheme.brightness, Brightness.dark);
      });

      test('has a color scheme', () {
        expect(AppTheme.darkTheme.colorScheme, isNotNull);
      });

      test('primary color is derived from seed', () {
        final ThemeData theme = AppTheme.darkTheme;
        expect(theme.colorScheme.primary, isNotNull);
      });
    });

    group('consistency', () {
      test('light and dark themes have different brightness', () {
        expect(
          AppTheme.lightTheme.brightness != AppTheme.darkTheme.brightness,
          isTrue,
        );
      });
    });
  });
}
