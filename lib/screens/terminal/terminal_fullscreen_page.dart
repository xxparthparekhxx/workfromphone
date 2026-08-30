import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workfromphone/screens/terminal/terminal_instance.dart';
import 'package:workfromphone/screens/terminal/terminal_surface.dart';
import 'package:workfromphone/services/terminal_session.dart';
import 'package:workfromphone/utils/tokyo_night_theme.dart';

enum _FullscreenAction { copy, clear, reconnect, toggleKeys }

class TerminalFullscreenPage extends StatefulWidget {
  final TerminalInstance instance;

  const TerminalFullscreenPage({super.key, required this.instance});

  @override
  State<TerminalFullscreenPage> createState() => _TerminalFullscreenPageState();
}

class _TerminalFullscreenPageState extends State<TerminalFullscreenPage> {
  TerminalInstance get instance => widget.instance;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) instance.requestFocus();
    });
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> _copySelection() async {
    final text = instance.selectedText();
    if (text == null || text.isEmpty) {
      _showMessage('Long press and drag to select terminal text');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    instance.clearSelection();
    if (mounted) _showMessage('Selection copied');
  }

  void _handleAction(_FullscreenAction action) {
    switch (action) {
      case _FullscreenAction.copy:
        _copySelection();
      case _FullscreenAction.clear:
        instance.clearTerminal();
      case _FullscreenAction.reconnect:
        instance.reconnect();
      case _FullscreenAction.toggleKeys:
        instance.toggleAccessoryBar();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TokyoNightColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildFullscreenBar(),
            Expanded(
              child: TerminalSurface(
                instance: instance,
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              ),
            ),
            TerminalAccessoryBar(instance: instance),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenBar() {
    return AnimatedBuilder(
      animation: instance,
      builder: (context, _) {
        return Container(
          key: const Key('terminal-fullscreen-bar'),
          height: 38,
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(
            color: TokyoNightColors.gutterBg,
            border: Border(bottom: BorderSide(color: Color(0xFF24283B))),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _statusColor(instance.connectionState),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${instance.title}  ·  ${instance.cols}×${instance.rows}  ·  ${instance.fontSize.toStringAsFixed(1)}pt',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TokyoNightColors.foreground,
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _barButton(
                key: const Key('terminal-fullscreen-zoom-out'),
                icon: CupertinoIcons.minus,
                tooltip: 'Zoom out',
                onPressed: () => instance.adjustFontSize(-1),
              ),
              _barButton(
                key: const Key('terminal-fullscreen-zoom-in'),
                icon: CupertinoIcons.plus,
                tooltip: 'Zoom in',
                onPressed: () => instance.adjustFontSize(1),
              ),
              PopupMenuButton<_FullscreenAction>(
                tooltip: 'Terminal actions',
                color: TokyoNightColors.surface,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 38),
                icon: const Icon(
                  CupertinoIcons.ellipsis,
                  size: 18,
                  color: TokyoNightColors.gutterText,
                ),
                onSelected: _handleAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _FullscreenAction.copy,
                    child: Text('Copy selection'),
                  ),
                  const PopupMenuItem(
                    value: _FullscreenAction.clear,
                    child: Text('Clear terminal'),
                  ),
                  const PopupMenuItem(
                    value: _FullscreenAction.reconnect,
                    child: Text('Reconnect shell'),
                  ),
                  PopupMenuItem(
                    value: _FullscreenAction.toggleKeys,
                    child: Text(
                      instance.accessoryExpanded
                          ? 'Hide extra keys'
                          : 'Show extra keys',
                    ),
                  ),
                ],
              ),
              _barButton(
                key: const Key('terminal-fullscreen-exit'),
                icon: CupertinoIcons.arrow_down_right_arrow_up_left,
                tooltip: 'Exit fullscreen',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _barButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 38),
      icon: Icon(icon, size: 18, color: TokyoNightColors.gutterText),
    );
  }

  Color _statusColor(TerminalConnectionState state) {
    switch (state) {
      case TerminalConnectionState.connecting:
        return TokyoNightColors.type;
      case TerminalConnectionState.connected:
        return TokyoNightColors.string;
      case TerminalConnectionState.exited:
        return TokyoNightColors.comment;
      case TerminalConnectionState.disconnected:
        return TokyoNightColors.annotation;
    }
  }
}
