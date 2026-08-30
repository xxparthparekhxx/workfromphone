import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/screens/terminal/terminal_fullscreen_page.dart';
import 'package:workfromphone/screens/terminal/terminal_instance.dart';
import 'package:workfromphone/screens/terminal/terminal_surface.dart';
import 'package:workfromphone/services/terminal_session.dart';
import 'package:workfromphone/utils/tokyo_night_theme.dart';

enum _TerminalAction { copy, clear, reconnect, toggleKeys }

class ProjectTerminalTab extends StatefulWidget {
  final ProjectDirectory project;
  final String backendUrl;
  final String accessToken;

  const ProjectTerminalTab({
    super.key,
    required this.project,
    required this.backendUrl,
    this.accessToken = '',
  });

  @override
  State<ProjectTerminalTab> createState() => _ProjectTerminalTabState();
}

class _ProjectTerminalTabState extends State<ProjectTerminalTab> {
  final List<TerminalInstance> _terminals = [];
  int _activeIndex = 0;
  int _nextNumber = 1;
  String? _fullscreenTerminalId;

  TerminalInstance get _activeTerminal => _terminals[_activeIndex];

  @override
  void initState() {
    super.initState();
    _terminals.add(_createTerminal());
    _connectAfterFrame(_terminals.first);
  }

  @override
  void dispose() {
    for (final terminal in _terminals) {
      terminal.dispose();
    }
    super.dispose();
  }

  TerminalInstance _createTerminal() {
    final number = _nextNumber++;
    return TerminalInstance(
      id: 'terminal-${DateTime.now().microsecondsSinceEpoch}-$number',
      number: number,
      backendUrl: widget.backendUrl,
      projectPath: widget.project.path,
      accessToken: widget.accessToken,
    );
  }

