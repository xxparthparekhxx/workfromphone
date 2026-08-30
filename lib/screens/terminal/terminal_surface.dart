import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/screens/terminal/terminal_instance.dart';
import 'package:workfromphone/utils/tokyo_night_theme.dart';
import 'package:xterm/xterm.dart';

const terminalTokyoNightTheme = TerminalTheme(
  cursor: TokyoNightColors.cyan,
  selection: TokyoNightColors.selection,
  foreground: TokyoNightColors.foreground,
  background: TokyoNightColors.background,
  black: Color(0xFF15161E),
  red: Color(0xFFF7768E),
  green: Color(0xFF9ECE6A),
  yellow: Color(0xFFE0AF68),
  blue: Color(0xFF7AA2F7),
  magenta: Color(0xFFBB9AF7),
  cyan: Color(0xFF7DCFFF),
  white: Color(0xFFC0CAF5),
  brightBlack: Color(0xFF565F89),
  brightRed: Color(0xFFFF899D),
  brightGreen: Color(0xFFB9F27C),
  brightYellow: Color(0xFFFFC777),
  brightBlue: Color(0xFF8DB0FF),
  brightMagenta: Color(0xFFC7A9FF),
  brightCyan: Color(0xFFA4DAFF),
  brightWhite: Color(0xFFD5D6DB),
  searchHitBackground: Color(0xFFE0AF68),
  searchHitBackgroundCurrent: Color(0xFFFF9E64),
  searchHitForeground: Color(0xFF1A1B26),
);

class TerminalSurface extends StatefulWidget {
  final TerminalInstance instance;
  final EdgeInsets padding;

  const TerminalSurface({
    super.key,
    required this.instance,
    this.padding = const EdgeInsets.fromLTRB(10, 8, 10, 6),
  });

  @override
  State<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<TerminalSurface> {
  final Map<int, Offset> _touches = {};
  double? _pinchDistance;
  double? _pinchFontSize;

  void _pointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touches[event.pointer] = event.localPosition;
    if (_touches.length == 2) {
      final points = _touches.values.toList(growable: false);
      _pinchDistance = (points[0] - points[1]).distance;
      _pinchFontSize = widget.instance.fontSize;
      widget.instance.clearSelection();
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_touches.containsKey(event.pointer)) return;
    _touches[event.pointer] = event.localPosition;
    if (_touches.length != 2 ||
        _pinchDistance == null ||
        _pinchDistance! <= 0 ||
        _pinchFontSize == null) {
      return;
    }
    final points = _touches.values.toList(growable: false);
    final distance = (points[0] - points[1]).distance;
    widget.instance.setFontSize(_pinchFontSize! * (distance / _pinchDistance!));
  }

  void _pointerEnd(PointerEvent event) {
    _touches.remove(event.pointer);
    if (_touches.length < 2) {
      _pinchDistance = null;
      _pinchFontSize = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.instance,
      builder: (context, _) {
        return Listener(
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerEnd,
          onPointerCancel: _pointerEnd,
          child: TerminalView(
            widget.instance.terminal,
            key: Key('terminal-view-${widget.instance.id}'),
            controller: widget.instance.terminalController,
            focusNode: widget.instance.focusNode,
            autofocus: true,
            readOnly: !widget.instance.isConnected,
            deleteDetection: true,
            theme: terminalTokyoNightTheme,
            textStyle: TerminalStyle(
              fontFamily: 'monospace',
              fontSize: widget.instance.fontSize,
              height: 1.25,
            ),
            textScaler: TextScaler.noScaling,
            padding: widget.padding,
            keyboardAppearance: Brightness.dark,
          ),
        );
      },
    );
  }
}

class TerminalAccessoryBar extends StatelessWidget {
  final TerminalInstance instance;

  const TerminalAccessoryBar({super.key, required this.instance});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: instance,
      builder: (context, _) {
        if (!instance.accessoryExpanded) {
          return Container(
            key: const Key('terminal-accessory-collapsed'),
            height: 28,
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              color: TokyoNightColors.gutterBg,
              border: Border(top: BorderSide(color: Color(0xFF24283B))),
            ),
            child: TextButton.icon(
              onPressed: instance.toggleAccessoryBar,
              style: TextButton.styleFrom(
                foregroundColor: TokyoNightColors.gutterText,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: const Icon(CupertinoIcons.keyboard, size: 15),
              label: const Text(
                'KEYS',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }

        return Container(
          key: const Key('terminal-accessory-bar'),
          height: 42,
          decoration: const BoxDecoration(
            color: TokyoNightColors.gutterBg,
            border: Border(top: BorderSide(color: Color(0xFF24283B))),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
            children: [
              _iconButton(
                CupertinoIcons.chevron_down,
                instance.toggleAccessoryBar,
                tooltip: 'Collapse terminal keys',
              ),
              _keyButton('ESC', () => instance.sendKey(TerminalKey.escape)),
              _keyButton('TAB', () => instance.sendKey(TerminalKey.tab)),
              _keyButton(
                'CTRL',
                instance.toggleCtrl,
                active: instance.ctrlArmed,
              ),
              _keyButton('↑', () => instance.sendKey(TerminalKey.arrowUp)),
              _keyButton('↓', () => instance.sendKey(TerminalKey.arrowDown)),
              _keyButton('←', () => instance.sendKey(TerminalKey.arrowLeft)),
              _keyButton('→', () => instance.sendKey(TerminalKey.arrowRight)),
              _keyButton('|', () => instance.sendText('|')),
              _keyButton('~', () => instance.sendText('~')),
              _keyButton('/', () => instance.sendText('/')),
              _keyButton('-', () => instance.sendText('-')),
              _keyButton('_', () => instance.sendText('_')),
            ],
          ),
        );
      },
    );
  }

  Widget _iconButton(
    IconData icon,
    VoidCallback onPressed, {
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: TokyoNightColors.surface,
          foregroundColor: TokyoNightColors.gutterText,
          minimumSize: const Size(34, 30),
          maximumSize: const Size(34, 30),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: Color(0xFF24283B)),
          ),
        ),
        icon: Icon(icon, size: 17),
      ),
    );
  }

  Widget _keyButton(
    String label,
    VoidCallback onPressed, {
    bool active = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: Material(
        color: active ? const Color(0xFF283457) : TokyoNightColors.surface,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: instance.isConnected ? onPressed : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minWidth: 38),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF24283B)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? TokyoNightColors.cyan
                    : TokyoNightColors.foreground,
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
