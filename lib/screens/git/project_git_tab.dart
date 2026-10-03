import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:workfromphone/models/git_status.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/theme/app_theme.dart';
import 'package:workfromphone/widgets/app_ui.dart';
import 'package:workfromphone/widgets/git_diff_view.dart';
import 'package:workfromphone/widgets/material_file_icon.dart';

class ProjectGitTab extends StatefulWidget {
  final ProjectDirectory project;
  final String backendUrl;

  const ProjectGitTab({
    super.key,
    required this.project,
    required this.backendUrl,
  });

  @override
  State<ProjectGitTab> createState() => _ProjectGitTabState();
}

class _ProjectGitTabState extends State<ProjectGitTab> {
  final TextEditingController _commitMsgCtrl = TextEditingController();
  final FocusNode _commitFocusNode = FocusNode();
  GitStatusData? _status;
  bool _isLoading = false;
  bool _isCommitting = false;
  bool _isSyncing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _commitMsgCtrl.dispose();
    _commitFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final status = await ApiService.getGitStatus(
        widget.backendUrl,
        projectPath: widget.project.path,
      );
      if (mounted) {
        setState(() {
          _status = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// Documented client limit: diffs above 300 KiB are truncated for display.
  static const _maxDiffChars = 300 * 1024;

  static String _truncateDiff(String diff) {
    if (diff.length <= _maxDiffChars) return diff;
    return '${diff.substring(0, _maxDiffChars)}\n\n… [truncated: diff exceeds the 300 KiB display limit]';
  }

  Future<void> _showDiffModal(String? path, {bool staged = false}) async {
    // Hoisted so rebuilds of the sheet reuse one request instead of
    // refetching the diff on every frame (FutureBuilder refetch loop).
    final diffFuture = ApiService.getGitDiff(
      widget.backendUrl,
      projectPath: widget.project.path,
      relativePath: path,
      staged: staged,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) {
            return FutureBuilder<String>(
              future: diffFuture,
              builder: (context, snapshot) {
                final theme = Theme.of(context);
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            staged
                                ? CupertinoIcons.check_mark_circled
                                : CupertinoIcons.arrow_2_squarepath,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  path != null
                                      ? path.split('/').last
                                      : 'Working Tree Diff',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (path != null)
                                  Text(
                                    path,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(CupertinoIcons.xmark),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Center(child: CircularProgressIndicator())
                          : snapshot.hasError
                          ? Center(
                              child: Text(
                                'Failed to load diff: ${snapshot.error}',
                              ),
                            )
                          : snapshot.data == null || snapshot.data!.isEmpty
                          ? const Center(child: Text('No differences found.'))
                          : GitDiffView(
                              // Documented client limit: huge diffs are
                              // truncated to keep parsing off the OOM path.
                              rawDiff: _truncateDiff(snapshot.data!),
                              scrollController: scrollCtrl,
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _stage(List<String>? paths) async {
    try {
      await ApiService.stageGitFiles(
        widget.backendUrl,
        projectPath: widget.project.path,
        paths: paths,
      );
      _loadStatus();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Stage failed: $e', tone: AppTone.danger);
      }
    }
  }

  Future<void> _unstage(List<String>? paths) async {
    try {
      await ApiService.unstageGitFiles(
        widget.backendUrl,
        projectPath: widget.project.path,
        paths: paths,
      );
      _loadStatus();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Unstage failed: $e', tone: AppTone.danger);
      }
    }
  }

  Future<void> _discard(List<String> paths) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: Text(
          'Are you sure you want to discard changes for ${paths.length} file(s)? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dangerText,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.discardGitChanges(
          widget.backendUrl,
          projectPath: widget.project.path,
          paths: paths,
        );
        _loadStatus();
      } catch (e) {
        if (mounted) {
          showAppSnackBar(context, 'Discard failed: $e', tone: AppTone.danger);
        }
      }
    }
  }

  Future<void> _commit() async {
    final msg = _commitMsgCtrl.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a commit message')),
      );
      return;
    }

    setState(() {
      _isCommitting = true;
    });

    try {
      final hasStaged = (_status?.staged.isNotEmpty ?? false);
      await ApiService.commitGit(
        widget.backendUrl,
        projectPath: widget.project.path,
        message: msg,
        stageAll: !hasStaged, // Auto-stage all if nothing was explicitly staged
      );

      _commitMsgCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Committed successfully!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _loadStatus();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Commit failed: $e', tone: AppTone.danger);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCommitting = false;
        });
      }
    }
  }

  Future<void> _syncPush() async {
    setState(() => _isSyncing = true);
    try {
      await ApiService.pushGit(
        widget.backendUrl,
        projectPath: widget.project.path,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pushed to remote!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _loadStatus();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Push failed: $e', tone: AppTone.danger);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _syncPull() async {
    setState(() => _isSyncing = true);
    try {
      await ApiService.pullGit(
        widget.backendUrl,
        projectPath: widget.project.path,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pulled latest changes!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _loadStatus();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Pull failed: $e', tone: AppTone.danger);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Widget _buildFileRow(GitFileItem file, {required bool isStaged}) {
    final theme = Theme.of(context);
    final statusColor = switch (file.status) {
      'U' || 'A' => AppColors.success,
      'D' => AppColors.dangerText,
      _ => AppColors.warning,
    };

    return InkWell(
      // The same path can appear in both the staged and unstaged lists, so
      // the key must be qualified by which list it belongs to.
      key: ValueKey(isStaged ? 'staged:${file.path}' : 'unstaged:${file.path}'),
      onTap: () => _showDiffModal(file.path, staged: isStaged),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                file.status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            MaterialFileIcon(name: file.fileName, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (file.dirName.isNotEmpty)
                    Text(
                      file.dirName,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isStaged)
              IconButton(
                icon: const Icon(CupertinoIcons.minus, size: 18),
                tooltip: 'Unstage Changes',
                visualDensity: VisualDensity.compact,
                onPressed: () => _unstage([file.path]),
              )
            else ...[
              IconButton(
                icon: const Icon(CupertinoIcons.arrow_uturn_left, size: 17),
                tooltip: 'Discard Changes',
                visualDensity: VisualDensity.compact,
                onPressed: () => _discard([file.path]),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.add, size: 18),
                tooltip: 'Stage Changes',
                visualDensity: VisualDensity.compact,
                onPressed: () => _stage([file.path]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading && _status == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _status == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: EmptyState(
            icon: CupertinoIcons.exclamationmark_circle,
            tone: AppTone.danger,
            title: 'Git error',
            message: _errorMessage,
            action: FilledButton.icon(
              key: const Key('git-retry-button'),
              onPressed: _loadStatus,
              icon: const Icon(CupertinoIcons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ),
        ),
      );
    }

    if (_status != null && !_status!.isRepo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: EmptyState(
            icon: CupertinoIcons.arrow_branch,
            title: 'Not a Git repository',
            message: 'This folder is not initialized with Git.',
            action: FilledButton.icon(
              key: const Key('git-init-button'),
              onPressed: () async {
                await ApiService.runTerminalCommand(
                  widget.backendUrl,
                  projectPath: widget.project.path,
                  command: 'git init',
                );
                _loadStatus();
              },
              icon: const Icon(CupertinoIcons.add, size: 16),
              label: const Text('Initialize Git Repository'),
            ),
          ),
        ),
      );
    }

    final staged = _status?.staged ?? [];
    final unstaged = _status?.unstaged ?? [];
    final untracked = _status?.untracked ?? [];
    final allChanges = [...unstaged, ...untracked];

    return RefreshIndicator(
      onRefresh: _loadStatus,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Branch & Sync Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(CupertinoIcons.arrow_branch, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _status?.branch ?? 'HEAD',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      if (_status?.tracking != null)
                        Text(
                          '↑${_status?.ahead} ↓${_status?.behind}',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(CupertinoIcons.refresh, size: 18),
                        tooltip: 'Refresh Status',
                        visualDensity: VisualDensity.compact,
                        onPressed: _loadStatus,
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSyncing ? null : _syncPull,
                          icon: const Icon(CupertinoIcons.arrow_down, size: 15),
                          label: const Text('Pull'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSyncing ? null : _syncPush,
                          icon: const Icon(CupertinoIcons.arrow_up, size: 15),
                          label: const Text('Push'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Commit Box
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Focus(
                    focusNode: _commitFocusNode,
                    onKeyEvent: (node, event) {
                      // Ctrl+Enter (Cmd+Enter on macOS) commits.
                      final isEnterDown =
                          event is KeyDownEvent &&
                          (event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey ==
                                  LogicalKeyboardKey.numpadEnter);
                      final isModifierDown =
                          HardwareKeyboard.instance.isControlPressed ||
                          HardwareKeyboard.instance.isMetaPressed;
                      if (!isEnterDown || !isModifierDown) {
                        return KeyEventResult.ignored;
                      }
                      if (_isCommitting) return KeyEventResult.ignored;
                      _commit();
                      return KeyEventResult.handled;
                    },
                    child: TextField(
                      key: const Key('git-commit-message-field'),
                      controller: _commitMsgCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Message (Ctrl+Enter to commit)',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('git-commit-button'),
                      onPressed: _isCommitting ? null : _commit,
                      icon: _isCommitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(CupertinoIcons.check_mark, size: 18),
                      label: Text(
                        staged.isNotEmpty
                            ? 'Commit Staged (${staged.length})'
                            : 'Commit All (${allChanges.length})',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Staged Changes Header
          if (staged.isNotEmpty) ...[
            SectionLabel(
              'Staged changes',
              count: staged.length,
              trailing: IconButton(
                icon: const Icon(CupertinoIcons.minus_circle, size: 16),
                tooltip: 'Unstage All',
                visualDensity: VisualDensity.compact,
                onPressed: () => _unstage(null),
              ),
            ),
            Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: staged.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (ctx, idx) =>
                    _buildFileRow(staged[idx], isStaged: true),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Changes & Untracked Files Header
          SectionLabel(
            'Changes',
            count: allChanges.length,
            trailing: allChanges.isEmpty
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          CupertinoIcons.arrow_uturn_left,
                          size: 16,
                        ),
                        tooltip: 'Discard All Changes',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _discard(allChanges.map((f) => f.path).toList()),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.add_circled, size: 16),
                        tooltip: 'Stage All',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _stage(null),
                      ),
                    ],
                  ),
          ),

          if (allChanges.isEmpty && staged.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(
                child: EmptyState(
                  icon: CupertinoIcons.check_mark_circled,
                  tone: AppTone.success,
                  title: 'Working tree clean',
                ),
              ),
            )
          else
            Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: allChanges.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (ctx, idx) =>
                    _buildFileRow(allChanges[idx], isStaged: false),
              ),
            ),
        ],
      ),
    );
  }
}
