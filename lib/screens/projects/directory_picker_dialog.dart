import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/services/api_service.dart';

class DirectoryPickerDialog extends StatefulWidget {
  final String backendUrl;
  final String? initialPath;

  const DirectoryPickerDialog({
    super.key,
    required this.backendUrl,
    this.initialPath,
  });

  static Future<ProjectDirectory?> show(
    BuildContext context, {
    required String backendUrl,
    String? initialPath,
  }) {
    return showModalBottomSheet<ProjectDirectory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DirectoryPickerDialog(
        backendUrl: backendUrl,
        initialPath: initialPath,
      ),
    );
  }

  @override
  State<DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<DirectoryPickerDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  BrowseResult? _browseResult;
  QuickPathsData? _quickPaths;
  String _currentPath = '';
  final TextEditingController _customPathCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath ?? '';
    _loadDirectory(_currentPath);
    _loadQuickPaths();
  }

  @override
  void dispose() {
    _customPathCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQuickPaths() async {
    try {
      final qp = await ApiService.getQuickPaths(widget.backendUrl);
      if (mounted) {
        setState(() {
          _quickPaths = qp;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.browseDirectory(
        widget.backendUrl,
        path: path.isNotEmpty ? path : null,
      );
      if (mounted) {
        setState(() {
          _browseResult = res;
          _currentPath = res.currentPath;
          _customPathCtrl.text = res.currentPath;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _selectCurrentDirectory() {
    if (_browseResult == null) return;
    final path = _browseResult!.currentPath;
    final name =
        path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'Project';

    Navigator.of(context).pop(
      ProjectDirectory(
        name: name,
        path: path,
        projectType: _browseResult!.projectType,
        lastOpened: DateTime.now(),
      ),
    );
  }

  void _selectItem(DirectoryItemData item) {
    if (item.isDir) {
      _loadDirectory(item.path);
    }
  }

  Widget _buildProjectTypeBadge(String? type) {
    if (type == null) return const SizedBox.shrink();
    Color color = Colors.blueGrey;
    IconData icon = CupertinoIcons.folder;

    if (type.contains('flutter') || type.contains('dart')) {
      color = Colors.lightBlue;
      icon = Icons.flutter_dash;
    } else if (type.contains('python')) {
      color = Colors.amber.shade700;
      icon = CupertinoIcons.command;
    } else if (type.contains('node') || type.contains('javascript')) {
      color = Colors.green;
      icon = Icons.javascript;
    } else if (type.contains('rust')) {
      color = Colors.deepOrange;
      icon = CupertinoIcons.gear;
    } else if (type.contains('git')) {
      color = Colors.orange;
      icon = CupertinoIcons.arrow_up_circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            type.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dirsOnly = _browseResult?.items.where((e) => e.isDir).toList() ?? [];

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.folder_open, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Project Directory',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Browse folders on host PC',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Quick shortcuts
            if (_quickPaths != null && _quickPaths!.commonPaths.isNotEmpty)
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _quickPaths!.commonPaths.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final qp = _quickPaths!.commonPaths[index];
                    final isSelected = qp.path == _currentPath;
                    return ActionChip(
                      avatar: const Icon(
                        CupertinoIcons.folder_fill_badge_person_crop,
                        size: 16,
                      ),
                      label: Text(qp.name),
                      backgroundColor: isSelected
                          ? theme.colorScheme.primaryContainer
                          : null,
                      onPressed: () => _loadDirectory(qp.path),
                    );
                  },
                ),
              ),

            // Path & Navigation bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(CupertinoIcons.arrow_up, size: 20),
                    tooltip: 'Parent Folder',
                    onPressed: _browseResult?.parentPath != null
                        ? () => _loadDirectory(_browseResult!.parentPath!)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _customPathCtrl,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        hintText: '/path/to/project',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            CupertinoIcons.arrow_right,
                            size: 18,
                          ),
                          onPressed: () => _loadDirectory(_customPathCtrl.text),
                        ),
                      ),
                      onSubmitted: (val) => _loadDirectory(val),
                    ),
                  ),
                ],
              ),
            ),

            // Current Directory Indicator & Select Button
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.check_mark_circled,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Current Folder',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (_browseResult?.isProject == true)
                              _buildProjectTypeBadge(
                                _browseResult?.projectType,
                              ),
                          ],
                        ),
                        Text(
                          _currentPath.isEmpty ? 'Loading...' : _currentPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _browseResult != null
                        ? _selectCurrentDirectory
                        : null,
                    icon: const Icon(CupertinoIcons.check_mark, size: 18),
                    label: const Text('Select'),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Directory listing
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              CupertinoIcons.exclamationmark_circle,
                              size: 48,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Cannot access folder',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () => _loadDirectory(''),
                              child: const Text('Go to Home'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : dirsOnly.isEmpty
                  ? const Center(
                      child: Text('No subfolders found in this directory'),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: dirsOnly.length,
                      itemBuilder: (context, index) {
                        final item = dirsOnly[index];
                        return ListTile(
                          leading: Icon(
                            item.isProject
                                ? CupertinoIcons.folder_fill_badge_person_crop
                                : CupertinoIcons.folder,
                            color: item.isProject
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: item.isProject
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            item.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.isProject)
                                _buildProjectTypeBadge(item.projectType),
                              const SizedBox(width: 4),
                              const Icon(
                                CupertinoIcons.chevron_right,
                                size: 20,
                              ),
                            ],
                          ),
                          onTap: () => _selectItem(item),
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
