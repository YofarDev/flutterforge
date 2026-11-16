import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/bloc/latest_request_wins.dart';
import '../../../../core/models/failure.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/models/home_data.dart';
import '../../domain/repositories/home_repository.dart';
import 'home_state.dart';

class HomeCubit extends Cubit<HomeState> with LatestRequestWins<HomeState> {
  final IHomeRepository _homeRepository;

  HomeCubit(this._homeRepository) : super(const HomeState.initial());

  Future<void> initialize() => _load();

  Future<void> refresh() => _load();

  /// Latest-request-wins read (see [LatestRequestWins]).
  Future<void> _load() => runLatest<Either<Failure, HomeData>>(
    _homeRepository.getHomeData,
    onStart: () => emit(const HomeState.loading()),
    onResult: (Either<Failure, HomeData> result) => result.fold(
      (Failure failure) {
        // The exception was already logged at the repository boundary; log
        // the category only.
        AppLogger.warning(
          'Failed to load home data (${failure.runtimeType})',
          tag: 'HomeCubit',
        );
        emit(HomeState.failure(failure: failure));
      },
      // Passed through unmodified: trimming and the empty-message fallback
      // are presentation decisions made by the screen.
      (HomeData homeData) =>
          emit(HomeState.loaded(welcomeMessage: homeData.welcomeMessage)),
    ),
  );
}
