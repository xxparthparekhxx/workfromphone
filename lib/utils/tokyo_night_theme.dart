import 'package:flutter/material.dart';

class TokyoNightColors {
  // Tokyo Night Theme Palette
  static const Color background = Color(0xFF1A1B26);
  static const Color surface = Color(0xFF1F2335);
  static const Color gutterBg = Color(0xFF16161E);
  static const Color gutterText = Color(0xFF565F89);
  static const Color currentLineGutter = Color(0xFF7AA2F7);
  static const Color foreground = Color(0xFFC0CAF5);

  // Syntax tokens
  static const Color keyword = Color(0xFFBB9AF7); // Purple
  static const Color cyan = Color(0xFF7DCFFF); // Light Cyan
  static const Color function = Color(0xFF7AA2F7); // Blue
  static const Color string = Color(0xFF9ECE6A); // Green
  static const Color number = Color(0xFFFF9E64); // Orange
  static const Color constant = Color(0xFFFF9E64); // Orange / Booleans
  static const Color type = Color(0xFFE0AF68); // Yellow / Amber
  static const Color comment = Color(0xFF565F89); // Muted Slate
  static const Color annotation = Color(0xFFF7768E); // Coral / Red
  static const Color operator_ = Color(0xFF89DDFF); // Soft Cyan
  static const Color tag = Color(0xFFF7768E); // Coral
  static const Color attribute = Color(0xFFBB9AF7);
  static const Color selection = Color(0xFF283457);
}

class TokyoNightCodeController extends TextEditingController {
  final String? language;

  TokyoNightCodeController({super.text, this.language});

  // Regex patterns for syntax highlighting
  static final RegExp _commentPattern = RegExp(
    r'(//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/)',
  );
  static final RegExp _stringPattern = RegExp(
    r'("""[\s\S]*?"""|'
    ''
    r"'''[\s\S]*?'''|"
    r'"([^"\\]|\\.)*"|'
    r"'([^'\\]|\\.)*'|`([^`\\]|\\.)*`)",
  );
  static final RegExp _numberPattern = RegExp(
    r'\b(0x[0-9a-fA-F]+|\d+(\.\d+)?([eE][+-]?\d+)?)\b',
  );
  static final RegExp _keywordPattern = RegExp(
    r'\b(abstract|as|assert|async|await|break|case|catch|class|const|continue|covariant|'
    r'default|deferred|def|del|do|dynamic|elif|else|enum|export|extends|extension|'
    r'external|factory|false|final|finally|fn|for|from|function|get|hide|if|implements|'
    r'import|in|is|lambda|late|let|library|mixin|new|nil|none|None|null|of|on|operator|'
    r'part|pass|print|pub|raise|rethrow|return|self|set|show|static|struct|super|'
    r'switch|sync|this|throw|true|try|type|typedef|var|void|while|with|yield)\b',
  );
  static final RegExp _typePattern = RegExp(r'\b([A-Z][a-zA-Z0-9_]*)\b');
  static final RegExp _annotationPattern = RegExp(r'(@[a-zA-Z0-9_]+)');
  static final RegExp _functionCallPattern = RegExp(
    r'\b([a-zA-Z_][a-zA-Z0-9_]*)\s*(?=\()',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle =
        style ??
        const TextStyle(
          color: TokyoNightColors.foreground,
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.45,
        );

    final rawText = text;
    if (rawText.isEmpty) {
      return TextSpan(style: baseStyle, text: '');
    }

    final spans = <InlineSpan>[];

    // Build tokenized spans using RegExp matching
    // Token priority: Comments -> Strings -> Annotations -> Keywords / Types -> Numbers -> Functions -> Plain text
    final combinedRegex = RegExp(
      '(${_commentPattern.pattern})|'
      '(${_stringPattern.pattern})|'
      '(${_annotationPattern.pattern})|'
      '(${_keywordPattern.pattern})|'
      '(${_numberPattern.pattern})|'
      '(${_typePattern.pattern})|'
      '(${_functionCallPattern.pattern})',
      multiLine: true,
    );

    int lastMatchEnd = 0;
    for (final match in combinedRegex.allMatches(rawText)) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: rawText.substring(lastMatchEnd, match.start),
            style: baseStyle,
          ),
        );
      }

      final matchedText = match.group(0)!;
      TextStyle tokenStyle = baseStyle;

      if (_commentPattern.hasMatch(matchedText) &&
          (matchedText.startsWith('//') ||
              matchedText.startsWith('#') ||
              matchedText.startsWith('/*'))) {
        tokenStyle = baseStyle.copyWith(
          color: TokyoNightColors.comment,
          fontStyle: FontStyle.italic,
        );
      } else if (matchedText.startsWith('"') ||
          matchedText.startsWith("'") ||
          matchedText.startsWith('`')) {
        tokenStyle = baseStyle.copyWith(color: TokyoNightColors.string);
      } else if (matchedText.startsWith('@')) {
        tokenStyle = baseStyle.copyWith(
          color: TokyoNightColors.annotation,
          fontWeight: FontWeight.bold,
        );
      } else if (_keywordPattern.hasMatch(matchedText) &&
          RegExp(r'^(true|false|null|None|nil)$').hasMatch(matchedText)) {
        tokenStyle = baseStyle.copyWith(
          color: TokyoNightColors.constant,
          fontWeight: FontWeight.w600,
        );
      } else if (_keywordPattern.hasMatch(matchedText)) {
        tokenStyle = baseStyle.copyWith(
          color: TokyoNightColors.keyword,
          fontWeight: FontWeight.bold,
        );
      } else if (_numberPattern.hasMatch(matchedText) &&
          RegExp(r'^\d').hasMatch(matchedText)) {
        tokenStyle = baseStyle.copyWith(color: TokyoNightColors.number);
      } else if (_typePattern.hasMatch(matchedText) &&
          matchedText[0].toUpperCase() == matchedText[0]) {
        tokenStyle = baseStyle.copyWith(
          color: TokyoNightColors.type,
          fontWeight: FontWeight.w600,
        );
      } else {
        tokenStyle = baseStyle.copyWith(color: TokyoNightColors.function);
      }

      spans.add(TextSpan(text: matchedText, style: tokenStyle));
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < rawText.length) {
      spans.add(
        TextSpan(text: rawText.substring(lastMatchEnd), style: baseStyle),
      );
    }

    return TextSpan(style: baseStyle, children: spans);
  }
}
