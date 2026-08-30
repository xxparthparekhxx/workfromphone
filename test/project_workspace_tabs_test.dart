import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/screens/chat/project_chat_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ProjectChatScreen renders 5 tabs and switches properly', (
    WidgetTester tester,
  ) async {
    final project = ProjectDirectory(
      name: 'my_flutter_app',
      path: '/home/user/my_flutter_app',
      lastOpened: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(home: ProjectChatScreen(project: project)),
    );
    await tester.pumpAndSettle();

    // Verify all workspace tabs exist in TabBar
    expect(find.byType(Tab), findsNWidgets(6));
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.chat_bubble),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.command),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.folder),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.doc_plaintext),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.heart),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.globe),
      ),
      findsOneWidget,
    );

    // Initial Chat view
    expect(find.text('AI Task Harness Ready'), findsOneWidget);

    // Switch to Terminal tab
    await tester.tap(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.command),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terminal-tab-bar')), findsOneWidget);
    expect(find.byKey(const Key('terminal-tab-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-accessory-bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('terminal-add-tab')));
    await tester.pump();
    expect(find.byKey(const Key('terminal-tab-2')), findsOneWidget);
    expect(find.textContaining('SSH: 127.0.0.1'), findsNothing);
    expect(find.text('git status'), findsNothing);

    // Switch to Files tab
    await tester.tap(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.folder),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('file-upload-button')), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.doc_text), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.folder_fill_badge_plus), findsOneWidget);

    // Switch to Git tab
    await tester.tap(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.doc_plaintext),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TabBarView), findsOneWidget);

    // Switch to System tab. It renders token usage while metrics connect.
    await tester.tap(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.heart),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('system-monitor-tab')), findsOneWidget);

    // Switch to Preview tab. It renders the empty state until a backend
    // registers an entry.
    await tester.tap(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.byIcon(CupertinoIcons.globe),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-empty-state')), findsOneWidget);
    expect(find.byKey(const Key('preview-list')), findsNothing);
  });
}
