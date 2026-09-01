import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:workfromphone/models/chat_message.dart';
import 'package:workfromphone/models/token_usage.dart';
import 'package:workfromphone/services/api_service.dart';

class GeneralChatService {
  static const _defaultRouterBaseUrl = 'https://openrouter.ai/api/v1';

  http.Client? _client;
  bool _isCancelled = false;

  void cancel() {
    _isCancelled = true;
    _client?.close();
    _client = null;
  }

  Future<void> runGeneralChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required double temperature,
    required List<ChatMessage> messages,
    required bool enableWebSearch,
    String backendUrl = '',
    String backendAccessToken = '',
    required Function(String status) onStatus,
    required Function(String chunk) onChunk,
    required Function(TokenUsage usage) onUsage,
    required Function() onDone,
    required Function(String error) onError,
  }) async {
    _isCancelled = false;
    _client = http.Client();

    final trimmedKey = apiKey.trim();
    final routerBaseUrl = _normalizeRouterBaseUrl(baseUrl);
    final backend = backendUrl.trim();

    try {
      if (backend.isNotEmpty) {
        final handled = await _runViaBackend(
          backendUrl: backend,
          backendAccessToken: backendAccessToken,
          routerBaseUrl: routerBaseUrl,
          apiKey: trimmedKey,
          model: model,
          temperature: temperature,
          messages: messages,
          enableWebSearch: enableWebSearch,
          onStatus: onStatus,
          onChunk: onChunk,
          onUsage: onUsage,
          onDone: onDone,
          onError: onError,
        );
        if (handled || _isCancelled) {
          return;
        }
      }

      await _runDirect(
        routerBaseUrl: routerBaseUrl,
        apiKey: trimmedKey,
        backendUrl: backend,
        backendAccessToken: backendAccessToken,
        model: model,
        temperature: temperature,
        messages: messages,
        enableWebSearch: enableWebSearch,
        onStatus: onStatus,
        onChunk: onChunk,
        onUsage: onUsage,
        onDone: onDone,
        onError: onError,
      );
    } catch (e) {
      if (!_isCancelled) {
        onError('Connection failed: $e');
      }
    } finally {
      _client?.close();
      _client = null;
    }
  }

  Future<bool> _runViaBackend({
    required String backendUrl,
    required String backendAccessToken,
    required String routerBaseUrl,
    required String apiKey,
    required String model,
    required double temperature,
    required List<ChatMessage> messages,
    required bool enableWebSearch,
    required Function(String status) onStatus,
    required Function(String chunk) onChunk,
    required Function(TokenUsage usage) onUsage,
    required Function() onDone,
    required Function(String error) onError,
  }) async {
    ApiService.configureAccessToken(backendAccessToken, backendUrl: backendUrl);
    final uri = Uri.parse(
      '${ApiService.cleanUrl(backendUrl)}/api/v1/llm/general',
    );
    final payload = {
      'messages': messages.map((m) => m.toApiMessage()).toList(),
      'llm_config': {
        'base_url': routerBaseUrl,
        'api_key': apiKey,
        'model': model,
        'temperature': temperature,
      },
      'enable_web_search': enableWebSearch,
    };

    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(ApiService.headers(json: true, uri: uri))
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode(payload);

      final response = await _client!.send(request);
      if (_isCancelled) return true;

      // Older backends do not have this route; fall back to a direct router call.
      if (response.statusCode == 404 || response.statusCode == 405) {
        return false;
      }

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        onError(_formatHttpError(response.statusCode, body));
        return true;
      }

      var sawError = false;
      await _consumeSse(response, (data) {
        final type = data['type'] as String?;
        if (type == 'status') {
          final content = data['content'] as String?;
          if (content != null && content.isNotEmpty) {
            onStatus(content);
          }
        } else if (type == 'chunk') {
          final content = data['content'] as String?;
          if (content != null && content.isNotEmpty) {
            onChunk(content);
          }
        } else if (type == 'usage' && data['usage'] is Map<String, dynamic>) {
          onUsage(TokenUsage.fromJson(data['usage'] as Map<String, dynamic>));
        } else if (type == 'error') {
          sawError = true;
          final message = data['message']?.toString() ?? 'Unknown error';
          onError(message);
        }
      });

      if (!_isCancelled && !sawError) {
        onDone();
      }
      return true;
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    } catch (_) {
      if (_isCancelled) return true;
      return false;
    }
  }

  Future<List<Map<String, String>>> _fetchDirectWebSearch(
    String query,
    int limit,
  ) async {
    try {
      final uri = Uri.parse('https://html.duckduckgo.com/html/');
      final resp = await _client!.post(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        body: {'q': query},
      );
      if (resp.statusCode == 200) {
        final text = resp.body;
        final blocks = RegExp(
          r"""<div[^>]+class=["'][^"']*result[^"']*results_links[^"']*["'][^>]*>(.*?)</div>\s*</div>""",
          caseSensitive: false,
          dotAll: true,
        ).allMatches(text);

        final results = <Map<String, String>>[];
        for (final b in blocks) {
          if (results.length >= limit) break;
          final blockText = b.group(1) ?? '';
          final titleMatch = RegExp(
            r"""<a[^>]+class=["'][^"']*result__a[^"']*["'][^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>""",
            caseSensitive: false,
            dotAll: true,
          ).firstMatch(blockText);
          if (titleMatch == null) continue;

          var rawUrl = titleMatch.group(1) ?? '';
          final rawTitle = titleMatch.group(2) ?? '';

          if (rawUrl.contains('duckduckgo.com/y.js')) continue;
          if (rawUrl.contains('uddg=')) {
            final m = RegExp(r'uddg=([^&]+)').firstMatch(rawUrl);
            if (m != null) {
              rawUrl = Uri.decodeComponent(m.group(1)!);
            }
          }

          final cleanTitle = rawTitle.replaceAll(RegExp(r'<[^>]+>'), '').trim();
          var snippet = '';
          final snippetMatch = RegExp(
            r"""<a[^>]+class=["'][^"']*result__snippet[^"']*["'][^>]*>(.*?)</a>""",
            caseSensitive: false,
            dotAll: true,
          ).firstMatch(blockText);
          if (snippetMatch != null) {
            snippet = (snippetMatch.group(1) ?? '')
                .replaceAll(RegExp(r'<[^>]+>'), '')
                .trim();
          }

          if (cleanTitle.isNotEmpty && rawUrl.startsWith('http')) {
            results.add({
              'title': cleanTitle,
              'url': rawUrl,
              'snippet': snippet,
            });
          }
        }
        return results;
      }
    } catch (_) {}
    return [];
  }

  Future<void> _runDirect({
    required String routerBaseUrl,
    required String apiKey,
    String backendUrl = '',
    String backendAccessToken = '',
    required String model,
    required double temperature,
    required List<ChatMessage> messages,
    required bool enableWebSearch,
    required Function(String status) onStatus,
    required Function(String chunk) onChunk,
    required Function(TokenUsage usage) onUsage,
    required Function() onDone,
    required Function(String error) onError,
  }) async {
    final outboundMessages = messages.map((m) => m.toApiMessage()).toList();

    // If web search is enabled, fetch SearXNG / Web search grounding
    if (enableWebSearch) {
      final userMsgs = messages
          .where((m) => m.role == MessageRole.user && m.content.isNotEmpty)
          .toList();
      final lastQuery = userMsgs.isNotEmpty ? userMsgs.last.content : '';

      if (lastQuery.isNotEmpty) {
        onStatus('Searching web via SearXNG...');
        List<Map<String, dynamic>> searchResults = [];

        if (backendUrl.isNotEmpty) {
          try {
            final searchUri = Uri.parse(
              '${ApiService.cleanUrl(backendUrl)}/api/v1/search',
            );
            ApiService.configureAccessToken(
              backendAccessToken,
              backendUrl: backendUrl,
            );
            final searchResp = await _client!.post(
              searchUri,
              headers: ApiService.headers(json: true, uri: searchUri),
              body: jsonEncode({'query': lastQuery, 'limit': 5}),
            );
            if (searchResp.statusCode == 200) {
              final data = jsonDecode(searchResp.body) as Map<String, dynamic>;
              final raw = (data['results'] as List<dynamic>?) ?? [];
              searchResults = raw.whereType<Map<String, dynamic>>().toList();
            }
          } catch (_) {}
        }

        if (searchResults.isEmpty) {
          final directRes = await _fetchDirectWebSearch(lastQuery, 5);
          searchResults = directRes;
        }

        if (searchResults.isNotEmpty) {
          final lines = <String>[
            '[Live Web Search Results via SearXNG for query: "$lastQuery"]:',
          ];
          for (var i = 0; i < searchResults.length; i++) {
            final item = searchResults[i];
            final title = item['title'] ?? '';
            final url = item['url'] ?? '';
            final snippet = item['snippet'] ?? '';
            lines.add('${i + 1}. $title\n   URL: $url\n   Snippet: $snippet');
          }
          final contextBlock = lines.join('\n');
          outboundMessages.insert(0, {
            'role': 'system',
            'content':
                'You are a helpful assistant. Use the following real-time SearXNG web search results when formulating your answer:\n\n$contextBlock',
          });
        }
      }
    }

    final uri = Uri.parse('$routerBaseUrl/chat/completions');
    final payload = <String, dynamic>{
      'model': model,
      'messages': outboundMessages,
      'temperature': temperature,
      'stream': true,
      'stream_options': {'include_usage': true},
    };

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..headers['HTTP-Referer'] = 'https://workfromphone.app'
      ..headers['X-Title'] = 'WorkFromPhone'
      ..body = jsonEncode(payload);

    if (apiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $apiKey';
    }

    onStatus('Generating response with $model...');

    final response = await _client!.send(request);
    if (_isCancelled) return;

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      onError(_formatHttpError(response.statusCode, body));
      return;
    }

    var sawError = false;
    await _consumeSse(response, (data) {
      if (data.containsKey('error')) {
        final err = data['error'];
        final errMsg = err is Map && err.containsKey('message')
            ? err['message'].toString()
            : err.toString();
        sawError = true;
        onError('API Error ($errMsg)');
        return;
      }

      final choices = data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final first = choices.first as Map<String, dynamic>;
        final delta = first['delta'] as Map<String, dynamic>?;
        if (delta != null) {
          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            onChunk(content);
          }
        }
      }

      if (data['usage'] is Map<String, dynamic>) {
        onUsage(TokenUsage.fromJson(data['usage'] as Map<String, dynamic>));
      }
    });

    if (!_isCancelled && !sawError) {
      onDone();
    }
  }

  Future<void> _consumeSse(
    http.StreamedResponse response,
    void Function(Map<String, dynamic> data) onEvent,
  ) async {
    var buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      if (_isCancelled) break;
      buffer += chunk;

      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (!line.startsWith('data:')) continue;

        final jsonStr = line.substring(5).trim();
        if (jsonStr.isEmpty || jsonStr == '[DONE]') {
          continue;
        }

        try {
          final data = jsonDecode(jsonStr);
          if (data is Map<String, dynamic>) {
            onEvent(data);
          }
        } catch (_) {
          // Ignore malformed partial chunks.
        }
      }
    }
  }

  static String _normalizeRouterBaseUrl(String baseUrl) {
    final clean = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return clean.isEmpty ? _defaultRouterBaseUrl : clean;
  }

  static String _formatHttpError(int statusCode, String body) {
    var errMsg = 'HTTP $statusCode';
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic> && parsed.containsKey('error')) {
        final err = parsed['error'];
        if (err is Map && err.containsKey('message')) {
          errMsg = err['message'].toString();
        } else if (err is Map && err.containsKey('detail')) {
          errMsg = err['detail'].toString();
        } else {
          errMsg = err.toString();
        }
      } else if (parsed is Map<String, dynamic> && parsed['detail'] != null) {
        errMsg = parsed['detail'].toString();
      }
    } catch (_) {
      errMsg = body.isNotEmpty ? body : errMsg;
    }
    return 'API Error ($errMsg)';
  }
}
