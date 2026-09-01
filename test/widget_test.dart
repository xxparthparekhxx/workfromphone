import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Bottom navigation switches between Projects, Assistant, and Settings screens',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // 1. Verify Projects tab is initially active
      expect(find.text('Projects'), findsWidgets);
      expect(find.text('Work on PC Project'), findsOneWidget);
      expect(find.text('Browse & Select Project Directory'), findsOneWidget);

      // 2. Switch to Assistant (General Chat) tab
      final assistantNavDestination = find.byIcon(CupertinoIcons.sparkles);
      expect(assistantNavDestination, findsOneWidget);
      await tester.tap(assistantNavDestination);
      await tester.pumpAndSettle();

      expect(find.text('AI General Assistant'), findsOneWidget);
      expect(find.text('Web Search OFF'), findsOneWidget);

      // 3. Switch to Settings tab
      final settingsNavDestination = find.byIcon(CupertinoIcons.settings);
      expect(settingsNavDestination, findsOneWidget);
      await tester.tap(settingsNavDestination);
      await tester.pumpAndSettle();

      expect(find.text('Settings & Harness'), findsOneWidget);
      expect(find.text('PC Backend Connection'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Dedicated Cloud Hub (Optional)'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Dedicated Cloud Hub (Optional)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('LLM Provider & Router'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('LLM Provider & Router'), findsOneWidget);

      // 4. Switch back to Projects tab
      final projectsNavDestination = find.byIcon(CupertinoIcons.folder);
      expect(projectsNavDestination, findsOneWidget);
      await tester.tap(projectsNavDestination);
      await tester.pumpAndSettle();

      expect(find.text('Work on PC Project'), findsOneWidget);
    },
  );
}
