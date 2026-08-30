import 'package:workfromphone/models/tool_event.dart';

enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  String content;
  final String? apiContent;
  final List<ToolEvent> toolEvents;
  final DateTime timestamp;
  bool isStreaming;
  String? statusMessage;
  bool isError;

  ChatMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.apiContent,
    List<ToolEvent>? toolEvents,
    DateTime? timestamp,
    this.isStreaming = false,
    this.statusMessage,
    this.isError = false,
  }) : toolEvents = toolEvents ?? [],
       timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toApiMessage() {
    return {
      'role': role == MessageRole.user
          ? 'user'
          : role == MessageRole.assistant
          ? 'assistant'
          : 'system',
      'content': apiContent ?? content,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'content': content,
      'tool_events': toolEvents.map((e) => e.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
      'is_error': isError,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    MessageRole parseRole(String? r) {
      switch (r) {
        case 'user':
          return MessageRole.user;
        case 'assistant':
          return MessageRole.assistant;
        case 'system':
          return MessageRole.system;
        default:
          return MessageRole.user;
      }
    }

    return ChatMessage(
      id:
          json['id'] as String? ??
          'msg_${DateTime.now().millisecondsSinceEpoch}',
      role: parseRole(json['role'] as String?),
      content: json['content'] as String? ?? '',
      toolEvents: ((json['tool_events'] as List<dynamic>?) ?? [])
          .map((e) => ToolEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      isStreaming: false,
      isError: json['is_error'] as bool? ?? false,
    );
  }
}
