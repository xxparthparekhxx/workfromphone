import 'package:flutter/material.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/screens/chat/project_chat_screen.dart';
import 'package:workfromphone/screens/projects/directory_picker_dialog.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/storage_service.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<ProjectDirectory> _projects = [];
  LLMConfig _llmConfig = const LLMConfig();
  bool _isLoading = true;
  bool _isServerOnline = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final cfg = await StorageService.loadLLMConfig();
    final list = await StorageService.loadRecentProjects();
    final online = await ApiService.testServer(cfg.backendUrl);

    if (mounted) {
      setState(() {
        _llmConfig = cfg;
        _projects = list;
        _isServerOnline = online;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDirectory() async {
    final selected = await DirectoryPickerDialog.show(
      context,
      backendUrl: _llmConfig.backendUrl,
    );

    if (selected != null) {
      await StorageService.saveRecentProject(selected);
      await _loadData();
      if (mounted) {
        _openChat(selected);
      }
    }
  }

  void _openChat(ProjectDirectory project) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectChatScreen(project: project),
      ),
    );
  }

  Future<void> _removeProject(ProjectDirectory project) async {
    await StorageService.removeRecentProject(project.path);
    await _loadData();
  }

  Widget _buildProjectTypeBadge(String? type) {
    if (type == null) return const SizedBox.shrink();
    Color color = Colors.blueGrey;
    IconData icon = Icons.folder;

    if (type.contains('flutter') || type.contains('dart')) {
      color = Colors.lightBlue;
      icon = Icons.flutter_dash;
    } else if (type.contains('python')) {
      color = Colors.amber.shade700;
      icon = Icons.terminal;
    } else if (type.contains('node') || type.contains('javascript')) {
      color = Colors.green;
      icon = Icons.javascript;
    } else if (type.contains('rust')) {
      color = Colors.deepOrange;
      icon = Icons.memory;
    } else if (type.contains('git')) {
      color = Colors.orange;
      icon = Icons.commit;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
    final filtered = _projects
        .where((p) =>
            p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            p.path.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Projects',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Server status indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isServerOnline ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isServerOnline ? 'PC Online' : 'PC Offline',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isServerOnline ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Server connection notice if offline
                  if (!_isServerOnline)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_off, color: theme.colorScheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Backend Server Not Reachable',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onErrorContainer,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Make sure FastAPI is running on your PC (${_llmConfig.backendUrl}).',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Hero Action Card: Pick project
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: theme.colorScheme.primary,
                                child: const Icon(
                                  Icons.add_to_photos_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Work on PC Project',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Select any project root folder on your computer to start chat and tasks.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _pickDirectory,
                              icon: const Icon(Icons.folder_open_rounded),
                              label: const Text('Browse & Select Project Directory'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Search bar
                  if (_projects.isNotEmpty) ...[
                    TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search recent projects...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Recent projects header
                  Row(
                    children: [
                      Text(
                        'Recent Workspaces',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${_projects.length})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (filtered.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Icon(
                              Icons.folder_open_outlined,
                              size: 56,
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No workspaces added yet'
                                  : 'No projects match "$_searchQuery"',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...filtered.map((project) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.terminal_rounded,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  project.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              _buildProjectTypeBadge(project.projectType),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              project.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                                tooltip: 'Open Chat',
                                onPressed: () => _openChat(project),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 20),
                                onSelected: (action) {
                                  if (action == 'chat') {
                                    _openChat(project);
                                  } else if (action == 'remove') {
                                    _removeProject(project);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'chat',
                                    child: Row(
                                      children: [
                                        Icon(Icons.chat_outlined, size: 18),
                                        SizedBox(width: 8),
                                        Text('Open Chat Harness'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Remove', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => _openChat(project),
                        ),
                      );
                    }),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickDirectory,
        icon: const Icon(Icons.add),
        label: const Text('Add Project'),
      ),
    );
  }
}
