import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'home_state.dart';

/// The cubit for the Home feature.
///
/// This cubit manages the state and business logic for the home screen.
/// Use this to handle user interactions, API calls, and other logic.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit() : super(const HomeState());

  /// Initialize the home screen with data.
  ///
  /// Call this method when the screen first loads to fetch any
  /// necessary data or perform setup operations.
  Future<void> initialize() async {
    emit(state.copyWith(isLoading: true));

    try {
      // Simulate a data fetch
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Emit the loaded state with data
      emit(
        state.copyWith(
          isLoading: false,
          welcomeMessage: 'Welcome to the app!',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isLoading: false));
      // Handle error appropriately
    }
  }

  /// Example method: Refresh the home data.
  Future<void> refresh() async {
    await initialize();
  }
}
