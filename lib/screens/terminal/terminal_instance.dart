import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workfromphone/services/terminal_session.dart';
import 'package:xterm/xterm.dart';

class TerminalInstance extends ChangeNotifier {
  static const double minFontSize = 9;
  static const double maxFontSize = 22;
  static const double defaultFontSize = 13;

  final String id;
  final int number;
  final Terminal terminal;
  final TerminalController terminalController;
  final FocusNode focusNode;

  late final TerminalSession session;

  TerminalConnectionState connectionState = TerminalConnectionState.connecting;
  String shell = 'shell';
  int cols = 80;
  int rows = 24;
  int pixelWidth = 0;
  int pixelHeight = 0;
  double fontSize = defaultFontSize;
  bool ctrlArmed = false;
  bool accessoryExpanded = true;

  Timer? _resizeDebounce;
  bool _notifyScheduled = false;
  bool _disposed = false;

  TerminalInstance({
    required this.id,
    required this.number,
    required String backendUrl,
    required String projectPath,
    String accessToken = '',
  }) : terminal = Terminal(maxLines: 10000),
       terminalController = TerminalController(),
       focusNode = FocusNode() {
    session = TerminalSession(
      backendUrl: backendUrl,
      projectPath: projectPath,
      accessToken: accessToken,
      onOutput: terminal.write,
      onReady: _handleReady,
      onExit: _handleExit,
      onError: _handleError,
      onStateChange: _handleStateChange,
    );
    terminal.onOutput = _handleTerminalInput;
    terminal.onResize = _handleResize;
  }

  String get title => '$number · $shell';

  bool get isConnected => connectionState == TerminalConnectionState.connected;

  Future<void> connect() => session.connect();

  void reconnect() {
    terminal.write(
      '\r\n\x1b[33m[Starting a new terminal session...]\x1b[0m\r\n',
    );
    session.connect();
  }

  void requestFocus() {
    if (!_disposed) focusNode.requestFocus();
  }

  void _handleReady(String value) {
    if (_disposed) return;
    shell = value.split('/').last;
    session.resize(
      cols,
      rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    );
    notifyListeners();
    requestFocus();
  }

  void _handleExit(int exitCode) {
    if (_disposed) return;
    terminal.write(
      '\r\n\x1b[90m[Shell exited with code $exitCode. Reconnect to start a new session.]\x1b[0m\r\n',
    );
  }

  void _handleError(String error) {
    if (_disposed) return;
    terminal.write('\r\n\x1b[31m[Terminal error: $error]\x1b[0m\r\n');
  }

  void _handleStateChange(TerminalConnectionState state) {
    if (_disposed) return;
    connectionState = state;
    if (!isConnected) ctrlArmed = false;
    notifyListeners();
  }

  void _handleTerminalInput(String data) {
    if (_disposed) return;
    if (ctrlArmed && data.runes.length == 1) {
      final rune = data.runes.single;
      if (rune >= 65 && rune <= 90) {
        session.sendInput(String.fromCharCode(rune - 64));
      } else if (rune >= 97 && rune <= 122) {
        session.sendInput(String.fromCharCode(rune - 96));
      } else {
        session.sendInput(data);
      }
      ctrlArmed = false;
      notifyListeners();
      return;
    }
    session.sendInput(data);
  }

  void _handleResize(
    int newCols,
    int newRows,
    int newPixelWidth,
    int newPixelHeight,
  ) {
    if (_disposed) return;
    final dimensionsChanged = newCols != cols || newRows != rows;
    cols = newCols;
    rows = newRows;
    pixelWidth = newPixelWidth;
    pixelHeight = newPixelHeight;

    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 120), () {
      if (_disposed) return;
      session.resize(
        cols,
        rows,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      );
    });

    if (dimensionsChanged) _scheduleNotifyAfterFrame();
  }

  void _scheduleNotifyAfterFrame() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void sendKey(TerminalKey key) {
    final useCtrl = ctrlArmed;
    if (ctrlArmed) {
      ctrlArmed = false;
      notifyListeners();
    }
    terminal.keyInput(key, ctrl: useCtrl);
    requestFocus();
  }

  void sendText(String text) {
    if (ctrlArmed) {
      ctrlArmed = false;
      notifyListeners();
    }
    terminal.textInput(text);
    requestFocus();
  }

  void toggleCtrl() {
    ctrlArmed = !ctrlArmed;
    notifyListeners();
    requestFocus();
  }

  void toggleAccessoryBar() {
    accessoryExpanded = !accessoryExpanded;
    notifyListeners();
    requestFocus();
  }

  void setFontSize(double value) {
    final bounded = value.clamp(minFontSize, maxFontSize).toDouble();
    final rounded = (bounded * 10).roundToDouble() / 10;
    if (rounded == fontSize) return;
    fontSize = rounded;
    terminalController.clearSelection();
    notifyListeners();
  }

  void adjustFontSize(double delta) {
    setFontSize(fontSize + delta);
    requestFocus();
  }

  String? selectedText() {
    final selection = terminalController.selection;
    if (selection == null) return null;
    return terminal.buffer.getText(selection);
  }

  void clearSelection() {
    terminalController.clearSelection();
  }

  void clearTerminal() {
    terminal.write('\x1b[2J\x1b[3J\x1b[H');
    terminalController.clearSelection();
    requestFocus();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _resizeDebounce?.cancel();
    session.dispose();
    terminalController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
