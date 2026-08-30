import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/models/preview_entry.dart';
import 'package:workfromphone/screens/preview/preview_browser_screen.dart';
import 'package:workfromphone/services/preview_session.dart';

class ProjectPreviewTab extends StatelessWidget {
  final List<PreviewEntry> entries;
  final String backendUrl;
  final String accessToken;
  final PreviewSessionState connectionState;
  final bool active;

  const ProjectPreviewTab({
    super.key,
    required this.entries,
    required this.backendUrl,
    this.accessToken = '',
    required this.connectionState,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateLabel = switch (connectionState) {
      PreviewSessionState.connecting => 'Connecting…',
      PreviewSessionState.connected => 'Live',
      PreviewSessionState.disconnected => 'Offline',
    };
    final stateColor = switch (connectionState) {
      PreviewSessionState.connected => Colors.green,
      PreviewSessionState.connecting => Colors.amber,
      PreviewSessionState.disconnected => theme.colorScheme.onSurfaceVariant,
    };

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: stateColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                stateLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '${entries.length} target${entries.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context, theme)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    if (entries.isEmpty) {
      return Center(
        key: const Key('preview-empty-state'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.globe,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'No previews registered',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Ask the AI to start a dev server, or use /preview '
                '<port> <label> in the chat to register one manually.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      key: const Key('preview-list'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 48),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          key: Key('preview-entry-${entry.id}'),
          leading: const Icon(CupertinoIcons.globe, size: 22),
          title: Text(
            entry.label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'localhost:${entry.port}'
            '${entry.basePath.isNotEmpty ? ' • ${entry.basePath}' : ''}'
            ' • ${entry.source}',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
          trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PreviewBrowserScreen(
                  backendUrl: backendUrl,
                  accessToken: accessToken,
                  entry: entry,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
