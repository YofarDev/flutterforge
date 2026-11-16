/// Public API of the counter feature: other features import only this file.
/// It exposes domain models, contracts and services, never data or
/// presentation.
library;

export 'domain/models/counter_settings.dart';
export 'domain/repositories/counter_repository.dart';
export 'domain/services/counter_service.dart';
