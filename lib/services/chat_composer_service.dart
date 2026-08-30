import 'package:flutter/services.dart';

enum ChatCommandAction {
  sendPrompt,
  showHelp,
  newConversation,
  chooseModel,
  stopTask,
  openPreview,
}

class ChatSlashCommand {
  final String name;
  final String description;
  final ChatCommandAction action;
  final String? prompt;

  const ChatSlashCommand({
    required this.name,
    required this.description,
    required this.action,
    this.prompt,
  });

  String expand(String arguments) {
    final base = prompt ?? '';
    final details = arguments.trim();
    return details.isEmpty
        ? base
        : '$base\n\nAdditional instructions: $details';
  }
}

class ParsedChatCommand {
  final String name;
  final String arguments;
  final ChatSlashCommand? command;

  const ParsedChatCommand({
    required this.name,
    required this.arguments,
    required this.command,
  });
}

class FileMentionTrigger {
  final int start;
  final int end;
  final String query;

  const FileMentionTrigger({
    required this.start,
    required this.end,
    required this.query,
  });
}

class ChatComposerService {
  static const commands = <ChatSlashCommand>[
    ChatSlashCommand(
      name: 'help',
      description: 'Show available commands',
      action: ChatCommandAction.showHelp,
    ),
    ChatSlashCommand(
      name: 'commands',
      description: 'Show available commands',
      action: ChatCommandAction.showHelp,
    ),
    ChatSlashCommand(
      name: 'new',
      description: 'Start a new conversation',
      action: ChatCommandAction.newConversation,
    ),
    ChatSlashCommand(
      name: 'model',
      description: 'Choose the model for this chat',
      action: ChatCommandAction.chooseModel,
    ),
    ChatSlashCommand(
      name: 'stop',
      description: 'Stop the current task',
      action: ChatCommandAction.stopTask,
    ),
    ChatSlashCommand(
      name: 'analyze',
      description: 'Analyze the project structure',
      action: ChatCommandAction.sendPrompt,
      prompt: 'Analyze this project and explain its structure and purpose.',
    ),
    ChatSlashCommand(
      name: 'test',
      description: 'Run the project test suite',
      action: ChatCommandAction.sendPrompt,
      prompt: 'Run the test suite in this project and report the results.',
    ),
    ChatSlashCommand(
      name: 'git',
      description: 'Summarize the current Git status',
      action: ChatCommandAction.sendPrompt,
      prompt: 'Check Git status and summarize the modified files.',
    ),
    ChatSlashCommand(
      name: 'lint',
      description: 'Find syntax and lint errors',
      action: ChatCommandAction.sendPrompt,
      prompt: 'Check the project for syntax, analysis, and lint errors.',
    ),
    ChatSlashCommand(
      name: 'preview',
      description: 'Manually register a local dev server port',
      action: ChatCommandAction.openPreview,
      prompt: '',
    ),
  ];

  static ParsedChatCommand? parseSlashCommand(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith('/')) return null;

    final match = RegExp(r'^/([a-zA-Z][\w-]*)(?:\s+([\s\S]*))?$')
        .firstMatch(trimmed);
    if (match == null) {
      return const ParsedChatCommand(name: '', arguments: '', command: null);
    }

    final name = match.group(1)!.toLowerCase();
    final definition = commands.where((item) => item.name == name).firstOrNull;
    return ParsedChatCommand(
      name: name,
      arguments: match.group(2)?.trim() ?? '',
      command: definition,
    );
  }

  static List<ChatSlashCommand> commandSuggestions(
    TextEditingValue value, {
    int limit = 6,
  }) {
    final cursor = value.selection.baseOffset;
    if (cursor < 0 || cursor > value.text.length) return const [];

    final beforeCursor = value.text.substring(0, cursor).trimLeft();
    if (!beforeCursor.startsWith('/') || beforeCursor.contains(RegExp(r'\s'))) {
      return const [];
    }

    final query = beforeCursor.substring(1).toLowerCase();
    return commands
        .where((command) => command.name.startsWith(query))
        .take(limit)
        .toList();
  }

  static FileMentionTrigger? mentionTrigger(TextEditingValue value) {
    final cursor = value.selection.baseOffset;
    if (cursor < 0 || cursor > value.text.length) return null;

    final beforeCursor = value.text.substring(0, cursor);
    final match = RegExp(r'(?:^|\s)@([a-zA-Z0-9._/-]*)$')
        .firstMatch(beforeCursor);
    if (match == null) return null;

    final fullMatch = match.group(0)!;
    final atOffset = match.start + fullMatch.lastIndexOf('@');
    return FileMentionTrigger(
      start: atOffset,
      end: cursor,
      query: match.group(1) ?? '',
    );
  }

  static List<String> extractFileMentions(String input) {
    final matches = RegExp(r'(?:^|[\s(])@([a-zA-Z0-9._/-]+)').allMatches(input);
    final mentions = <String>[];
    for (final match in matches) {
      final candidate = _normalizeMention(match.group(1) ?? '');
      if (candidate != null && !mentions.contains(candidate)) {
        mentions.add(candidate);
      }
    }
    return mentions;
  }

  static String buildApiContent(String visibleText) {
    final mentions = extractFileMentions(visibleText);
    if (mentions.isEmpty) return visibleText;

    final paths = mentions.map((path) => '- `$path`').join('\n');
    return '''
$visibleText

Referenced project files:
$paths

The user explicitly referenced these project-relative files. Use the read_file tool to inspect them before answering or making changes.''';
  }

  static String? _normalizeMention(String raw) {
    var path = raw;
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    if (path.isEmpty || path.startsWith('/')) return null;
    final segments = path.split('/');
    if (segments.any((segment) => segment.isEmpty || segment == '..')) {
      return null;
    }
    return path;
  }
}
