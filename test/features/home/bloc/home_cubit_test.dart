import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/features/home/bloc/home_cubit.dart';

/// Tests for the HomeCubit.
///
/// These tests verify the business logic of the home feature,
/// particularly the async initialization and state management.
void main() {
  group('HomeCubit', () {
    late HomeCubit homeCubit;

    setUp(() {
      homeCubit = HomeCubit();
    });

    tearDown(() {
      homeCubit.close();
    });

    test('initial state has isLoading false and empty welcomeMessage', () {
      expect(
        homeCubit.state,
        const HomeState(isLoading: false, welcomeMessage: ''),
      );
    });

    group('initialize', () {
      blocTest<HomeCubit, HomeState>(
        'emits loading state then loaded state with welcome message',
        build: () => homeCubit,
        act: (HomeCubit cubit) => cubit.initialize(),
        wait: const Duration(milliseconds: 600), // Wait for the simulated delay
        expect: () => <HomeState>[
          const HomeState(isLoading: true, welcomeMessage: ''),
          const HomeState(
            isLoading: false,
            welcomeMessage: 'Welcome to the app!',
          ),
        ],
      );
    });

    group('refresh', () {
      blocTest<HomeCubit, HomeState>(
        're-initializes when refresh is called',
        build: () => homeCubit,
        seed: () => const HomeState(
          isLoading: false,
          welcomeMessage: 'Previous message',
        ),
        act: (HomeCubit cubit) => cubit.refresh(),
        wait: const Duration(milliseconds: 600),
        expect: () => <HomeState>[
          const HomeState(isLoading: true, welcomeMessage: 'Previous message'),
          const HomeState(
            isLoading: false,
            welcomeMessage: 'Welcome to the app!',
          ),
        ],
      );
    });
  });
}
