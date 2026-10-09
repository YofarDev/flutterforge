import 'dart:async';

import '../models/failure.dart';
import '../utils/logger.dart';

/// Classifies an exception a repository does not specifically know about into
/// a typed [Failure] and logs the error and stack trace exactly once, at the
/// data mapping boundary.
///
/// Repositories catch their known exception types first and map them to a
/// specific variant themselves; everything else funnels through here. The
/// details are logged for debugging, never surfaced to the UI. Malformed DTO
/// conversion errors ([FormatException], [TypeError]) also land here and
/// become [Failure.unexpected] instead of escaping as exceptions.
Failure mapExceptionToFailure(
  Object error, {
  StackTrace? stackTrace,
  String tag = 'Repository',
}) {
  final Failure failure = switch (error) {
    TimeoutException() => const Failure.networkError(),
    _ => const Failure.unexpected(),
  };
  AppLogger.error(
    'Exception mapped to ${failure.runtimeType}',
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
  return failure;
}
