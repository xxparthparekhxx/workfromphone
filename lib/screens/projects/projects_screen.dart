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
import 'package:workfromphone/theme/app_theme.dart';
import 'package:workfromphone/widgets/add_edit_backend_dialog.dart';
import 'package:workfromphone/widgets/app_ui.dart';
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
  bool _isCheckingServer = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final cfg = await StorageService.loadLLMConfig();
    final activeProfile = await StorageService.loadActiveBackendProfile();

    ApiService.configureAccessToken(
      cfg.backendAccessToken,
      backendUrl: cfg.backendUrl,
    );
    final list = await StorageService.loadRecentProjects();
    if (!mounted) return;

    // Show local data right away; the reachability probe can take seconds
    // when the host is offline, so only the host status waits on it.
    setState(() {
      _llmConfig = cfg;
      _activeProfile = activeProfile;
      _projects = list;
      _isLoading = false;
      _isCheckingServer = true;
    });

    final online = await ApiService.testServer(cfg.backendUrl);
    if (mounted) {
      setState(() {
        _isServerOnline = online;
        _isCheckingServer = false;
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

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.toLowerCase();
    final filtered = _projects
        .where(
          (p) =>
              p.name.toLowerCase().contains(query) ||
              p.path.toLowerCase().contains(query),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.md,
                  AppSpace.lg,
                  AppSpace.xxl,
                ),
                children: [
                  const SectionLabel('Host'),
                  _buildHostCard(),
                  const SizedBox(height: AppSpace.xl),
                  _buildOpenProjectCard(),
                  const SizedBox(height: AppSpace.xl),
                  SectionLabel(
                    'Recent',
                    count: _projects.isEmpty ? null : _projects.length,
                  ),
                  if (_projects.length > 3) ...[
                    TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: const InputDecoration(
                        hintText: 'Filter projects',
                        prefixIcon: Icon(CupertinoIcons.search, size: 16),
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                  ],
                  if (_projects.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
                      child: Center(
                        child: EmptyState(
                          icon: CupertinoIcons.folder,
                          title: 'No recent projects',
                          message: 'Projects you open will show up here.',
                        ),
                      ),
                    )
                  else if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.xl),
                      child: Center(
                        child: Text(
                          'No projects match "$_searchQuery"',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < filtered.length; i++) ...[
                            if (i > 0) const Divider(),
                            _buildProjectRow(filtered[i]),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildHostCard() {
    final theme = Theme.of(context);
    final url = _llmConfig.backendUrl;
    final hostName =
        _activeProfile?.name ??
        (url.isEmpty
            ? 'No host configured'
            : url.replaceAll('http://', '').replaceAll('https://', ''));

    return Card(
      child: Column(
        children: [
          InkWell(
            key: const Key('projects-host-card'),
            onTap: _openServerPicker,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.md,
                AppSpace.xs,
                AppSpace.md,
              ),
              child: Row(
                children: [
                  const IconTile(icon: CupertinoIcons.desktopcomputer),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                hostName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            const SizedBox(width: AppSpace.sm),
                            StatusPill(
                              label: _isCheckingServer
                                  ? 'Checking'
                                  : _isServerOnline
                                  ? 'Online'
                                  : 'Offline',
                              tone: _isCheckingServer
                                  ? AppTone.neutral
                                  : _isServerOnline
                                  ? AppTone.success
                                  : AppTone.danger,
                            ),
                          ],
                        ),
                        // Without a profile name the title already is the URL.
                        if (url.isNotEmpty && _activeProfile != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.plus, size: 18),
                    tooltip: 'Add host',
                    onPressed: _addNewServer,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: AppSpace.sm),
                    child: Icon(
                      CupertinoIcons.chevron_up_chevron_down,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_isServerOnline && !_isCheckingServer) ...[
            const Divider(),
            Container(
              color: AppTone.danger.container,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    CupertinoIcons.wifi_slash,
                    size: 16,
                    color: AppColors.dangerText,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      url.isEmpty
                          ? 'Add a host to start working on projects.'
                          : 'Can\'t reach the backend. Make sure it\'s running, '
                                'then pull down to retry.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOpenProjectCard() {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: _isServerOnline
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Open a project', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Pick a folder on your host to chat with the agent, edit files, '
              'run terminals and manage git.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('projects-browse-button'),
                onPressed: _isServerOnline ? _pickDirectory : null,
                icon: const Icon(CupertinoIcons.folder_badge_plus, size: 18),
                label: const Text('Browse folders'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectRow(ProjectDirectory project) {
    final theme = Theme.of(context);
    final type = project.projectType;
    return InkWell(
      onTap: () => _openChat(project),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.md,
          AppSpace.sm,
          AppSpace.xs,
          AppSpace.sm,
        ),
        child: Row(
          children: [
            const IconTile(icon: CupertinoIcons.folder, size: 32),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (type != null) ...[
                        const SizedBox(width: AppSpace.sm),
                        ToneBadge(label: type),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    project.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.clock, size: 18),
              tooltip: 'Conversation history',
              onPressed: () => _openConversations(project),
            ),
            PopupMenuButton<String>(
              tooltip: 'More actions',
              icon: const Icon(CupertinoIcons.ellipsis, size: 18),
              onSelected: (value) {
                if (value == 'remove') _removeProject(project);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.minus_circle,
                        size: 16,
                        color: AppColors.dangerText,
                      ),
                      SizedBox(width: AppSpace.sm),
                      Text(
                        'Remove from recents',
                        style: TextStyle(color: AppColors.dangerText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
