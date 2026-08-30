import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:workfromphone/models/preview_entry.dart';
import 'package:workfromphone/services/api_service.dart';

enum PreviewSessionState { disconnected, connecting, connected }

/// Subscribes to the backend's preview registry stream so the UI can
/// react to entries added by the LLM harness or by other clients in
/// real time.
class PreviewSession {
  final String backendUrl;
  final String? accessToken;
  final String projectPath;
  final void Function(List<PreviewEntry> entries) onEntries;
  final void Function(PreviewSessionState state) onStateChange;
  final void Function(String error) onError;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _shouldRun = false;
  int _generation = 0;

  PreviewSession({
    required this.backendUrl,
    required this.onEntries,
    required this.onStateChange,
    required this.onError,
    required this.projectPath,
    this.accessToken,
  });

  Uri _webSocketUri() {
    var base = backendUrl.trim().replaceFirst(RegExp(r'/$'), '');
    if (base.startsWith('https://')) {
      base = base.replaceFirst('https://', 'wss://');
    } else if (base.startsWith('http://')) {
      base = base.replaceFirst('http://', 'ws://');
    } else if (!base.startsWith('ws://') && !base.startsWith('wss://')) {
      base = 'ws://$base';
    }
    return Uri.parse('$base/api/v1/preview/ws');
  }

  Future<void> start() async {
    if (_shouldRun) return;
    _shouldRun = true;
    await _connect();
  }

  Future<void> _connect() async {
    if (!_shouldRun) return;
    final generation = ++_generation;
    _reconnectTimer?.cancel();
    await _closeChannel();
    if (!_shouldRun || generation != _generation) return;

    onStateChange(PreviewSessionState.connecting);
    try {
      final uri = _webSocketUri();
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: ApiService.webSocketAuthHeaders(uri, accessToken ?? ''),
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        (message) {
          if (!_shouldRun || generation != _generation) return;
          try {
            final json = jsonDecode(message as String) as Map<String, dynamic>;
            onStateChange(PreviewSessionState.connected);
            final raw = (json['entries'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>();
            final entries = raw.map(PreviewEntry.fromJson).toList();
            onEntries(entries);
          } catch (error) {
            onError('Invalid preview payload: $error');
          }
        },
        onError: (Object error) {
          if (!_shouldRun || generation != _generation) return;
          onError('Preview stream failed: $error');
          _scheduleReconnect();
        },
        onDone: () {
          if (!_shouldRun || generation != _generation) return;
          onStateChange(PreviewSessionState.disconnected);
          _scheduleReconnect();
        },
      );
      await channel.ready;
    } catch (error) {
      if (!_shouldRun || generation != _generation) return;
      onStateChange(PreviewSessionState.disconnected);
      onError('Preview stream failed: $error');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_shouldRun || _reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), _connect);
  }

  Future<void> stop() async {
    _shouldRun = false;
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeChannel();
    onStateChange(PreviewSessionState.disconnected);
  }

  Future<void> _closeChannel() async {
    final channel = _channel;
    final subscription = _subscription;
    _channel = null;
    _subscription = null;
    await channel?.sink.close();
    await subscription?.cancel();
  }

  void dispose() {
    unawaited(stop());
  }
}
