import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:workfromphone/models/conversation_session.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/services/storage_service.dart';
import 'package:workfromphone/theme/app_theme.dart';
import 'package:workfromphone/widgets/app_ui.dart';

class ConversationHistorySheet extends StatefulWidget {
  final ProjectDirectory project;
  final String? activeConversationId;
  final ValueChanged<ConversationSession> onSelectConversation;
  final VoidCallback onNewConversation;

  const ConversationHistorySheet({
    super.key,
    required this.project,
    required this.activeConversationId,
    required this.onSelectConversation,
    required this.onNewConversation,
  });

  static Future<void> show(
    BuildContext context, {
    required ProjectDirectory project,
    required String? activeConversationId,
    required ValueChanged<ConversationSession> onSelectConversation,
    required VoidCallback onNewConversation,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ConversationHistorySheet(
        project: project,
        activeConversationId: activeConversationId,
        onSelectConversation: onSelectConversation,
        onNewConversation: onNewConversation,
      ),
    );
  }

  @override
  State<ConversationHistorySheet> createState() =>
      _ConversationHistorySheetState();
}

class _ConversationHistorySheetState extends State<ConversationHistorySheet> {
  List<ConversationSession> _conversations = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);
    final list = await StorageService.loadConversations(widget.project.path);
    if (mounted) {
      setState(() {
        _conversations = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _renameConversation(ConversationSession session) async {
    final textCtrl = TextEditingController(text: session.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Conversation'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Conversation Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textCtrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != session.title) {
      session.title = newTitle;
      session.updatedAt = DateTime.now();
      await StorageService.saveConversation(widget.project.path, session);
      await _loadConversations();
    }
  }

  Future<void> _deleteConversation(ConversationSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: Text(
          'Are you sure you want to delete "${session.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await StorageService.deleteConversation(widget.project.path, session.id);
      await _loadConversations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _conversations.where((c) {
      final q = _searchQuery.toLowerCase();
      return c.title.toLowerCase().contains(q) ||
          c.previewSnippet.toLowerCase().contains(q);
    }).toList();
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textMuted,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Column(
          children: [
            const SizedBox(height: AppSpace.sm),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            SheetHeader(
              title: 'Conversations',
              subtitle: '${widget.project.name} · ${_conversations.length}',
              actions: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.onNewConversation();
                  },
                  icon: const Icon(CupertinoIcons.add, size: 16),
                  label: const Text('New Chat'),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
            ),

            if (_conversations.length > 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  0,
                  AppSpace.lg,
                  AppSpace.md,
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search conversations',
                    prefixIcon: Icon(CupertinoIcons.search, size: 16),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),

            const Divider(),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.xl),
                        child: EmptyState(
                          icon: CupertinoIcons.chat_bubble,
                          title: _searchQuery.isEmpty
                              ? 'No conversations yet'
                              : 'No conversations match "$_searchQuery"',
                          action: _searchQuery.isEmpty
                              ? OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    widget.onNewConversation();
                                  },
                                  icon: const Icon(
                                    CupertinoIcons.add,
                                    size: 16,
                                  ),
                                  label: const Text('Start First Chat'),
                                )
                              : null,
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, idx) {
                        final session = filtered[idx];
                        final isActive =
                            session.id == widget.activeConversationId;

                        return Material(
                          color: isActive
                              ? AppColors.primaryTint
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              widget.onSelectConversation(session);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: isActive
                                        ? AppColors.primary
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(
                                AppSpace.lg - 2,
                                AppSpace.md,
                                AppSpace.xs,
                                AppSpace.md,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                session.title,
                                                style: theme
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      color: isActive
                                                          ? AppColors.primary
                                                          : null,
                                                    ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isActive) ...[
                                              const SizedBox(
                                                width: AppSpace.sm,
                                              ),
                                              const ToneBadge(
                                                label: 'Active',
                                                tone: AppTone.primary,
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          session.previewSnippet,
                                          style: theme.textTheme.bodySmall,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: AppSpace.sm),
                                        Text(
                                          '${session.messages.length} msgs · '
                                          '${session.formattedTime} · '
                                          '${session.model.split('/').last}',
                                          style: metaStyle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Conversation actions',
                                    icon: const Icon(
                                      CupertinoIcons.ellipsis,
                                      size: 18,
                                    ),
                                    onSelected: (val) {
                                      if (val == 'rename') {
                                        _renameConversation(session);
                                      } else if (val == 'delete') {
                                        _deleteConversation(session);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'rename',
                                        child: Row(
                                          children: [
                                            Icon(
                                              CupertinoIcons.pencil,
                                              size: 16,
                                            ),
                                            SizedBox(width: AppSpace.sm),
                                            Text('Rename'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              CupertinoIcons.trash,
                                              size: 16,
                                              color: AppColors.dangerText,
                                            ),
                                            SizedBox(width: AppSpace.sm),
                                            Text(
                                              'Delete',
                                              style: TextStyle(
                                                color: AppColors.dangerText,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
