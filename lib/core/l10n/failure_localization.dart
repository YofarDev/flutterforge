import '../models/failure.dart';
import 'generated/app_localizations.dart';

/// Maps a [Failure] exhaustively to user-facing text for the current locale.
///
/// This is the single place where failure categories become UI copy: the
/// domain layer and cubits stay free of `BuildContext` and localized strings.
/// Call it from `build` (or a widget helper) so an existing error state
/// re-localizes automatically when the device locale changes.
///
/// Diagnostic details carried by failures (e.g. [FailureServer.message]) are
/// deliberately ignored — they are for logs and must never be displayed.
String localizeFailure(AppLocalizations l10n, Failure failure) {
  return switch (failure) {
    FailureServer() => l10n.failureServer,
    FailureNetwork() => l10n.failureNetwork,
    FailureUnauthorized() => l10n.failureUnauthorized,
    FailureUnexpected() => l10n.commonError,
  };
}
