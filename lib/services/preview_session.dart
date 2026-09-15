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
  int _reconnectAttempts = 0;
  bool _authFailed = false;

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
    _authFailed = false;
    _reconnectAttempts = 0;
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
            // A successful frame resets the backoff chain.
            _reconnectAttempts = 0;
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
          _handleDone();
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

  /// Exponential backoff with cap (3s…30s). Auth rejections (4401/4403)
  /// stop reconnecting — a bad token never recovers by retrying.
  void _scheduleReconnect() {
    if (!_shouldRun || _authFailed || _reconnectTimer?.isActive == true) {
      return;
    }
    _reconnectAttempts++;
    final backoffSeconds = _reconnectAttempts <= 1
        ? 3
        : (3 * (1 << (_reconnectAttempts - 1))).clamp(3, 30);
    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), _connect);
  }

  bool _isAuthClose(int? closeCode) => closeCode == 4401 || closeCode == 4403;

  void _handleDone() {
    final closeCode = _channel?.closeCode;
    if (_isAuthClose(closeCode)) {
      _authFailed = true;
      _reconnectTimer?.cancel();
      onStateChange(PreviewSessionState.disconnected);
      onError(
        closeCode == 4401
            ? 'Preview stream rejected: invalid or missing access token.'
            : 'Preview stream rejected: browser origin not allowed.',
      );
      return;
    }
    onStateChange(PreviewSessionState.disconnected);
    _scheduleReconnect();
  }

  Future<void> stop() async {
    _shouldRun = false;
    _generation++;
    _reconnectAttempts = 0;
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
