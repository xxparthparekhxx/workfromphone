import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:workfromphone/models/preview_entry.dart';
import 'package:workfromphone/services/api_service.dart';

class PreviewBrowserScreen extends StatefulWidget {
  final String backendUrl;
  final String accessToken;
  final PreviewEntry entry;

  const PreviewBrowserScreen({
    super.key,
    required this.backendUrl,
    required this.accessToken,
    required this.entry,
  });

  @override
  State<PreviewBrowserScreen> createState() => _PreviewBrowserScreenState();
}

class _PreviewBrowserScreenState extends State<PreviewBrowserScreen> {
  late final WebViewController _controller;
  String _currentUrl = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final initial = ApiService.previewUri(
      widget.backendUrl,
      entryId: widget.entry.id,
      path: '/',
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Theme.of(context).colorScheme.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            return ApiService.isPreviewNavigationAllowed(
                  backendUrl: widget.backendUrl,
                  entryId: widget.entry.id,
                  url: request.url,
                )
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _currentUrl = url;
                _isLoading = true;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        ),
      )
      ..loadRequest(initial, headers: _authHeadersFor(initial));
    _currentUrl = initial.toString();
  }

  Map<String, String> _authHeadersFor(Uri uri) {
    final token = widget.accessToken.trim();
    if (token.isEmpty) return const {};
    return ApiService.webSocketAuthHeaders(uri, token);
  }

  Future<void> _reload() async {
    final current = Uri.tryParse(_currentUrl);
    final target =
        current != null &&
            ApiService.isPreviewNavigationAllowed(
              backendUrl: widget.backendUrl,
              entryId: widget.entry.id,
              url: current.toString(),
            )
        ? current
        : ApiService.previewUri(widget.backendUrl, entryId: widget.entry.id);
    await _controller.loadRequest(target, headers: _authHeadersFor(target));
  }

  Future<void> _goHome() async {
    final home = ApiService.previewUri(
      widget.backendUrl,
      entryId: widget.entry.id,
      path: '/',
    );
    await _controller.loadRequest(home, headers: _authHeadersFor(home));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.label, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const Key('preview-go-home'),
            tooltip: 'Go to root',
            icon: const Icon(CupertinoIcons.house, size: 20),
            onPressed: _goHome,
          ),
          IconButton(
            key: const Key('preview-reload'),
            tooltip: 'Reload',
            icon: const Icon(CupertinoIcons.refresh, size: 20),
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Text(
              _currentUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: WebViewWidget(
              key: const Key('preview-webview'),
              controller: _controller,
            ),
          ),
        ],
      ),
    );
  }
}
