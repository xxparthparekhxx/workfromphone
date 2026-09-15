import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
      expect(find.text('Open a project'), findsOneWidget);
      expect(find.text('Browse folders'), findsOneWidget);

      // 2. Switch to Assistant (General Chat) tab
      final assistantNavDestination = find.byIcon(CupertinoIcons.sparkles);
      expect(assistantNavDestination, findsOneWidget);
      await tester.tap(assistantNavDestination);
      await tester.pumpAndSettle();

      expect(find.text('Ask anything'), findsWidgets);
      final webSearchChip = find.byKey(
        const Key('general-chat-web-search-chip'),
      );
      expect(tester.widget<FilterChip>(webSearchChip).selected, isFalse);

      // 3. Switch to Settings tab
      final settingsNavDestination = find.byIcon(CupertinoIcons.settings);
      expect(settingsNavDestination, findsOneWidget);
      await tester.tap(settingsNavDestination);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
      expect(find.text('BACKEND'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('AI PROVIDER'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('AI PROVIDER'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('CLOUD HUB · OPTIONAL'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('CLOUD HUB · OPTIONAL'), findsOneWidget);

      // 4. Switch back to Projects tab
      final projectsNavDestination = find.byIcon(CupertinoIcons.folder);
      expect(projectsNavDestination, findsOneWidget);
      await tester.tap(projectsNavDestination);
      await tester.pumpAndSettle();

      expect(find.text('Open a project'), findsOneWidget);
    },
  );
}
