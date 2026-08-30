import 'package:workfromphone/models/chat_message.dart';
import 'package:workfromphone/models/task_stats.dart';

class ConversationSession {
  final String id;
  final String projectPath;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  String model;
  final List<ChatMessage> messages;
  final TaskStats stats;

  ConversationSession({
    required this.id,
    required this.projectPath,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.model,
    List<ChatMessage>? messages,
    this.stats = const TaskStats(),
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       messages = messages ?? [];

  String get previewSnippet {
    if (messages.isEmpty) return 'No messages yet';
    final last = messages.last;
    if (last.content.isNotEmpty) {
      final clean = last.content.replaceAll('\n', ' ').trim();
      return clean.length > 80 ? '${clean.substring(0, 80)}...' : clean;
    }
    if (last.toolEvents.isNotEmpty) {
      return last.toolEvents.last.summary;
    }
    return 'Task in progress...';
  }

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(updatedAt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${updatedAt.month}/${updatedAt.day}/${updatedAt.year}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'project_path': projectPath,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stats': stats.toJson(),
    };
  }

  factory ConversationSession.fromJson(Map<String, dynamic> json) {
    return ConversationSession(
      id:
          json['id'] as String? ??
          'conv_${DateTime.now().millisecondsSinceEpoch}',
      projectPath: json['project_path'] as String? ?? '',
      title: json['title'] as String? ?? 'New Conversation',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      model: json['model'] as String? ?? 'anthropic/claude-3.7-sonnet',
      messages: ((json['messages'] as List<dynamic>?) ?? [])
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList(),
      stats: json['stats'] != null
          ? TaskStats.fromJson(json['stats'] as Map<String, dynamic>)
          : const TaskStats(),
    );
  }

  ConversationSession copyWith({
    String? id,
    String? projectPath,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? model,
    List<ChatMessage>? messages,
    TaskStats? stats,
  }) {
    return ConversationSession(
      id: id ?? this.id,
      projectPath: projectPath ?? this.projectPath,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      model: model ?? this.model,
      messages: messages ?? this.messages,
      stats: stats ?? this.stats,
    );
  }
}
