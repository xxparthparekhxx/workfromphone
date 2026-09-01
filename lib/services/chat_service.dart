import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:workfromphone/models/chat_message.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/models/token_usage.dart';
import 'package:workfromphone/services/api_service.dart';

class ChatService {
  http.Client? _client;
  bool _isCancelled = false;

  void cancel() {
    _isCancelled = true;
    _client?.close();
    _client = null;
  }

  Future<void> runTask({
    required String backendUrl,
    required String projectPath,
    required List<ChatMessage> messages,
    required LLMConfig llmConfig,
    required Function(String status) onStatus,
    required Function(String chunk) onChunk,
    required Function(String toolName, Map<String, dynamic> args)
    onToolCallStart,
    required Function(String toolName, String output) onToolCallResult,
    required Function(TokenUsage usage) onUsage,
    required Function(int? steps) onDone,
    required Function(String error) onError,
  }) async {
    _isCancelled = false;
    _client = http.Client();

    final base = ApiService.cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/llm/chat');

    final payload = {
      'project_path': projectPath,
      'messages': messages.map((m) => m.toApiMessage()).toList(),
      'llm_config': llmConfig.toJson(),
    };
    var receivedTerminalEvent = false;

    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(ApiService.headers(json: true, uri: uri))
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode(payload);

      final response = await _client!.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        onError('Server returned ${response.statusCode}: $body');
        return;
      }

      String buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        if (_isCancelled) break;
        buffer += chunk;

        final lines = buffer.split('\n');
        buffer = lines.removeLast(); // keep incomplete tail

        for (final rawLine in lines) {
          final line = rawLine.trim();
          if (!line.startsWith('data:')) continue;

          final jsonStr = line.substring(5).trim();
          if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;

          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = data['type'] as String?;

            if (type == 'status') {
              onStatus(data['content'] as String? ?? 'Processing...');
            } else if (type == 'chunk') {
              onChunk(data['content'] as String? ?? '');
            } else if (type == 'tool_call_start') {
              final tool = data['tool'] as String? ?? 'tool';
              final args = (data['args'] as Map<String, dynamic>?) ?? {};
              onToolCallStart(tool, args);
            } else if (type == 'tool_call_result') {
              final tool = data['tool'] as String? ?? 'tool';
              final output = data['output'] as String? ?? '';
              onToolCallResult(tool, output);
            } else if (type == 'usage') {
              final usage = data['usage'];
              if (usage is Map<String, dynamic>) {
                onUsage(TokenUsage.fromJson(usage));
              }
            } else if (type == 'done') {
              receivedTerminalEvent = true;
              onDone(data['total_steps'] as int?);
            } else if (type == 'error') {
              receivedTerminalEvent = true;
              onError(
                data['message'] as String? ??
                    'An error occurred during execution',
              );
            }
          } catch (_) {
            // Ignore malformed partial chunks
          }
        }
      }

      if (!_isCancelled && !receivedTerminalEvent) {
        onDone(null);
      }
    } catch (e) {
      if (!_isCancelled) {
        onError('Connection error: $e');
      }
    } finally {
      _client?.close();
      _client = null;
    }
  }
}
