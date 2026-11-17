import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/l10n/failure_localization.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/models/failure.dart';
import '../../../../core/router/route_constants.dart';
import '../bloc/home_cubit.dart';
import '../bloc/home_state.dart';

/// The route provides [HomeCubit]; this screen only consumes it.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).homeTitle)),
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (BuildContext context, HomeState state) {
          return state.when(
            initial: () => const Center(child: CircularProgressIndicator()),
            loading: () => const Center(child: CircularProgressIndicator()),
            loaded: (String welcomeMessage) =>
                HomeContent(welcomeMessage: welcomeMessage),
            failure: (Failure failure) => HomeError(failure: failure),
          );
        },
      ),
    );
  }
}

class HomeContent extends StatelessWidget {
  const HomeContent({super.key, required this.welcomeMessage});

  final String welcomeMessage;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Presentation decision: blank messages fall back to localized copy.
    final String trimmedMessage = welcomeMessage.trim();

    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              trimmedMessage.isNotEmpty ? trimmedMessage : l10n.homeWelcome,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(l10n.homeSubtitle),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.push(Routes.counter),
              icon: const Icon(Icons.arrow_forward),
              label: Text(l10n.tryCounterDemo),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.counterDemoDescription,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeError extends StatelessWidget {
  const HomeError({super.key, required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            localizeFailure(l10n, failure),
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => context.read<HomeCubit>().refresh(),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}
