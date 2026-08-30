import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfromphone/utils/tokyo_night_theme.dart';
import 'package:workfromphone/widgets/code_editor_view.dart';

void main() {
  testWidgets(
    'CodeEditorView displays line numbers and Tokyo Night styled text',
    (WidgetTester tester) async {
      final controller = TokyoNightCodeController(
        text: 'import "dart:async";\n\nvoid main() {\n  print("Hello World!");\n}',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CodeEditorView(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      // Verify line numbers gutter exists (5 lines)
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      // Verify Tokyo Night label & line counter
      expect(find.text('Tokyo Night'), findsOneWidget);
      expect(find.text('5 lines'), findsOneWidget);
    },
  );

  test('TokyoNightCodeController builds syntax token spans', () {
    final controller = TokyoNightCodeController(
      text: '// comment\nimport "package:http/http.dart";\nclass MyService {}\nfinal int x = 42;',
    );

    final span = controller.buildTextSpan(
      context: DummyBuildContext(),
      withComposing: false,
    );

    expect(span.children, isNotEmpty);
  });
}

class DummyBuildContext extends Fake implements BuildContext {}
