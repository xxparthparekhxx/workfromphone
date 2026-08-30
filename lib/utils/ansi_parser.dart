import 'package:flutter/material.dart';

class AnsiParser {
  static const Color defaultForeground = Color(0xFFC0CAF5); // Tokyo Night FG

  // Standard ANSI 16 colors (Tokyo Night theme map)
  static const Map<int, Color> ansiColors = {
    // Normal colors
    30: Color(0xFF15161E), // Black
    31: Color(0xFFF7768E), // Red
    32: Color(0xFF9ECE6A), // Green
    33: Color(0xFFE0AF68), // Yellow
    34: Color(0xFF7AA2F7), // Blue
    35: Color(0xFFBB9AF7), // Magenta
    36: Color(0xFF7DCFFF), // Cyan
    37: Color(0xFFA9B1D6), // White
    // Bright colors
    90: Color(0xFF565F89), // Bright Black (Grey)
    91: Color(0xFFFF9E9E), // Bright Red
    92: Color(0xFFB9F27C), // Bright Green
    93: Color(0xFFFFD580), // Bright Yellow
    94: Color(0xFF89DDFF), // Bright Blue
    95: Color(0xFFD2A6FF), // Bright Magenta
    96: Color(0xFF00E8C6), // Bright Cyan
    97: Color(0xFFC0CAF5), // Bright White
  };

  static const Map<int, Color> ansiBackgrounds = {
    40: Color(0xFF15161E),
    41: Color(0x3DF7768E),
    42: Color(0x3D9ECE6A),
    43: Color(0x3DE0AF68),
    44: Color(0x3D7AA2F7),
    45: Color(0x3DBB9AF7),
    46: Color(0x3D7DCFFF),
    47: Color(0x3DA9B1D6),
  };

  static List<TextSpan> parse(
    String text, {
    TextStyle baseStyle = const TextStyle(
      color: defaultForeground,
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.35,
    ),
  }) {
    if (!text.contains('\x1B')) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final spans = <TextSpan>[];
    final regex = RegExp(r'\x1B\[([0-9;]*)m');
    int lastIndex = 0;

    Color currentFg = baseStyle.color ?? defaultForeground;
    Color? currentBg;
    bool isBold = false;
    bool isDim = false;
    bool isItalic = false;
    bool isUnderline = false;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        final chunk = text.substring(lastIndex, match.start);
        spans.add(
          TextSpan(
            text: chunk,
            style: baseStyle.copyWith(
              color: isDim ? currentFg.withValues(alpha: 0.6) : currentFg,
              backgroundColor: currentBg,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
              decoration: isUnderline
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
          ),
        );
      }

      final codeStr = match.group(1) ?? '0';
      final codes = codeStr.isEmpty
          ? [0]
          : codeStr.split(';').map((e) => int.tryParse(e) ?? 0).toList();

      for (final code in codes) {
        if (code == 0) {
          // Reset
          currentFg = baseStyle.color ?? defaultForeground;
          currentBg = null;
          isBold = false;
          isDim = false;
          isItalic = false;
          isUnderline = false;
        } else if (code == 1) {
          isBold = true;
        } else if (code == 2) {
          isDim = true;
        } else if (code == 3) {
          isItalic = true;
        } else if (code == 4) {
          isUnderline = true;
        } else if (ansiColors.containsKey(code)) {
          currentFg = ansiColors[code]!;
        } else if (ansiBackgrounds.containsKey(code)) {
          currentBg = ansiBackgrounds[code];
        }
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      final chunk = text.substring(lastIndex);
      spans.add(
        TextSpan(
          text: chunk,
          style: baseStyle.copyWith(
            color: isDim ? currentFg.withValues(alpha: 0.6) : currentFg,
            backgroundColor: currentBg,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
            decoration: isUnderline
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
        ),
      );
    }

    return spans;
  }
}
