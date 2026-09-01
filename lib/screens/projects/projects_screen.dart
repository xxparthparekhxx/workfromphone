import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/screens/chat/conversation_history_sheet.dart';
import 'package:workfromphone/screens/chat/project_chat_screen.dart';
import 'package:workfromphone/screens/projects/directory_picker_dialog.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/storage_service.dart';
import 'package:workfromphone/widgets/add_edit_backend_dialog.dart';
import 'package:workfromphone/widgets/server_picker_sheet.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<ProjectDirectory> _projects = [];
  LLMConfig _llmConfig = const LLMConfig();
  BackendProfile? _activeProfile;
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
    final activeProfile = await StorageService.loadActiveBackendProfile();

    ApiService.configureAccessToken(
      cfg.backendAccessToken,
      backendUrl: cfg.backendUrl,
    );
    final list = await StorageService.loadRecentProjects();
    final online = await ApiService.testServer(cfg.backendUrl);

    if (mounted) {
      setState(() {
        _llmConfig = cfg;
        _activeProfile = activeProfile;
        _projects = list;
        _isServerOnline = online;
        _isLoading = false;
      });
    }
  }

  void _openServerPicker() {
    ServerPickerSheet.show(context, onServerChanged: _loadData);
  }

  Future<void> _addNewServer() async {
    final result = await AddEditBackendDialog.show(context);
    if (result != null) {
      await _loadData();
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
      MaterialPageRoute(builder: (_) => ProjectChatScreen(project: project)),
    );
  }

  void _openConversations(ProjectDirectory project) {
    ConversationHistorySheet.show(
      context,
      project: project,
      activeConversationId: null,
      onSelectConversation: (session) async {
        await StorageService.saveActiveConversationId(project.path, session.id);
        if (mounted) {
          _openChat(project);
        }
      },
      onNewConversation: () {
        _openChat(project);
      },
    );
  }

  Future<void> _removeProject(ProjectDirectory project) async {
    await StorageService.removeRecentProject(project.path);
    await _loadData();
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
        .where(
          (p) =>
              p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              p.path.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    final activeHostName =
        _activeProfile?.name ??
        (_llmConfig.backendUrl.isEmpty
            ? 'Local Host'
            : _llmConfig.backendUrl
                  .replaceAll('http://', '')
                  .replaceAll('https://', ''));

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Projects',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Server status indicator with quick switch action
          InkWell(
            onTap: _openServerPicker,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isServerOnline
                      ? Colors.green.withValues(alpha: 0.4)
                      : Colors.red.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                    _isServerOnline ? 'Host Online' : 'Host Offline',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isServerOnline ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(CupertinoIcons.chevron_down, size: 12),
                ],
              ),
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
                  // Prominent Active Host Switcher Bar
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.desktopcomputer,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _openServerPicker,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      activeHostName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      CupertinoIcons.chevron_down,
                                      size: 12,
                                    ),
                                  ],
                                ),
                                Text(
                                  _llmConfig.backendUrl,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _addNewServer,
                          icon: const Icon(CupertinoIcons.plus, size: 14),
                          label: const Text(
                            'Add Host',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Server connection notice if offline
                  if (!_isServerOnline)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(
                          alpha: 0.7,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.wifi_slash,
                            color: theme.colorScheme.error,
                          ),
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
                                  'Make sure FastAPI is running on your host (${_llmConfig.backendUrl}).',
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
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.5,
                    ),
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
                                  CupertinoIcons.plus_circle,
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
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Select any directory on your computer to begin coding with AI assistance.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
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
                              onPressed: _isServerOnline
                                  ? _pickDirectory
                                  : null,
                              icon: const Icon(
                                CupertinoIcons.folder_badge_plus,
                              ),
                              label: const Text(
                                'Browse & Select Project Directory',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Recent Projects Header
                  Row(
                    children: [
                      const Icon(CupertinoIcons.clock_fill, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Recent Projects',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_projects.isNotEmpty)
                        Text(
                          '${_projects.length} project${_projects.length == 1 ? "" : "s"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Search Bar for recent projects
                  if (_projects.length > 3) ...[
                    TextField(
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Filter recent projects...',
                        prefixIcon: const Icon(CupertinoIcons.search, size: 18),
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Recent Projects List
                  if (_projects.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Icon(
                            CupertinoIcons.folder_badge_minus,
                            size: 48,
                            color: theme.colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No recent projects yet',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Use the button above to select your first workspace folder.',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          'No projects match "$_searchQuery"',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ...filtered.map((project) {
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _openChat(project),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor:
                                      theme.colorScheme.secondaryContainer,
                                  child: Icon(
                                    CupertinoIcons.folder,
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              project.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildProjectTypeBadge(
                                            project.projectType,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        project.path,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontFamily: 'monospace',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    CupertinoIcons.chat_bubble_2,
                                    size: 20,
                                  ),
                                  tooltip: 'Conversation History',
                                  onPressed: () => _openConversations(project),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    CupertinoIcons.delete,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'Remove from Recents',
                                  onPressed: () => _removeProject(project),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}
