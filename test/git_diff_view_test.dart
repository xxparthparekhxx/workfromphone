import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfromphone/widgets/git_diff_view.dart';

void main() {
  const sampleDiff = '''
diff --git a/lib/main.dart b/lib/main.dart
index 1234567..89abcdef 100644
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -10,5 +10,6 @@
 void main() {
-  print("Old message");
+  print("New message");
+  print("Added line");
 }
''';

  test('GitDiffParser parses hunk headers, old line numbers, and new line numbers correctly', () {
    final lines = GitDiffParser.parse(sampleDiff);

    // Filter by type
    final hunk = lines.firstWhere((l) => l.type == DiffLineType.hunk);
    expect(hunk.text, contains('@@ -10,5 +10,6 @@'));

    final deletion = lines.firstWhere((l) => l.type == DiffLineType.deletion);
    expect(deletion.oldLineNum, 11);
    expect(deletion.newLineNum, isNull);
    expect(deletion.text, contains('-  print("Old message");'));

    final addition1 = lines.firstWhere(
      (l) => l.type == DiffLineType.addition && l.text.contains('New message'),
    );
    expect(addition1.oldLineNum, isNull);
    expect(addition1.newLineNum, 11);

    final addition2 = lines.firstWhere(
      (l) => l.type == DiffLineType.addition && l.text.contains('Added line'),
    );
    expect(addition2.oldLineNum, isNull);
    expect(addition2.newLineNum, 12);
  });

  testWidgets('GitDiffView renders diff line numbers and styled text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GitDiffView(rawDiff: sampleDiff)),
      ),
    );
    await tester.pumpAndSettle();

    // Verify legend header
    expect(find.text('OLD'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);

    // Verify line numbers in gutter
    expect(find.text('10'), findsWidgets);
    expect(find.text('11'), findsWidgets);
    expect(find.text('12'), findsWidgets);

    // Verify diff content
    expect(find.textContaining('Old message'), findsOneWidget);
    expect(find.textContaining('New message'), findsOneWidget);
  });
}
