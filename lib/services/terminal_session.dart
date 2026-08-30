import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum TerminalConnectionState { disconnected, connecting, connected, exited }

typedef TerminalOutputCallback = void Function(String data);
typedef TerminalReadyCallback = void Function(String shell);
typedef TerminalExitCallback = void Function(int exitCode);
typedef TerminalErrorCallback = void Function(String error);

class TerminalSession {
  final String backendUrl;
  final String projectPath;
  final String accessToken;

  final TerminalOutputCallback onOutput;
  final TerminalReadyCallback? onReady;
  final TerminalExitCallback? onExit;
  final TerminalErrorCallback? onError;
  final void Function(TerminalConnectionState state)? onStateChange;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  TerminalConnectionState _state = TerminalConnectionState.disconnected;
  bool _isDisposed = false;
  int _generation = 0;

  TerminalSession({
    required this.backendUrl,
    required this.projectPath,
    required this.onOutput,
    this.accessToken = '',
    this.onReady,
    this.onExit,
    this.onError,
    this.onStateChange,
  });

  TerminalConnectionState get state => _state;
  bool get isConnected => _state == TerminalConnectionState.connected;

  String _buildWsUrl() {
    String cleanUrl = backendUrl.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }

    if (cleanUrl.startsWith('https://')) {
      cleanUrl = cleanUrl.replaceFirst('https://', 'wss://');
    } else if (cleanUrl.startsWith('http://')) {
      cleanUrl = cleanUrl.replaceFirst('http://', 'ws://');
    } else if (!cleanUrl.startsWith('ws://') &&
        !cleanUrl.startsWith('wss://')) {
      cleanUrl = 'ws://$cleanUrl';
    }

    final uri = Uri.parse('$cleanUrl/api/v1/terminal/ws')
        .replace(queryParameters: {'project_path': projectPath});
    return uri.toString();
  }

  Future<void> connect() async {
    if (_isDisposed) return;

    final generation = ++_generation;
    _setState(TerminalConnectionState.connecting);

    await _closeCurrentConnection();
    if (_isDisposed || generation != _generation) return;

    try {
      final wsUrl = _buildWsUrl();
      final channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: {
          if (accessToken.isNotEmpty) 'Authorization': 'Bearer $accessToken',
        },
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        (message) => _handleMessage(message, generation),
        onError: (err) {
          if (_isDisposed || generation != _generation) return;
          _setState(TerminalConnectionState.disconnected);
          onError?.call('WebSocket error: $err');
        },
        onDone: () {
          if (_isDisposed || generation != _generation) return;
          if (_state != TerminalConnectionState.exited) {
            _setState(TerminalConnectionState.disconnected);
          }
        },
        cancelOnError: false,
      );

      await channel.ready;
    } catch (e) {
      if (_isDisposed || generation != _generation) return;
      _setState(TerminalConnectionState.disconnected);
      onError?.call('Connection failed: $e');
    }
  }

  void _handleMessage(dynamic message, int generation) {
    if (_isDisposed || generation != _generation) return;

    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'output') {
        onOutput(data['data'] as String? ?? '');
      } else if (type == 'ready') {
        _setState(TerminalConnectionState.connected);
        onReady?.call(data['shell'] as String? ?? 'shell');
      } else if (type == 'exit') {
        final exitCode = data['exit_code'] as int? ?? 0;
        _setState(TerminalConnectionState.exited);
        onExit?.call(exitCode);
      } else if (type == 'error') {
        onError?.call(data['error'] as String? ?? 'Unknown terminal error');
      }
    } catch (e) {
      onError?.call('Invalid terminal message: $e');
    }
  }

  void sendInput(String input) {
    if (!isConnected || input.isEmpty) return;
    final payload = jsonEncode({'type': 'input', 'data': input});
    _channel?.sink.add(payload);
  }

  void resize(int cols, int rows, {int pixelWidth = 0, int pixelHeight = 0}) {
    if (!isConnected || cols <= 0 || rows <= 0) return;
    final payload = jsonEncode({
      'type': 'resize',
      'cols': cols,
      'rows': rows,
      'pixel_width': pixelWidth,
      'pixel_height': pixelHeight,
    });
    _channel?.sink.add(payload);
  }

  void _setState(TerminalConnectionState state) {
    if (_state == state) return;
    _state = state;
    onStateChange?.call(state);
  }

  Future<void> _closeCurrentConnection() async {
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;

    await channel?.sink.close();
    await subscription?.cancel();
  }

  void dispose() {
    _isDisposed = true;
    _generation++;
    unawaited(_closeCurrentConnection());
    _state = TerminalConnectionState.disconnected;
  }
}
