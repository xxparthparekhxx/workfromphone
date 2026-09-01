import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// A custom Markdown viewer widget optimized for chat messages and streaming LLM responses.
class MarkdownMessageView extends StatelessWidget {
  final String data;
  final bool isUser;
  final bool isStreaming;
  final TextStyle? textStyle;

  const MarkdownMessageView({
    super.key,
    required this.data,
    this.isUser = false,
    this.isStreaming = false,
    this.textStyle,
  });

  Future<void> _handleLinkTap(BuildContext context, String url) async {
    var cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    // Clean trailing punctuation attached by markdown or text parsers
    cleanUrl = cleanUrl.replaceAll(RegExp(r'[\)\]\.\,]+$'), '');

    var uri = Uri.tryParse(cleanUrl);
    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid URL: $url'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!uri.hasScheme) {
      uri = Uri.tryParse('https://$cleanUrl');
    }

    if (uri == null) return;

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open link: $url'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final defaultTextColor = theme.colorScheme.onSurface;

    final baseStyle =
        textStyle ??
        TextStyle(color: defaultTextColor, fontSize: 14.5, height: 1.45);

    final codeBlockBackground = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7)
        : const Color(0xFF1E1E2E);

    final codeBlockTextColor = isDark
        ? theme.colorScheme.onSurface
        : const Color(0xFFCDD6F4);

    final styleSheet = GptMarkdownStyleSheet(
      codeBlock: CodeBlockStyle(
        backgroundColor: codeBlockBackground,
        textColor: codeBlockTextColor,
        borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        borderWidth: 1,
        borderRadius: const Radius.circular(8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        headerPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        showCopyButton: true,
        showLanguageLabel: true,
        languageStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isDark ? theme.colorScheme.primary : const Color(0xFF89B4FA),
        ),
      ),
      inlineCode: InlineCodeStyle(
        fontSizeFactor: 0.92,
        color: isDark ? theme.colorScheme.primary : theme.colorScheme.primary,
        backgroundColor: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        borderRadius: const Radius.circular(4),
      ),
      link: LinkStyle(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
        fontWeight: FontWeight.w600,
      ),
      blockQuote: BlockQuoteStyle(
        barColor: theme.colorScheme.primary,
        barWidth: 3.5,
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      ),
      table: TableStyle(
        borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        headerBackground: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
      ),
    );

    return SelectionArea(
      child: GptMarkdown(
        data,
        style: baseStyle,
        isStreaming: isStreaming,
        useDollarSignsForLatex: true,
        styleSheet: styleSheet,
        onLinkTap: (url, title) => _handleLinkTap(context, url),
        onCodeCopy: (code) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Code copied to clipboard'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }
}
