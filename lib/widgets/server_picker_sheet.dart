import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/screens/settings/remote_backend_setup_screen.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/storage_service.dart';
import 'package:workfromphone/widgets/add_edit_backend_dialog.dart';

class ServerPickerSheet extends StatefulWidget {
  final VoidCallback? onServerChanged;

  const ServerPickerSheet({super.key, this.onServerChanged});

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onServerChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ServerPickerSheet(onServerChanged: onServerChanged),
    );
  }

  @override
  State<ServerPickerSheet> createState() => _ServerPickerSheetState();
}

class _ServerPickerSheetState extends State<ServerPickerSheet> {
  List<BackendProfile> _profiles = [];
  BackendProfile? _activeProfile;
  final Map<String, bool?> _onlineStatus = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    final allProfiles = await StorageService.loadBackendProfiles();
    final active = await StorageService.loadActiveBackendProfile();
    final devProfiles = allProfiles.where((p) => !p.isHub).toList();

    if (mounted) {
      setState(() {
        _profiles = devProfiles;
        _activeProfile = active;
        _isLoading = false;
      });
    }

    _testAllProfiles(devProfiles);
  }

  Future<void> _testAllProfiles(List<BackendProfile> profiles) async {
    for (final p in profiles) {
      final token =
          await StorageService.loadBackendSecret(p.id, 'access_token') ?? '';
      ApiService.configureAccessToken(token, backendUrl: p.backendUrl);
      final isOnline = await ApiService.testServer(p.backendUrl);
      if (mounted) {
        setState(() {
          _onlineStatus[p.id] = isOnline;
        });
      }
    }
  }

  Future<void> _selectServer(BackendProfile profile) async {
    await StorageService.setActiveBackendProfile(profile.id);
    final token =
        await StorageService.loadBackendSecret(profile.id, 'access_token') ??
        '';
    final current = await StorageService.loadLLMConfig();
    final updated = current.copyWith(
      backendUrl: profile.backendUrl,
      backendAccessToken: token,
    );
    await StorageService.saveLLMConfig(updated);
    ApiService.configureAccessToken(token, backendUrl: updated.backendUrl);

    if (mounted) {
      setState(() => _activeProfile = profile);
      widget.onServerChanged?.call();
      Navigator.of(context).pop();
    }
  }

  Future<void> _addDirectServer() async {
    final result = await AddEditBackendDialog.show(context);
    if (result != null) {
      await _loadProfiles();
      widget.onServerChanged?.call();
    }
  }

  Future<void> _addSshServer() async {
    final configured = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RemoteBackendSetupScreen()),
    );
    if (configured == true) {
      await _loadProfiles();
      widget.onServerChanged?.call();
    }
  }

  Future<void> _editServer(BackendProfile profile) async {
    final result = await AddEditBackendDialog.show(context, profile: profile);
    if (result != null) {
      await _loadProfiles();
      widget.onServerChanged?.call();
    }
  }

  Future<void> _deleteServer(BackendProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${profile.name}?'),
        content: const Text(
          'This will remove this backend server from your saved profiles.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await StorageService.deleteBackendProfile(profile.id);
      await _loadProfiles();
      widget.onServerChanged?.call();
    }
  }

  Widget _buildTransportBadge(BackendTransport transport) {
    String label = 'Direct HTTP';
    Color color = Colors.teal;
    IconData icon = CupertinoIcons.link;

    if (transport == BackendTransport.sshTunnel) {
      label = 'SSH Tunnel';
      color = Colors.blue;
      icon = CupertinoIcons.shield;
    } else if (transport == BackendTransport.cloudflareTunnel) {
      label = 'Cloudflare';
      color = Colors.orange;
      icon = CupertinoIcons.cloud;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
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

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(CupertinoIcons.desktopcomputer, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Backend Servers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(CupertinoIcons.refresh, size: 18),
                  tooltip: 'Refresh Status',
                  onPressed: () => _testAllProfiles(_profiles),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.wifi_slash,
                    size: 42,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No saved server profiles yet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add your PC or VPS to start coding and running tasks.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _profiles.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (context, idx) {
                  final p = _profiles[idx];
                  final isActive = _activeProfile?.id == p.id;
                  final status = _onlineStatus[p.id];

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          backgroundColor: isActive
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            CupertinoIcons.desktopcomputer,
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: status == true
                                ? Colors.green
                                : (status == false ? Colors.red : Colors.grey),
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name,
                            style: TextStyle(
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          p.backendUrl,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildTransportBadge(p.transport),
                            const SizedBox(width: 8),
                            Text(
                              status == true
                                  ? 'Online'
                                  : (status == false
                                        ? 'Unreachable'
                                        : 'Checking…'),
                              style: TextStyle(
                                fontSize: 11,
                                color: status == true
                                    ? Colors.green
                                    : (status == false
                                          ? Colors.red
                                          : Colors.grey),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(CupertinoIcons.pencil, size: 18),
                          tooltip: 'Edit Server',
                          onPressed: () => _editServer(p),
                        ),
                        IconButton(
                          icon: const Icon(
                            CupertinoIcons.trash,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Remove Server',
                          onPressed: () => _deleteServer(p),
                        ),
                      ],
                    ),
                    onTap: () => _selectServer(p),
                  );
                },
              ),
            ),

          const Divider(height: 1),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addDirectServer,
                    icon: const Icon(CupertinoIcons.plus, size: 16),
                    label: const Text('Add URL / Host'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _addSshServer,
                    icon: const Icon(
                      CupertinoIcons.arrow_down_circle,
                      size: 16,
                    ),
                    label: const Text('Setup via SSH'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
