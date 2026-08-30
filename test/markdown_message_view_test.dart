import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfromphone/widgets/markdown_message_view.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

void main() {
  group('MarkdownMessageView Tests', () {
    testWidgets('renders basic markdown text properly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownMessageView(
              data: '# Title\nThis is **bold** text and `inline code`.',
              isUser: false,
            ),
          ),
        ),
      );

      expect(find.byType(MarkdownMessageView), findsOneWidget);
      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('renders code blocks and user message styling', (
      WidgetTester tester,
    ) async {
      const codeSnippet =
          '```dart\nvoid main() {\n  print("Hello World!");\n}\n```';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownMessageView(
              data: 'Here is some code:\n$codeSnippet',
              isUser: true,
              isStreaming: false,
            ),
          ),
        ),
      );

      expect(find.byType(MarkdownMessageView), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('renders lists and tables without crashing', (
      WidgetTester tester,
    ) async {
      const tableAndList = '''
- Item 1
- Item 2
- Item 3

| Header 1 | Header 2 |
| --- | --- |
| Cell 1 | Cell 2 |
''';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownMessageView(data: tableAndList, isUser: false),
          ),
        ),
      );

      expect(find.byType(MarkdownMessageView), findsOneWidget);
    });
  });
}
