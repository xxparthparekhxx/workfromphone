import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/models/chat_message.dart';
import 'package:workfromphone/models/conversation_session.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/models/task_stats.dart';
import 'package:workfromphone/screens/chat/conversation_history_sheet.dart';
import 'package:workfromphone/services/storage_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ConversationSession serialization and formatting', () {
    final session = ConversationSession(
      id: 'conv_123',
      projectPath: '/home/user/app',
      title: 'Fix App Navigation',
      model: 'anthropic/claude-3.7-sonnet',
      messages: [
        ChatMessage(
          id: '1',
          role: MessageRole.user,
          content: 'Can you fix the router and tabs?',
        ),
        ChatMessage(
          id: '2',
          role: MessageRole.assistant,
          content: 'Sure! I will update the project route configuration.',
        ),
      ],
      stats: const TaskStats(totalTokens: 1200),
    );

    final json = session.toJson();
    final restored = ConversationSession.fromJson(json);

    expect(restored.id, 'conv_123');
    expect(restored.title, 'Fix App Navigation');
    expect(restored.messages.length, 2);
    expect(restored.previewSnippet, contains('update the project route'));
    expect(restored.formattedTime, isNotEmpty);
  });

  test('StorageService persists and retrieves multiple conversations per project', () async {
    const projectPath = '/home/user/my_project';

    final session1 = ConversationSession(
      id: 'conv_1',
      projectPath: projectPath,
      title: 'Setup Database',
      model: 'anthropic/claude-3.7-sonnet',
    );

    final session2 = ConversationSession(
      id: 'conv_2',
      projectPath: projectPath,
      title: 'Refactor UI',
      model: 'google/gemini-2.0-flash',
    );

    await StorageService.saveConversation(projectPath, session1);
    await StorageService.saveConversation(projectPath, session2);
    await StorageService.saveActiveConversationId(projectPath, 'conv_2');

    final list = await StorageService.loadConversations(projectPath);
    expect(list.length, 2);

    final activeId = await StorageService.loadActiveConversationId(projectPath);
    expect(activeId, 'conv_2');

    await StorageService.deleteConversation(projectPath, 'conv_1');
    final afterDelete = await StorageService.loadConversations(projectPath);
    expect(afterDelete.length, 1);
    expect(afterDelete.first.id, 'conv_2');
  });

  testWidgets('ConversationHistorySheet renders conversations list and handles selection', (WidgetTester tester) async {
    final project = ProjectDirectory(
      name: 'flutter_app',
      path: '/home/user/flutter_app',
      lastOpened: DateTime.now(),
    );

    final session = ConversationSession(
      id: 'conv_abc',
      projectPath: project.path,
      title: 'Implement Dark Theme',
      model: 'anthropic/claude-3.7-sonnet',
      messages: [
        ChatMessage(id: '1', role: MessageRole.user, content: 'Add dark mode theme support'),
      ],
    );

    await StorageService.saveConversation(project.path, session);

    ConversationSession? selectedSession;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationHistorySheet(
            project: project,
            activeConversationId: 'conv_abc',
            onSelectConversation: (s) => selectedSession = s,
            onNewConversation: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify header and new chat button
    expect(find.text('Conversations'), findsOneWidget);
    expect(find.text('New Chat'), findsOneWidget);

    // Verify conversation card with active indicator
    expect(find.text('Implement Dark Theme'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('Add dark mode theme support'), findsOneWidget);

    // Tap on the conversation card
    await tester.tap(find.text('Implement Dark Theme'));
    await tester.pumpAndSettle();

    expect(selectedSession, isNotNull);
    expect(selectedSession!.id, 'conv_abc');
  });

  testWidgets('ConversationHistorySheet triggers new conversation callback', (WidgetTester tester) async {
    final project = ProjectDirectory(
      name: 'flutter_app',
      path: '/home/user/flutter_app',
      lastOpened: DateTime.now(),
    );

    bool newConversationTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationHistorySheet(
            project: project,
            activeConversationId: null,
            onSelectConversation: (_) {},
            onNewConversation: () => newConversationTriggered = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap New Chat
    await tester.tap(find.text('New Chat'));
    await tester.pumpAndSettle();
    expect(newConversationTriggered, isTrue);
  });
}
