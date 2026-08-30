import 'package:workfromphone/models/tool_event.dart';

enum MessageRole { user, assistant, system }

sealed class ChatElement {
  const ChatElement();

  Map<String, dynamic> toJson();

  factory ChatElement.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == 'tool') {
      return ToolChatElement.fromJson(json);
    }
    return TextChatElement.fromJson(json);
  }
}

class TextChatElement extends ChatElement {
  String text;

  TextChatElement(this.text);

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'text', 'text': text};
  }

  factory TextChatElement.fromJson(Map<String, dynamic> json) {
    return TextChatElement(json['text'] as String? ?? '');
  }
}

class ToolChatElement extends ChatElement {
  final ToolEvent event;

  ToolChatElement(this.event);

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'tool', 'event': event.toJson()};
  }

  factory ToolChatElement.fromJson(Map<String, dynamic> json) {
    final rawEvent = json['event'];
    if (rawEvent is Map<String, dynamic>) {
      return ToolChatElement(ToolEvent.fromJson(rawEvent));
    }
    return ToolChatElement(ToolEvent.fromJson(json));
  }
}

class ChatMessage {
  final String id;
  final MessageRole role;
  final List<ChatElement> elements;
  final String? apiContent;
  final DateTime timestamp;
  bool isStreaming;
  String? statusMessage;
  bool isError;

  ChatMessage({
    required this.id,
    required this.role,
    String content = '',
    this.apiContent,
    List<ToolEvent>? toolEvents,
    List<ChatElement>? elements,
    DateTime? timestamp,
    this.isStreaming = false,
    this.statusMessage,
    this.isError = false,
  }) : elements = elements ?? [],
       timestamp = timestamp ?? DateTime.now() {
    if (elements == null) {
      if (toolEvents != null && toolEvents.isNotEmpty) {
        for (final t in toolEvents) {
          this.elements.add(ToolChatElement(t));
        }
      }
      if (content.isNotEmpty) {
        this.elements.add(TextChatElement(content));
      }
    }
  }

  /// Combined text content of all text elements in this message.
  String get content {
    return elements
        .whereType<TextChatElement>()
        .map((e) => e.text)
        .join('\n\n');
  }

  set content(String val) {
    final textElements = elements.whereType<TextChatElement>().toList();
    if (textElements.isNotEmpty) {
      textElements.first.text = val;
    } else {
      elements.add(TextChatElement(val));
    }
  }

  /// All tool events in this message.
  List<ToolEvent> get toolEvents {
    return elements.whereType<ToolChatElement>().map((e) => e.event).toList();
  }

  /// Appends streaming text to the current trailing text element, or creates a new one.
  void appendChunk(String chunk) {
    if (elements.isNotEmpty && elements.last is TextChatElement) {
      (elements.last as TextChatElement).text += chunk;
    } else {
      elements.add(TextChatElement(chunk));
    }
  }

  /// Appends a new tool event in chronological order.
  void addToolEvent(ToolEvent event) {
    elements.add(ToolChatElement(event));
  }

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
      'elements': elements.map((e) => e.toJson()).toList(),
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

    final rawElements = json['elements'] as List<dynamic>?;
    List<ChatElement>? parsedElements;
    if (rawElements != null && rawElements.isNotEmpty) {
      parsedElements = rawElements
          .map((e) => ChatElement.fromJson(e as Map<String, dynamic>))
          .toList();
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
      elements: parsedElements,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      isStreaming: false,
      isError: json['is_error'] as bool? ?? false,
    );
  }
}
