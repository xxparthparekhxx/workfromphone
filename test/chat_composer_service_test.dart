import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfromphone/models/chat_message.dart';
import 'package:workfromphone/services/chat_composer_service.dart';

void main() {
  test('parses known slash commands and expands prompt commands', () {
    final parsed = ChatComposerService.parseSlashCommand(
      '/test only the backend',
    );

    expect(parsed, isNotNull);
    expect(parsed!.command?.name, 'test');
    expect(parsed.arguments, 'only the backend');
    expect(
      parsed.command!.expand(parsed.arguments),
      contains('Additional instructions: only the backend'),
    );
  });

  test('reports unknown slash commands without treating text as a prompt', () {
    final parsed = ChatComposerService.parseSlashCommand('/does-not-exist');

    expect(parsed, isNotNull);
    expect(parsed!.name, 'does-not-exist');
    expect(parsed.command, isNull);
  });

  test('suggests slash commands at the start of the composer', () {
    const value = TextEditingValue(
      text: '/mo',
      selection: TextSelection.collapsed(offset: 3),
    );

    final suggestions = ChatComposerService.commandSuggestions(value);

    expect(suggestions.map((command) => command.name), ['model']);
  });

  test('finds and normalizes unique project file mentions', () {
    final mentions = ChatComposerService.extractFileMentions(
      'Compare @lib/main.dart with @./test/widget_test.dart and '
      '@lib/main.dart, but ignore me@example.com and @../secret.',
    );

    expect(mentions, ['lib/main.dart', 'test/widget_test.dart']);
  });

  test('builds API-only instructions for referenced files', () {
    const visible = 'Explain @lib/main.dart';
    final apiContent = ChatComposerService.buildApiContent(visible);
    final message = ChatMessage(
      id: 'mention',
      role: MessageRole.user,
      content: visible,
      apiContent: apiContent,
    );

    expect(apiContent, startsWith(visible));
    expect(apiContent, contains('- `lib/main.dart`'));
    expect(apiContent, contains('Use the read_file tool'));
    expect(message.content, visible);
    expect(message.toApiMessage()['content'], apiContent);
    expect(message.toJson()['content'], visible);
  });

  test('locates the active mention at the cursor', () {
    const value = TextEditingValue(
      text: 'Review @lib/ma',
      selection: TextSelection.collapsed(offset: 14),
    );

    final trigger = ChatComposerService.mentionTrigger(value);

    expect(trigger, isNotNull);
    expect(trigger!.query, 'lib/ma');
    expect(trigger.start, 7);
    expect(trigger.end, 14);
  });
}
