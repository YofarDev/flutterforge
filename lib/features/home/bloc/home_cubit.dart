import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/utils/logger.dart';

part 'home_state.dart';

/// The cubit for the Home feature.
///
/// This cubit manages the state and business logic for the home screen.
/// Use this to handle user interactions, API calls, and other logic.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit() : super(const HomeState()) {
    AppLogger.info('HomeCubit initialized', tag: 'HomeCubit');
  }

  /// Initialize the home screen with data.
  ///
  /// Call this method when the screen first loads to fetch any
  /// necessary data or perform setup operations.
  Future<void> initialize() async {
    AppLogger.debug('Loading home data...', tag: 'HomeCubit');
    emit(state.copyWith(isLoading: true));

    try {
      // Simulate a data fetch
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Emit the loaded state with data
      AppLogger.info('Home data loaded successfully', tag: 'HomeCubit');
      emit(
        state.copyWith(
          isLoading: false,
          welcomeMessage: 'Welcome to the app!',
        ),
      );
    } catch (error) {
      AppLogger.error(
        'Failed to load home data',
        tag: 'HomeCubit',
        error: error,
        stackTrace: StackTrace.current,
      );
      emit(state.copyWith(isLoading: false));
    }
  }

  /// Example method: Refresh the home data.
  Future<void> refresh() async {
    AppLogger.debug('Refreshing home data...', tag: 'HomeCubit');
    await initialize();
  }

  @override
  void onChange(Change<HomeState> change) {
    super.onChange(change);
    AppLogger.debug(
      'Home state changed: isLoading=${change.nextState.isLoading}',
      tag: 'HomeCubit',
    );
  }
}
