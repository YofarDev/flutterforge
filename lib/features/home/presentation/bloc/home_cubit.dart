import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/models/failure.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/models/home_data.dart';
import '../../domain/services/home_service.dart';
import 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  final HomeService _homeService;

  HomeCubit(this._homeService) : super(const HomeState()) {
    AppLogger.info('HomeCubit initialized', tag: 'HomeCubit');
  }

  Future<void> initialize() async {
    AppLogger.debug('Loading home data...', tag: 'HomeCubit');
    emit(state.copyWith(isLoading: true));

    final Either<Failure, HomeData> result = await _homeService.loadHomeData();

    result.fold(
      (Failure failure) {
        AppLogger.error(
          'Failed to load home data',
          tag: 'HomeCubit',
          error: failure.toString(),
        );
        emit(state.copyWith(isLoading: false));
      },
      (HomeData homeData) {
        final String welcomeMessage = _homeService.formatWelcomeMessage(
          homeData.welcomeMessage,
        );

        AppLogger.info('Home data loaded successfully', tag: 'HomeCubit');
        emit(state.copyWith(isLoading: false, welcomeMessage: welcomeMessage));
      },
    );
  }

  Future<void> refresh() async {
    AppLogger.debug('Refreshing home data...', tag: 'HomeCubit');
    await initialize();
  }
}
