import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/utils/tokyo_night_theme.dart';

class CodeEditorView extends StatefulWidget {
  final TokyoNightCodeController controller;
  final bool readOnly;
  final ValueChanged<String>? onChanged;

  const CodeEditorView({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.onChanged,
  });

  @override
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<CodeEditorView> {
  final ScrollController _verticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();
  final FocusNode _focusNode = FocusNode();
  int _lineCount = 1;

  @override
  void initState() {
    super.initState();
    _updateLineCount();
    widget.controller.addListener(_updateLineCount);
  }

  @override
  void didUpdateWidget(covariant CodeEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateLineCount);
      widget.controller.addListener(_updateLineCount);
      _updateLineCount();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateLineCount);
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateLineCount() {
    final lines = widget.controller.text.split('\n').length;
    final validLines = lines > 0 ? lines : 1;
    if (validLines != _lineCount && mounted) {
      setState(() {
        _lineCount = validLines;
      });
    }
  }

  void _insertIndent() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (selection.start < 0) return;

    const indent = '  '; // 2 spaces
    final newText = text.replaceRange(selection.start, selection.end, indent);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + indent.length,
      ),
    );
    widget.onChanged?.call(newText);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    const double lineHeight =
        18.85; // Standard 13pt monospace line height * 1.45
    const textStyle = TextStyle(
      color: TokyoNightColors.foreground,
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.45,
    );

    return Container(
      color: TokyoNightColors.background,
      child: Column(
        children: [
          // Editor Main Area (Line Numbers Gutter + Code Editor Text Area)
          Expanded(
            child: SingleChildScrollView(
              controller: _verticalScroll,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line Numbers Gutter
                  Container(
                    width: 44,
                    padding: const EdgeInsets.only(
                      top: 12,
                      right: 8,
                      bottom: 24,
                    ),
                    decoration: const BoxDecoration(
                      color: TokyoNightColors.gutterBg,
                      border: Border(
                        right: BorderSide(color: Color(0xFF24283B), width: 1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(
                        _lineCount,
                        (index) => SizedBox(
                          height: lineHeight,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: TokyoNightColors.gutterText,
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Editable / Viewable Code Field with Horizontal Scrolling
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _horizontalScroll,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 24,
                        top: 12,
                        bottom: 24,
                      ),
                      child: SizedBox(
                        width: 2500, // Stable canvas width to prevent layout shifts & keyboard dismissal
                        child: TextField(
                          controller: widget.controller,
                          focusNode: _focusNode,
                          readOnly: widget.readOnly,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          cursorColor: TokyoNightColors.cyan,
                          style: textStyle,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: widget.onChanged,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Code Editor Quick Tools Bar
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: TokyoNightColors.gutterBg,
              border: Border(
                top: BorderSide(color: Color(0xFF24283B), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Tokyo Night',
                  style: TextStyle(
                    color: TokyoNightColors.keyword,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$_lineCount lines',
                  style: const TextStyle(
                    color: TokyoNightColors.gutterText,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                if (!widget.readOnly) ...[
                  InkWell(
                    onTap: _insertIndent,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: TokyoNightColors.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.arrow_right_square,
                            size: 12,
                            color: TokyoNightColors.cyan,
                          ),
                          SizedBox(width: 2),
                          Text(
                            'Tab',
                            style: TextStyle(
                              color: TokyoNightColors.foreground,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
