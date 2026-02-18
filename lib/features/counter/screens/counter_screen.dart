import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../bloc/counter_cubit.dart';

/// The counter screen.
///
/// DEMO FEATURE: This is a demonstration feature that can be deleted.
/// It shows how to create a feature screen with BLoC/Cubit integration.
///
/// This screen demonstrates:
/// - Setting up a BlocProvider
/// - Using BlocBuilder to react to state changes
/// - Implementing user interactions that call cubit methods
/// - Building a proper UI with Material Design
///
/// To remove this feature:
/// 1. Delete the `/lib/features/counter` directory
/// 2. Remove the counter route from `lib/core/router/app_router.dart`
/// 3. Remove any navigation references to the counter screen
class CounterScreen extends StatelessWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CounterCubit>(
      create: (BuildContext context) => CounterCubit(),
      child: const CounterView(),
    );
  }
}

/// The actual view/widget for the counter screen.
///
/// Separating the view from the page allows for better testing
/// and reusability.
class CounterView extends StatelessWidget {
  const CounterView({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.counterTitle)),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                l10n.counterDescription,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Text(
                '${l10n.count}:',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              BlocBuilder<CounterCubit, CounterState>(
                builder: (BuildContext context, CounterState state) {
                  return Text(
                    '${state.count}',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  FloatingActionButton(
                    heroTag: 'decrement',
                    onPressed: () => context.read<CounterCubit>().decrement(),
                    child: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton(
                    heroTag: 'increment',
                    onPressed: () => context.read<CounterCubit>().increment(),
                    child: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => context.read<CounterCubit>().reset(),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.reset),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
