library;

import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../utils/logger.dart';

part 'failure.freezed.dart';

@freezed
sealed class Failure with _$Failure {
  const factory Failure.serverError({required String message}) = _ServerError;
  const factory Failure.networkError() = _NetworkError;
  const factory Failure.unauthorized() = _Unauthorized;
  const factory Failure.unexpected({String? detail}) = _Unexpected;

  const Failure._();

  String get message => when(
    serverError: (String message) => message,
    networkError: () => 'Network error occurred',
    unauthorized: () => 'Unauthorized access',
    unexpected: (String? detail) => detail ?? 'An unexpected error occurred',
  );

  /// Maps an exception a repository does not specifically know about to a
  /// typed failure.
  ///
  /// Repositories should catch their known exception types first and map them
  /// to a specific variant; everything else funnels through here. The details
  /// are logged for debugging, never surfaced to the UI.
  static Failure fromException(
    Object error, {
    StackTrace? stackTrace,
    String tag = 'Repository',
  }) {
    AppLogger.error(
      'Unhandled exception mapped to Failure.unexpected',
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
    return switch (error) {
      TimeoutException() => const Failure.networkError(),
      _ => const Failure.unexpected(),
    };
  }
}
