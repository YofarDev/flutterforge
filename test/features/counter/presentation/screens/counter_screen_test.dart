import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_flutter_app/core/l10n/app_localization_delegates.dart';
import 'package:my_flutter_app/core/l10n/generated/app_localizations.dart';
import 'package:my_flutter_app/features/counter/data/models/counter_settings_dto.dart';
import 'package:my_flutter_app/features/counter/data/repositories/counter_repository_impl.dart';
import 'package:my_flutter_app/features/counter/domain/services/counter_service.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_cubit.dart';
import 'package:my_flutter_app/features/counter/presentation/screens/counter_screen.dart';

import '../../../../support/fake_counter_data_source.dart';

/// Behavior tests for the counter UI driven by a real CounterCubit, real
/// CounterService and real repository over a fake persistence seam.
void main() {
  group('CounterView', () {
    late CounterCubit counterCubit;

    setUp(() {
      counterCubit = CounterCubit(
        CounterService(
          CounterRepository(
            FakeCounterLocalDataSource(const CounterSettingsDto()),
          ),
        ),
      );
    });

    tearDown(() {
      counterCubit.close();
    });

    Widget buildTestableWidget(Widget child) {
      return MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<CounterCubit>.value(
          value: counterCubit,
          child: child,
        ),
      );
    }

    testWidgets('starts at 0 and increments when + is tapped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const CounterView()));
      expect(find.text('0'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('decrements count when - button is tapped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const CounterView()));

      // First increment to have a positive number
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Then decrement
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('resets count when reset button is tapped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(const CounterView()));

      // Increment a few times
      await tester.tap(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);

      // Reset
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
    });
  });
}
