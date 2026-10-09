library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'failure.freezed.dart';

/// Pure, immutable error model shared across layers.
///
/// `Failure` carries meaning (the category) only — no user-facing copy and no
/// logging. Presentation text is derived in `core/l10n/failure_localization.dart`;
/// exception classification and logging happen at the data boundary in
/// `core/errors/exception_mapper.dart`. Any field such as [FailureServer.message]
/// is a diagnostic for logs/telemetry and must never be displayed in the UI.
@freezed
sealed class Failure with _$Failure {
  const factory Failure.serverError({required String message}) = FailureServer;
  const factory Failure.networkError() = FailureNetwork;
  const factory Failure.unauthorized() = FailureUnauthorized;
  const factory Failure.unexpected() = FailureUnexpected;
}