  void _connectAfterFrame(TerminalInstance terminal) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_terminals.contains(terminal)) return;
      terminal.connect();
      terminal.requestFocus();
    });
  }

  void _addTerminal() {
    final terminal = _createTerminal();
    setState(() {
      _terminals.add(terminal);
      _activeIndex = _terminals.length - 1;
    });
    _connectAfterFrame(terminal);
  }

  void _selectTerminal(int index) {
    if (index == _activeIndex) {
      _terminals[index].requestFocus();
      return;
    }
    setState(() => _activeIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _activeTerminal.requestFocus();
    });
  }

  void _closeTerminal(int index) {
    final removed = _terminals[index];
    TerminalInstance? replacement;

    setState(() {
      _terminals.removeAt(index);
      if (_terminals.isEmpty) {
        replacement = _createTerminal();
        _terminals.add(replacement!);
        _activeIndex = 0;
      } else if (_activeIndex > index) {
        _activeIndex--;
      } else if (_activeIndex >= _terminals.length) {
        _activeIndex = _terminals.length - 1;
      }
    });

    removed.dispose();
    if (replacement != null) {
      _connectAfterFrame(replacement!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _activeTerminal.requestFocus();
      });
    }
  }

  Future<void> _copySelection(TerminalInstance terminal) async {
    final text = terminal.selectedText();
    if (text == null || text.isEmpty) {
      _showMessage('Long press and drag to select terminal text');
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    terminal.clearSelection();
    if (mounted) _showMessage('Selection copied');
  }

  void _handleAction(_TerminalAction action) {
    switch (action) {
      case _TerminalAction.copy:
        _copySelection(_activeTerminal);
      case _TerminalAction.clear:
        _activeTerminal.clearTerminal();
      case _TerminalAction.reconnect:
        _activeTerminal.reconnect();
      case _TerminalAction.toggleKeys:
        _activeTerminal.toggleAccessoryBar();
    }
  }

  Future<void> _openFullscreen() async {
    final terminal = _activeTerminal;
    setState(() => _fullscreenTerminalId = terminal.id);

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 140),
          pageBuilder: (context, animation, secondaryAnimation) =>
              TerminalFullscreenPage(instance: terminal),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _fullscreenTerminalId = null);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) terminal.requestFocus();
        });
      }
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
    return ColoredBox(
      color: TokyoNightColors.background,
      child: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: IndexedStack(
              index: _activeIndex,
              children: [
                for (final terminal in _terminals) _buildTerminalPane(terminal),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalPane(TerminalInstance terminal) {
    return KeyedSubtree(
      key: Key('terminal-pane-${terminal.id}'),
      child: Column(
        children: [
          Expanded(
            child: _fullscreenTerminalId == terminal.id
                ? const ColoredBox(color: TokyoNightColors.background)
                : TerminalSurface(instance: terminal),
          ),
          TerminalAccessoryBar(instance: terminal),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      key: const Key('terminal-tab-bar'),
      height: 48,
      decoration: const BoxDecoration(
        color: TokyoNightColors.gutterBg,
        border: Border(bottom: BorderSide(color: Color(0xFF24283B))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 6, top: 5, bottom: 5),
              itemCount: _terminals.length,
              itemBuilder: (context, index) {
                return _buildTerminalTab(_terminals[index], index);
              },
            ),
          ),
          _toolbarButton(
            key: const Key('terminal-add-tab'),
            icon: CupertinoIcons.add,
            tooltip: 'New terminal',
            onPressed: _addTerminal,
          ),
          const SizedBox(
            height: 24,
            child: VerticalDivider(
              width: 8,
              thickness: 1,
              color: Color(0xFF24283B),
            ),
          ),
          _toolbarButton(
            key: const Key('terminal-zoom-out'),
            icon: CupertinoIcons.minus,
            tooltip: 'Zoom out',
            onPressed: () => _activeTerminal.adjustFontSize(-1),
          ),
          _toolbarButton(
            key: const Key('terminal-zoom-in'),
            icon: CupertinoIcons.plus,
            tooltip: 'Zoom in',
            onPressed: () => _activeTerminal.adjustFontSize(1),
          ),
          _toolbarButton(
            key: const Key('terminal-fullscreen'),
            icon: CupertinoIcons.arrow_up_left_arrow_down_right,
            tooltip: 'Fullscreen terminal',
            onPressed: _openFullscreen,
          ),
          PopupMenuButton<_TerminalAction>(
            key: const Key('terminal-more-actions'),
            tooltip: 'Terminal actions',
            color: TokyoNightColors.surface,
            icon: const Icon(
              CupertinoIcons.ellipsis,
              size: 19,
              color: TokyoNightColors.gutterText,
            ),
            onSelected: _handleAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _TerminalAction.copy,
                child: _MenuLabel(CupertinoIcons.doc_on_doc, 'Copy selection'),
              ),
              const PopupMenuItem(
                value: _TerminalAction.clear,
                child: _MenuLabel(CupertinoIcons.trash, 'Clear terminal'),
              ),
              const PopupMenuItem(
                value: _TerminalAction.reconnect,
                child: _MenuLabel(CupertinoIcons.refresh, 'Reconnect shell'),
              ),
              PopupMenuItem(
                value: _TerminalAction.toggleKeys,
                child: _MenuLabel(
                  CupertinoIcons.keyboard,
                  _activeTerminal.accessoryExpanded
                      ? 'Hide extra keys'
                      : 'Show extra keys',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalTab(TerminalInstance terminal, int index) {
    final active = index == _activeIndex;
    return AnimatedBuilder(
      animation: terminal,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Material(
            color: active ? TokyoNightColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              key: Key('terminal-tab-${terminal.number}'),
              onTap: () => _selectTerminal(index),
              borderRadius: BorderRadius.circular(7),
              child: Container(
                width: 126,
                padding: const EdgeInsets.only(left: 8, right: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: active
                        ? const Color(0xFF3B4261)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _statusColor(terminal.connectionState),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            terminal.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active
                                  ? TokyoNightColors.foreground
                                  : TokyoNightColors.gutterText,
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_statusLabel(terminal.connectionState)} · ${terminal.cols}×${terminal.rows}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: TokyoNightColors.gutterText,
                              fontFamily: 'monospace',
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: Key('terminal-close-${terminal.number}'),
                      tooltip: 'Close terminal ${terminal.number}',
                      onPressed: () => _closeTerminal(index),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 25,
                        minHeight: 30,
                      ),
                      icon: const Icon(
                        CupertinoIcons.xmark,
                        size: 14,
                        color: TokyoNightColors.gutterText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _toolbarButton({
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
      constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
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

  String _statusLabel(TerminalConnectionState state) {
    switch (state) {
      case TerminalConnectionState.connecting:
        return 'connecting';
      case TerminalConnectionState.connected:
        return 'connected';
      case TerminalConnectionState.exited:
        return 'exited';
      case TerminalConnectionState.disconnected:
        return 'offline';
    }
  }
}

class _MenuLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuLabel(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: TokyoNightColors.gutterText),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: TokyoNightColors.foreground)),
      ],
    );
  }
}
