import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/models/preview_entry.dart';
import 'package:workfromphone/screens/preview/preview_browser_screen.dart';
import 'package:workfromphone/services/preview_session.dart';
import 'package:workfromphone/theme/app_theme.dart';
import 'package:workfromphone/widgets/app_ui.dart';

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
    final stateTone = switch (connectionState) {
      PreviewSessionState.connected => AppTone.success,
      PreviewSessionState.connecting => AppTone.warning,
      PreviewSessionState.disconnected => AppTone.neutral,
    };

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.sm,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              StatusDot(tone: stateTone),
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
      return const Center(
        key: Key('preview-empty-state'),
        child: Padding(
          padding: EdgeInsets.all(AppSpace.xl),
          child: EmptyState(
            icon: CupertinoIcons.globe,
            title: 'No previews registered',
            message:
                'Ask the agent to start a dev server, or type /preview '
                '<port> <label> in chat to register one manually.',
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
