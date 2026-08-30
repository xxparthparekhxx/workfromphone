import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:workfromphone/models/system_snapshot.dart';

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
      final headers = <String, dynamic>{};
      if (accessToken?.isNotEmpty == true) {
        headers['Authorization'] = 'Bearer $accessToken';
      }
      final channel = IOWebSocketChannel.connect(
        _webSocketUri(),
        headers: headers,
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        (message) {
          if (!_shouldRun || generation != _generation) return;
          try {
            final json = jsonDecode(message as String) as Map<String, dynamic>;
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
          onStateChange(SystemMonitorState.disconnected);
          _scheduleReconnect();
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
