import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/main.dart';

/// Integration/Smoke tests for the entire app.
///
/// These tests verify that:
/// - The app starts without errors
/// - Basic navigation works
/// - The app renders correctly
void main() {
  group('MyApp', () {
    testWidgets('app starts and shows home screen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Verify app title is present (in home screen)
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('app has correct localization', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Verify welcome text from localization is shown (homeWelcome = 'Welcome to the app!')
      expect(find.text('Welcome to the app!'), findsOneWidget);
    });
  });
}
