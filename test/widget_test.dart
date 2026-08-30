import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Bottom navigation and Projects / Settings screens smoke test', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Verify Projects tab is active and shows hero card
    expect(find.text('Projects'), findsWidgets);
    expect(find.text('Work on PC Project'), findsOneWidget);
    expect(find.text('Browse & Select Project Directory'), findsOneWidget);

    // Switch to Settings tab
    final settingsNavDestination = find.byIcon(CupertinoIcons.settings);
    expect(settingsNavDestination, findsOneWidget);
    await tester.tap(settingsNavDestination);
    await tester.pumpAndSettle();

    // Verify Settings content
    expect(find.text('Settings & Harness'), findsOneWidget);
    expect(find.text('PC Backend Connection'), findsOneWidget);
    expect(find.text('LLM Provider & Router'), findsOneWidget);
    expect(find.text('Selected Model ID'), findsOneWidget);

    // Switch back to Projects tab
    final projectsNavDestination = find.byIcon(CupertinoIcons.folder);
    expect(projectsNavDestination, findsOneWidget);
    await tester.tap(projectsNavDestination);
    await tester.pumpAndSettle();

    // Verify back on Projects tab
    expect(find.text('Work on PC Project'), findsOneWidget);
  });
}
