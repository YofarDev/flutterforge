part of 'home_cubit.dart';

/// The state for the Home feature.
///
/// This class holds the state data for the home screen.
/// Add any properties you need to track here.
class HomeState extends Equatable {
  /// Example property: loading state
  final bool isLoading;

  /// Example property: welcome message
  final String welcomeMessage;

  const HomeState({
    this.isLoading = false,
    this.welcomeMessage = '',
  });

  /// Creates a copy of this state with the given fields replaced.
  HomeState copyWith({
    bool? isLoading,
    String? welcomeMessage,
  }) {
    return HomeState(
      isLoading: isLoading ?? this.isLoading,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
    );
  }

  @override
  List<Object> get props => <Object>[isLoading, welcomeMessage];
}
