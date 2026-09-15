import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:workfromphone/models/system_snapshot.dart';
import 'package:workfromphone/services/api_service.dart';

enum SystemMonitorState { disconnected, connecting, connected }

class SystemMonitorSession {
  final String backendUrl;
  final String? accessToken;
  final void Function(SystemSnapshot snapshot) onSnapshot;
  final void Function(SystemMonitorState state) onStateChange;
  final void Function(String error) onError;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _shouldRun = false;
  int _generation = 0;
  int _reconnectAttempts = 0;
  bool _authFailed = false;

  SystemMonitorSession({
    required this.backendUrl,
    required this.onSnapshot,
    required this.onStateChange,
    required this.onError,
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
    return Uri.parse('$base/api/v1/system/ws?interval=2');
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

    onStateChange(SystemMonitorState.connecting);
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
            onStateChange(SystemMonitorState.connected);
            onSnapshot(SystemSnapshot.fromJson(json));
          } catch (error) {
            onError('Invalid metrics response: $error');
          }
        },
        onError: (Object error) {
          if (!_shouldRun || generation != _generation) return;
          onError('Metrics connection failed: $error');
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
      onStateChange(SystemMonitorState.disconnected);
      onError('Metrics connection failed: $error');
      _scheduleReconnect();
    }
  }

  /// Exponential backoff with jitter (3s, 6s, 12s… capped at 30s). Stops
  /// entirely after an auth rejection (4401/4403) — retrying a bad token in
  /// a tight loop hammers the backend and never recovers.
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

  /// Backend auth/origin rejections arrive as abnormal WS closes. Returns
  /// true when the close code means "fix credentials, don't retry".
  bool _isAuthClose(int? closeCode) => closeCode == 4401 || closeCode == 4403;

  void _handleDone() {
    final closeCode = _channel?.closeCode;
    if (_isAuthClose(closeCode)) {
      _authFailed = true;
      _reconnectTimer?.cancel();
      onStateChange(SystemMonitorState.disconnected);
      onError(
        closeCode == 4401
            ? 'Metrics stream rejected: invalid or missing access token.'
            : 'Metrics stream rejected: browser origin not allowed.',
      );
      return;
    }
    onStateChange(SystemMonitorState.disconnected);
    _scheduleReconnect();
  }

  Future<void> stop() async {
    _shouldRun = false;
    _generation++;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeChannel();
    onStateChange(SystemMonitorState.disconnected);
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
