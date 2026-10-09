import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/models/failure.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/models/home_data.dart';
import '../../domain/repositories/home_repository.dart';
import 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  final IHomeRepository _homeRepository;

  /// Monotonically increasing identifier for read requests. Each accepted
  /// request captures its identifier before awaiting; after the await the
  /// identifier is compared against the current one so only the newest
  /// request is allowed to emit (latest-request-wins).
  int _requestId = 0;

  HomeCubit(this._homeRepository) : super(const HomeState.initial()) {
    AppLogger.info('HomeCubit initialized', tag: 'HomeCubit');
  }

  Future<void> initialize() => _load();

  Future<void> refresh() => _load();

  Future<void> _load() async {
    // A request invoked after close must not emit (emit on a closed cubit
    // throws a StateError).
    if (isClosed) {
      return;
    }

    final int requestId = ++_requestId;

    AppLogger.debug('Loading home data...', tag: 'HomeCubit');
    emit(const HomeState.loading());

    // Note: awaiting a superseded request here does not cancel its underlying
    // network call — ignoring the stale result only discards its emission. Add
    // transport-level cancellation (e.g. a CancelToken) only if an actual data
    // source needs it.
    final Either<Failure, HomeData> result = await _homeRepository
        .getHomeData();

    // Check before processing EITHER a success or a failure: after close,
    // emitting throws; and a stale (superseded) result must never overwrite a
    // newer request's state.
    if (isClosed || requestId != _requestId) {
      AppLogger.debug(
        'Ignoring stale home data result (request $_requestId superseded or cubit closed)',
        tag: 'HomeCubit',
      );
      return;
    }

    result.fold(
      (Failure failure) {
        // The exception itself was already logged at the repository mapping
        // boundary; log the category only, never duplicate the error details.
        AppLogger.warning(
          'Failed to load home data (${failure.runtimeType})',
          tag: 'HomeCubit',
        );
        emit(HomeState.failure(failure: failure));
      },
      (HomeData homeData) {
        // The message is passed through unmodified: trimming and the
        // empty-message fallback are explicit presentation transformations
        // in the screen — the domain does not own UI copy decisions.
        AppLogger.info('Home data loaded successfully', tag: 'HomeCubit');
        emit(HomeState.loaded(welcomeMessage: homeData.welcomeMessage));
      },
    );
  }
}
