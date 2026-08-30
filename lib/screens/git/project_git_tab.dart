import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:workfromphone/models/git_status.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/services/api_service.dart';
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

  Future<void> _showDiffModal(String? path, {bool staged = false}) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) {
            return FutureBuilder<String>(
              future: ApiService.getGitDiff(
                widget.backendUrl,
                projectPath: widget.project.path,
                relativePath: path,
                staged: staged,
              ),
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
                              rawDiff: snapshot.data!,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stage failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unstage failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Discard failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Commit failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Push failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pull failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Widget _buildFileRow(GitFileItem file, {required bool isStaged}) {
    final theme = Theme.of(context);
    Color statusColor = Colors.amber;
    if (file.status == 'U' || file.status == 'A') statusColor = Colors.green;
    if (file.status == 'D') statusColor = Colors.red;
    if (file.status == 'M') statusColor = Colors.amber.shade700;

    return InkWell(
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
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 12),
              Text('Git Error', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadStatus,
                icon: const Icon(CupertinoIcons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_status != null && !_status!.isRepo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.doc_plaintext,
                size: 54,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text('Not a Git Repository', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'This folder is not initialized with Git.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await ApiService.runTerminalCommand(
                    widget.backendUrl,
                    projectPath: widget.project.path,
                    command: 'git init',
                  );
                  _loadStatus();
                },
                icon: const Icon(CupertinoIcons.add),
                label: const Text('Initialize Git Repository'),
              ),
            ],
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
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
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
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
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
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isCommitting ? null : _commit,
                      icon: _isCommitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Text(
                    'STAGED CHANGES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${staged.length}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(CupertinoIcons.minus_circle, size: 16),
                    tooltip: 'Unstage All',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _unstage(null),
                  ),
                ],
              ),
            ),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Text(
                  'CHANGES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${allChanges.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                if (allChanges.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(CupertinoIcons.arrow_uturn_left, size: 16),
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
              ],
            ),
          ),

          if (allChanges.isEmpty && staged.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.check_mark_circled,
                    size: 40,
                    color: Colors.green.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Working tree clean',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
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
