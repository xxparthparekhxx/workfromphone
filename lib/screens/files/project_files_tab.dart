import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/utils/tokyo_night_theme.dart';
import 'package:workfromphone/widgets/code_editor_view.dart';
import 'package:workfromphone/widgets/material_file_icon.dart';

class ProjectFilesTab extends StatefulWidget {
  final ProjectDirectory project;
  final String backendUrl;

  const ProjectFilesTab({
    super.key,
    required this.project,
    required this.backendUrl,
  });

  @override
  State<ProjectFilesTab> createState() => _ProjectFilesTabState();
}

class _ProjectFilesTabState extends State<ProjectFilesTab> {
  String _currentPath = '';
  List<DirectoryItemData> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Active file editor state
  String? _activeFilePath;
  final TokyoNightCodeController _fileEditorCtrl = TokyoNightCodeController();
  bool _isSavingFile = false;
  bool _isTransferring = false;
  bool _isEditorDirty = false;
  String _originalContent = '';

  @override
  void initState() {
    super.initState();
    _currentPath = widget.project.path;
    _loadDirectory(_currentPath);
  }

  @override
  void dispose() {
    _fileEditorCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.browseDirectory(
        widget.backendUrl,
        path: path,
      );
      if (mounted) {
        setState(() {
          _currentPath = res.currentPath;
          _items = res.items;
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

  Future<void> _openFile(String path) async {
    final relPath = path.startsWith(widget.project.path)
        ? path
              .substring(widget.project.path.length)
              .replaceFirst(RegExp(r'^/+'), '')
        : path;

    setState(() {
      _isLoading = true;
    });

    try {
      final fileData = await ApiService.readFile(
        widget.backendUrl,
        projectPath: widget.project.path,
        relativePath: relPath,
      );

      if (mounted) {
        setState(() {
          _activeFilePath = relPath;
          _fileEditorCtrl.text = fileData.content;
          _originalContent = fileData.content;
          _isEditorDirty = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveCurrentFile() async {
    if (_activeFilePath == null) return;
    setState(() => _isSavingFile = true);

    try {
      await ApiService.writeFile(
        widget.backendUrl,
        projectPath: widget.project.path,
        relativePath: _activeFilePath!,
        content: _fileEditorCtrl.text,
      );

      if (mounted) {
        setState(() {
          _originalContent = _fileEditorCtrl.text;
          _isEditorDirty = false;
          _isSavingFile = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File saved successfully!'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingFile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _createNewItem({required bool isDir}) async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDir ? 'New Folder' : 'New File'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isDir ? 'folder_name' : 'filename.dart',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final relDir = _currentPath.startsWith(widget.project.path)
          ? _currentPath
                .substring(widget.project.path.length)
                .replaceFirst(RegExp(r'^/+'), '')
          : '';
      final fullRelPath = relDir.isEmpty ? name : '$relDir/$name';

      try {
        await ApiService.createItem(
          widget.backendUrl,
          projectPath: widget.project.path,
          relativePath: fullRelPath,
          isDir: isDir,
        );
        _loadDirectory(_currentPath);
        if (!isDir) {
          _openFile('${widget.project.path}/$fullRelPath');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Creation failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _relativeDirectory() {
    return _currentPath.startsWith(widget.project.path)
        ? _currentPath
              .substring(widget.project.path.length)
              .replaceFirst(RegExp(r'^/+'), '')
        : '';
  }

  String _relativeFilePath(String path) {
    return path.startsWith(widget.project.path)
        ? path
              .substring(widget.project.path.length)
              .replaceFirst(RegExp(r'^/+'), '')
        : path;
  }

  Future<List<UploadFileData>> _uploadSources(
    List<PlatformFile> pickedFiles,
  ) async {
    final sources = <UploadFileData>[];
    for (final file in pickedFiles) {
      sources.add(
        UploadFileData(
          name: file.name,
          size: await file.length(),
          stream: file.readAsByteStream(),
        ),
      );
    }
    return sources;
  }

  Future<void> _uploadFiles() async {
    final pickedFiles = await FilePicker.pickFiles(
      dialogTitle:
          'Upload files to ${_relativeDirectory().isEmpty ? '/' : _relativeDirectory()}',
    );
    if (pickedFiles.isEmpty || !mounted) return;

    setState(() => _isTransferring = true);
    try {
      Future<List<String>> upload({bool overwrite = false}) async {
        return ApiService.uploadFiles(
          widget.backendUrl,
          projectPath: widget.project.path,
          relativeDirectory: _relativeDirectory(),
          files: await _uploadSources(pickedFiles),
          overwrite: overwrite,
        );
      }

      List<String> uploaded;
      try {
        uploaded = await upload();
      } catch (error) {
        if (!mounted ||
            !error.toString().toLowerCase().contains('already exists')) {
          rethrow;
        }
        final overwrite = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace existing files?'),
            content: const Text(
              'One or more files already exist in this directory.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (overwrite != true) return;
        uploaded = await upload(overwrite: true);
      }

      if (!mounted) return;
      await _loadDirectory(_currentPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploaded.length == 1
                ? '${uploaded.first.split('/').last} uploaded'
                : '${uploaded.length} files uploaded',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  Future<void> _downloadFile(DirectoryItemData item) async {
    if (item.isDir || _isTransferring) return;
    setState(() => _isTransferring = true);
    try {
      final uri = ApiService.fileDownloadUri(
        widget.backendUrl,
        projectPath: widget.project.path,
        relativePath: _relativeFilePath(item.path),
      );
      final savedTo = await FileSaver.instance.saveFile(
        name: item.name,
        includeExtension: false,
        mimeType: MimeType.other,
        link: LinkDetails(
          link: uri.toString(),
          headers: ApiService.headers(uri: uri),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.name} saved to $savedTo'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  Future<void> _deleteItem(DirectoryItemData item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${item.isDir ? 'Folder' : 'File'}?'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final relPath = item.path.startsWith(widget.project.path)
          ? item.path
                .substring(widget.project.path.length)
                .replaceFirst(RegExp(r'^/+'), '')
          : item.name;

      try {
        await ApiService.deleteItem(
          widget.backendUrl,
          projectPath: widget.project.path,
          relativePath: relPath,
        );
        if (_activeFilePath == relPath) {
          setState(() => _activeFilePath = null);
        }
        _loadDirectory(_currentPath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If an editor is active, show Code Editor view
    if (_activeFilePath != null) {
      return Column(
        children: [
          // Editor Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(CupertinoIcons.back, size: 20),
                  tooltip: 'Back to File Explorer',
                  onPressed: () {
                    if (_isEditorDirty) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Unsaved Changes'),
                          content: const Text(
                            'You have unsaved changes. Discard and exit?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Keep Editing'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                setState(() => _activeFilePath = null);
                              },
                              child: const Text('Discard'),
                            ),
                          ],
                        ),
                      );
                    } else {
                      setState(() => _activeFilePath = null);
                    }
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _activeFilePath!.split('/').last,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_isEditorDirty) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.amber,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _activeFilePath!,
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
                  icon: const Icon(CupertinoIcons.arrow_uturn_left, size: 18),
                  tooltip: 'Reset Changes',
                  onPressed: _isEditorDirty
                      ? () {
                          setState(() {
                            _fileEditorCtrl.text = _originalContent;
                            _isEditorDirty = false;
                          });
                        }
                      : null,
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _isSavingFile || !_isEditorDirty
                      ? null
                      : _saveCurrentFile,
                  icon: _isSavingFile
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(CupertinoIcons.arrow_down_doc, size: 16),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

          // Code Text Area with Line Numbers & Tokyo Night Syntax Highlighting
          Expanded(
            child: CodeEditorView(
              controller: _fileEditorCtrl,
              onChanged: (val) {
                final isDirty = val != _originalContent;
                if (_isEditorDirty != isDirty && mounted) {
                  setState(() {
                    _isEditorDirty = isDirty;
                  });
                }
              },
            ),
          ),
        ],
      );
    }

    // Otherwise show File Explorer View
    final isRoot = _currentPath == widget.project.path;
    final relCurrent = _currentPath.startsWith(widget.project.path)
        ? _currentPath
              .substring(widget.project.path.length)
              .replaceFirst(RegExp(r'^/+'), '')
        : '';

    return Column(
      children: [
        // Action Bar (Breadcrumbs + New File/Folder + Refresh)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            children: [
              if (!isRoot)
                IconButton(
                  icon: const Icon(CupertinoIcons.arrow_up, size: 18),
                  tooltip: 'Go to parent directory',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final parent = _currentPath.substring(
                      0,
                      _currentPath.lastIndexOf('/'),
                    );
                    if (parent.startsWith(widget.project.path)) {
                      _loadDirectory(parent);
                    }
                  },
                ),
              Expanded(
                child: Text(
                  relCurrent.isEmpty ? '/' : '/$relCurrent',
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('file-upload-button'),
                icon: _isTransferring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.cloud_upload, size: 18),
                tooltip: 'Upload files',
                visualDensity: VisualDensity.compact,
                onPressed: _isTransferring ? null : _uploadFiles,
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.doc_text, size: 18),
                tooltip: 'New File',
                visualDensity: VisualDensity.compact,
                onPressed: () => _createNewItem(isDir: false),
              ),
              IconButton(
                icon: const Icon(
                  CupertinoIcons.folder_fill_badge_plus,
                  size: 18,
                ),
                tooltip: 'New Folder',
                visualDensity: VisualDensity.compact,
                onPressed: () => _createNewItem(isDir: true),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.refresh, size: 18),
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
                onPressed: () => _loadDirectory(_currentPath),
              ),
            ],
          ),
        ),

        // Files & Folders List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : _items.isEmpty
              ? const Center(child: Text('This folder is empty.'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, indent: 48),
                  itemBuilder: (context, idx) {
                    final item = _items[idx];
                    return ListTile(
                      leading: MaterialFileIcon(
                        name: item.name,
                        isDir: item.isDir,
                        size: 22,
                      ),
                      title: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: item.isDir
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: !item.isDir && item.sizeBytes != null
                          ? Text(
                              _formatSize(item.sizeBytes),
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : null,
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(CupertinoIcons.ellipsis, size: 18),
                        onSelected: (val) {
                          if (val == 'delete') {
                            _deleteItem(item);
                          } else if (val == 'download') {
                            _downloadFile(item);
                          } else if (val == 'copy_path') {
                            Clipboard.setData(ClipboardData(text: item.path));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Path copied to clipboard'),
                              ),
                            );
                          }
                        },
                        itemBuilder: (ctx) => [
                          if (!item.isDir)
                            const PopupMenuItem(
                              value: 'download',
                              child: Row(
                                children: [
                                  Icon(CupertinoIcons.cloud_download, size: 16),
                                  SizedBox(width: 8),
                                  Text('Download'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'copy_path',
                            child: Row(
                              children: [
                                Icon(CupertinoIcons.doc_on_doc, size: 16),
                                SizedBox(width: 8),
                                Text('Copy Path'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  CupertinoIcons.trash,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        if (item.isDir) {
                          _loadDirectory(item.path);
                        } else {
                          _openFile(item.path);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
