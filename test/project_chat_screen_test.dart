import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/screens/chat/project_chat_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ProjectChatScreen renders the model picker in the composer', (
    WidgetTester tester,
  ) async {
    final project = ProjectDirectory(
      name: 'test_project',
      path: '/home/user/test_project',
      lastOpened: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(home: ProjectChatScreen(project: project)),
    );
    await tester.pumpAndSettle();

    expect(find.text('test_project'), findsOneWidget);
    expect(find.text('AI Task Harness Ready'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('chat-model-picker')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('chat-model-picker')),
      ),
      findsNothing,
    );
  });

  testWidgets('ProjectChatScreen suggests and handles slash commands', (
    WidgetTester tester,
  ) async {
    final project = ProjectDirectory(
      name: 'test_project',
      path: '/home/user/test_project',
      lastOpened: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(home: ProjectChatScreen(project: project)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat-input')), '/');
    await tester.pump();
    expect(find.byKey(const Key('chat-composer-suggestions')), findsOneWidget);
    expect(find.text('/help'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chat-input')), '/help');
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pumpAndSettle();
    expect(find.text('Chat commands'), findsOneWidget);
    expect(find.text('/model'), findsOneWidget);
  });
}
