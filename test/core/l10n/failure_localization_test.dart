import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/core/l10n/failure_localization.dart';
import 'package:my_flutter_app/core/l10n/generated/app_localizations.dart';
import 'package:my_flutter_app/core/models/failure.dart';

/// `localizeFailure` is the single place failure categories become UI copy.
/// It is a pure function, so it is tested here once instead of through every
/// screen that shows an error.
void main() {
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  final AppLocalizations fr = lookupAppLocalizations(const Locale('fr'));

  test('every failure category has its own English copy', () {
    expect(
      <String>[
        localizeFailure(en, const Failure.networkError()),
        localizeFailure(en, const Failure.unauthorized()),
        localizeFailure(en, const Failure.serverError(message: 'ignored')),
        localizeFailure(en, const Failure.unexpected()),
      ],
      <String>[
        'Network error. Please check your connection.',
        'You are not authorized.',
        'A server error occurred. Please try again later.',
        'An error occurred',
      ],
    );
  });

  test('every failure category is translated to French', () {
    for (final Failure failure in const <Failure>[
      Failure.networkError(),
      Failure.unauthorized(),
      Failure.serverError(message: 'ignored'),
      Failure.unexpected(),
    ]) {
      expect(
        localizeFailure(fr, failure),
        isNot(localizeFailure(en, failure)),
        reason: '${failure.runtimeType} has no French translation',
      );
    }
  });

  test('diagnostic details carried by a failure are never shown', () {
    final String text = localizeFailure(
      en,
      const Failure.serverError(message: 'SECRET-DIAGNOSTIC-42'),
    );

    expect(text, isNot(contains('SECRET-DIAGNOSTIC')));
  });
}
