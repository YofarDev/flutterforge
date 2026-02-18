import 'package:flutter/foundation.dart';

/// Log levels for filtering log messages.
///
/// Levels can be compared using their index values:
/// - `none` (index 0) - No logging
/// - `debug` (index 1) - Debug messages
/// - `info` (index 2) - Info messages
/// - `warning` (index 3) - Warning messages
/// - `error` (index 4) - Error messages
///
/// Example:
/// ```dart
/// // Only log warnings and errors
/// AppLogger.minimumLevel = LogLevel.warning;
///
/// // Disable all logging
/// AppLogger.minimumLevel = LogLevel.none;
/// ```
enum LogLevel {
  /// No logging
  none,

  /// Debug messages for development
  debug,

  /// Informational messages about app flow
  info,

  /// Warning messages for potential issues
  warning,

  /// Error messages for critical issues
  error,
}

/// A simple logger wrapper around [debugPrint] with log levels, timestamps,
/// and source location information.
///
/// This logger provides:
/// - Log levels (debug, info, warning, error)
/// - Automatic filtering in release builds using [kDebugMode]
/// - Source file and line number for easy debugging
/// - Optional tag/context for better log organization
/// - Consistent formatting
/// - Runtime log level filtering
/// - Ready for crash reporting integration
///
/// Usage:
/// ```dart
/// AppLogger.debug('This is a debug message');
/// AppLogger.info('This is an info message', tag: 'AuthService');
/// AppLogger.warning('This is a warning message');
/// AppLogger.error('This is an error message');
/// AppLogger.error('Failed to authenticate', error: e, stackTrace: stackTrace);
/// ```
///
/// Output example:
/// ```
/// [10:30:45.123] DEBUG [home_page.dart:42] [AuthService]: User tapped button
/// [10:30:46.456] INFO [api_service.dart:78]: Data loaded successfully
/// [10:30:47.789] ERROR [auth_cubit.dart:15]: Failed to authenticate
///   Error: InvalidCredentials
///   StackTrace: #0      AuthCubit.login (package:my_app/features/auth/bloc/auth_cubit.dart:15)
/// ```
///
/// ## Log Level Filtering
///
/// By default, debug builds show all logs and release builds only show warnings and errors.
/// You can adjust this at runtime:
///
/// ```dart
/// // Show only errors
/// AppLogger.minimumLevel = LogLevel.error;
///
/// // Disable all logging
/// AppLogger.minimumLevel = LogLevel.none;
///
/// // Show everything (useful for debugging production issues)
/// AppLogger.minimumLevel = LogLevel.debug;
/// ```
///
/// ## Crash Reporting Integration
///
/// The error logger is ready for crash reporting integration. Uncomment the relevant
/// line in the [error] method to enable it:
///
/// ```dart
/// // Firebase Crashlytics
/// // FirebaseCrashlytics.instance.recordError(error, stackTrace);
///
/// // Sentry
/// // Sentry.captureException(error, stackTrace: stackTrace);
/// ```
class AppLogger {
  AppLogger._();

  /// The minimum log level to display.
  ///
  /// Logs below this level will be ignored.
  /// Defaults to [LogLevel.debug] in debug builds and [LogLevel.warning] in release builds.
  static LogLevel minimumLevel = kDebugMode ? LogLevel.debug : LogLevel.warning;

  /// Logs a debug message.
  ///
  /// Debug messages are useful for development and troubleshooting.
  /// They are automatically disabled in release builds.
  ///
  /// Example:
  /// ```dart
  /// AppLogger.debug('User tapped button');
  /// AppLogger.debug('Fetching data', tag: 'ApiService');
  /// ```
  static void debug(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.debug, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Logs an info message.
  ///
  /// Info messages provide general information about app flow.
  ///
  /// Example:
  /// ```dart
  /// AppLogger.info('User logged in successfully');
  /// AppLogger.info('Data loaded', tag: 'UserService');
  /// ```
  static void info(String message, {String? tag}) {
    _log(LogLevel.info, message, tag: tag);
  }

  /// Logs a warning message.
  ///
  /// Warning messages indicate potential issues that don't prevent
  /// the app from functioning.
  ///
  /// Example:
  /// ```dart
  /// AppLogger.warning('API response took longer than expected');
  /// AppLogger.warning('Cache miss', tag: 'CacheService');
  /// ```
  static void warning(String message, {String? tag}) {
    _log(LogLevel.warning, message, tag: tag);
  }

  /// Logs an error message.
  ///
  /// Error messages indicate critical issues that may affect app functionality.
  /// These should always be logged, even in production.
  ///
  /// Optionally includes error object and stack trace for debugging.
  /// This method also includes integration points for crash reporting services.
  ///
  /// Example:
  /// ```dart
  /// AppLogger.error('Failed to load user data');
  /// AppLogger.error(
  ///   'Authentication failed',
  ///   tag: 'AuthService',
  ///   error: e,
  ///   stackTrace: stackTrace,
  /// );
  /// ```
  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.error, message, tag: tag, error: error, stackTrace: stackTrace);

    // Crash reporting integration
    // Uncomment the appropriate service for your project:

    // Firebase Crashlytics
    // if (error != null || stackTrace != null) {
    //   FirebaseCrashlytics.instance.recordError(
    //     error,
    //     stackTrace,
    //     fatal: false,
    //     context: {'message': message},
    //   );
    // }

    // Sentry
    // if (error != null || stackTrace != null) {
    //   Sentry.captureException(
    //     error,
    //     stackTrace: stackTrace,
    //     hint: {'message': message},
    //   );
    // }
  }

  /// Internal method to format and print log messages with source location.
  static void _log(
    LogLevel level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Check if this log level should be displayed
    if (level.index < minimumLevel.index) {
      return;
    }

    // Get the current stack trace
    final StackTrace currentStackTrace = StackTrace.current;
    final String stackTraceStr = currentStackTrace.toString();

    // Parse the stack trace to find the caller (skip logger frames)
    final List<String> lines = stackTraceStr.split('\n');

    // Find the first line that's not from logger.dart
    String? callerInfo;
    for (final String line in lines) {
      if (line.contains('logger.dart')) {
        continue; // Skip logger frames
      }
      if (line.contains('#')) {
        // Extract file and line number from stack trace
        // Format: #1  SomeClass.method (package:app/path/to/file.dart:42:15)
        final RegExp regex = RegExp(r'\(([^:]+):(\d+):\d+\)');
        final Match? match = regex.firstMatch(line);
        if (match != null) {
          final String file = match.group(1) ?? 'unknown';
          final String lineNumber = match.group(2) ?? '?';
          // Extract just the filename from the full path
          final String fileName = file.split('/').last;
          callerInfo = '$fileName:$lineNumber';
        }
        break;
      }
    }

    // Format timestamp (show only time for brevity)
    final String timestamp = DateTime.now().toIso8601String().split('T').last;
    final String timeOnly = timestamp.split('.').first; // Remove microseconds

    // Format log level
    final String levelStr = level.name.toUpperCase();

    // Format tag if present
    final String tagStr = tag != null ? ' [$tag]' : '';

    // Build the log message
    final String caller = callerInfo ?? 'unknown:0';
    final String formattedMessage = '[$timeOnly] $levelStr [$caller]$tagStr: $message';

    // Print the main message
    debugPrint(formattedMessage);

    // Print error and stack trace if provided
    if (error != null) {
      debugPrint('  Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('  StackTrace: $stackTrace');
    }
  }
}
