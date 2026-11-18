import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/core/errors/exception_mapper.dart';
import 'package:my_flutter_app/core/models/failure.dart';

/// Every repository funnels unknown exceptions through
/// `mapExceptionToFailure`, so the classification is tested once here rather
/// than per repository.
void main() {
  test('a timeout becomes a network failure', () {
    expect(
      mapExceptionToFailure(TimeoutException('slow')),
      const Failure.networkError(),
    );
  });

  test('any other error becomes an unexpected failure', () {
    for (final Object error in <Object>[
      Exception('boom'),
      const FormatException('malformed payload'),
      TypeError(),
      StateError('bad state'),
    ]) {
      expect(
        mapExceptionToFailure(error),
        const Failure.unexpected(),
        reason: '$error',
      );
    }
  });
}
