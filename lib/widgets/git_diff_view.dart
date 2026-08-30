import 'package:flutter/material.dart';
import 'package:workfromphone/utils/tokyo_night_theme.dart';

enum DiffLineType { header, hunk, addition, deletion, context }

class DiffLine {
  final DiffLineType type;
  final int? oldLineNum;
  final int? newLineNum;
  final String text;

  const DiffLine({
    required this.type,
    this.oldLineNum,
    this.newLineNum,
    required this.text,
  });
}

class GitDiffParser {
  static List<DiffLine> parse(String rawDiff) {
    if (rawDiff.trim().isEmpty) return [];

    final lines = rawDiff.split('\n');
    final result = <DiffLine>[];

    int? currentOldLine;
    int? currentNewLine;

    final hunkRegex = RegExp(r'^@@\s+-(\d+)(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s+@@');

    for (final line in lines) {
      if (line.startsWith('diff --git') ||
          line.startsWith('index ') ||
          line.startsWith('--- ') ||
          line.startsWith('+++ ') ||
          line.startsWith('new file mode') ||
          line.startsWith('deleted file mode') ||
          line.startsWith('similarity index') ||
          line.startsWith('rename from') ||
          line.startsWith('rename to')) {
        result.add(DiffLine(type: DiffLineType.header, text: line));
        continue;
      }

      final hunkMatch = hunkRegex.firstMatch(line);
      if (hunkMatch != null) {
        currentOldLine = int.tryParse(hunkMatch.group(1)!);
        currentNewLine = int.tryParse(hunkMatch.group(2)!);
        result.add(DiffLine(type: DiffLineType.hunk, text: line));
        continue;
      }

      if (line.startsWith('+')) {
        final num = currentNewLine;
        if (currentNewLine != null) currentNewLine++;
        result.add(
          DiffLine(type: DiffLineType.addition, newLineNum: num, text: line),
        );
      } else if (line.startsWith('-')) {
        final num = currentOldLine;
        if (currentOldLine != null) currentOldLine++;
        result.add(
          DiffLine(type: DiffLineType.deletion, oldLineNum: num, text: line),
        );
      } else {
        final oldNum = currentOldLine;
        final newNum = currentNewLine;
        if (currentOldLine != null) currentOldLine++;
        if (currentNewLine != null) currentNewLine++;
        result.add(
          DiffLine(
            type: DiffLineType.context,
            oldLineNum: oldNum,
            newLineNum: newNum,
            text: line,
          ),
        );
      }
    }

    return result;
  }
}

class GitDiffView extends StatelessWidget {
  final String rawDiff;
  final ScrollController? scrollController;

  const GitDiffView({super.key, required this.rawDiff, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final parsedLines = GitDiffParser.parse(rawDiff);

    if (parsedLines.isEmpty) {
      return Container(
        color: TokyoNightColors.background,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: const Text(
          'No differences to display.',
          style: TextStyle(
            color: TokyoNightColors.gutterText,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
        ),
      );
    }

    return Container(
      color: TokyoNightColors.background,
      child: SingleChildScrollView(
        controller: scrollController,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header legend bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  color: TokyoNightColors.gutterBg,
                  child: Row(
                    children: [
                      const Text(
                        'OLD',
                        style: TextStyle(
                          color: TokyoNightColors.gutterText,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        'NEW',
                        style: TextStyle(
                          color: TokyoNightColors.gutterText,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        '${parsedLines.length} lines in diff',
                        style: const TextStyle(
                          color: TokyoNightColors.gutterText,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF24283B)),

                // Parsed diff lines with dual line numbers
                for (int i = 0; i < parsedLines.length; i++)
                  _buildLineRow(parsedLines[i]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLineRow(DiffLine line) {
    Color? bgColor;
    Color textColor = TokyoNightColors.foreground;
    Color oldNumColor = TokyoNightColors.gutterText;
    Color newNumColor = TokyoNightColors.gutterText;

    switch (line.type) {
      case DiffLineType.addition:
        bgColor = const Color(0x2422C55E); // Green tint
        textColor = const Color(0xFF9ECE6A); // Tokyo Night green
        newNumColor = const Color(0xFF9ECE6A);
        break;
      case DiffLineType.deletion:
        bgColor = const Color(0x24EF4444); // Red tint
        textColor = const Color(0xFFF7768E); // Tokyo Night red/coral
        oldNumColor = const Color(0xFFF7768E);
        break;
      case DiffLineType.hunk:
        bgColor = const Color(0x1F7DCFFF); // Cyan tint
        textColor = const Color(0xFF7DCFFF);
        break;
      case DiffLineType.header:
        bgColor = const Color(0x0FFFFFFF);
        textColor = const Color(0xFFE0AF68); // Gold
        break;
      case DiffLineType.context:
        break;
    }

    if (line.type == DiffLineType.hunk) {
      return Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: SelectableText(
          line.text,
          style: TextStyle(
            color: textColor,
            fontFamily: 'monospace',
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (line.type == DiffLineType.header) {
      return Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: SelectableText(
          line.text,
          style: TextStyle(
            color: textColor,
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      );
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gutter: Old Line Number
          Container(
            width: 32,
            padding: const EdgeInsets.only(right: 6),
            alignment: Alignment.centerRight,
            child: Text(
              line.oldLineNum != null ? '${line.oldLineNum}' : '',
              style: TextStyle(
                color: oldNumColor,
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),

          // Gutter: New Line Number
          Container(
            width: 32,
            padding: const EdgeInsets.only(right: 6),
            alignment: Alignment.centerRight,
            child: Text(
              line.newLineNum != null ? '${line.newLineNum}' : '',
              style: TextStyle(
                color: newNumColor,
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),

          // Gutter border
          Container(
            width: 1,
            height: 16,
            color: const Color(0xFF24283B),
            margin: const EdgeInsets.only(right: 8),
          ),

          // Code line text with prefix
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: SelectableText(
              line.text.isEmpty ? ' ' : line.text,
              style: TextStyle(
                color: textColor,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
