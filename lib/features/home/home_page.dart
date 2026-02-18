import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/l10n/generated/app_localizations.dart';
import 'bloc/home_cubit.dart';

/// The home screen of the application.
///
/// This screen serves as the main entry point and can be customized
/// to display whatever content is appropriate for your app.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<HomeCubit>(
      create: (BuildContext context) => HomeCubit()..initialize(),
      child: const HomeView(),
    );
  }
}

/// The actual view/widget for the home screen.
///
/// Separating the view from the page allows for better testing
/// and reusability.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeTitle)),
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (BuildContext context, HomeState state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    state.welcomeMessage.isNotEmpty
                        ? state.welcomeMessage
                        : l10n.homeWelcome,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text('Home Screen'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
