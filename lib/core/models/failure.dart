library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'failure.freezed.dart';

@freezed
sealed class Failure with _$Failure {
  const factory Failure.serverError({required String message}) = _ServerError;
  const factory Failure.networkError() = _NetworkError;
  const factory Failure.unauthorized() = _Unauthorized;

  const Failure._();

  String get message => when(
    serverError: (String message) => message,
    networkError: () => 'Network error occurred',
    unauthorized: () => 'Unauthorized access',
  );
}
