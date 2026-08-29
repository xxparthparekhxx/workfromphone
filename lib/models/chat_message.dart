import 'package:workfromphone/models/tool_event.dart';

enum MessageRole {
  user,
  assistant,
  system,
}

class ChatMessage {
  final String id;
  final MessageRole role;
  String content;
  final List<ToolEvent> toolEvents;
  final DateTime timestamp;
  bool isStreaming;
  String? statusMessage;
  bool isError;

  ChatMessage({
    required this.id,
    required this.role,
    this.content = '',
    List<ToolEvent>? toolEvents,
    DateTime? timestamp,
    this.isStreaming = false,
    this.statusMessage,
    this.isError = false,
  })  : toolEvents = toolEvents ?? [],
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toApiMessage() {
    return {
      'role': role == MessageRole.user
          ? 'user'
          : role == MessageRole.assistant
              ? 'assistant'
              : 'system',
      'content': content,
    };
  }
}
