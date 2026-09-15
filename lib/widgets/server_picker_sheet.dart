import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/screens/settings/remote_backend_setup_screen.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/storage_service.dart';
import 'package:workfromphone/theme/app_theme.dart';
import 'package:workfromphone/widgets/add_edit_backend_dialog.dart';
import 'package:workfromphone/widgets/app_ui.dart';

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
      showDragHandle: true,
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
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
    return switch (transport) {
      BackendTransport.sshTunnel => const ToneBadge(
        label: 'SSH tunnel',
        icon: CupertinoIcons.shield,
      ),
      BackendTransport.cloudflareTunnel => const ToneBadge(
        label: 'Cloudflare',
        icon: CupertinoIcons.cloud,
      ),
      _ => const ToneBadge(label: 'Direct', icon: CupertinoIcons.link),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Backend Servers',
          subtitle: 'Choose which host this app works against.',
          actions: [
            IconButton(
              icon: const Icon(CupertinoIcons.refresh, size: 18),
              tooltip: 'Refresh Status',
              onPressed: () => _testAllProfiles(_profiles),
            ),
          ],
        ),
        const Divider(),

        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(AppSpace.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_profiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpace.xl),
            child: Center(
              child: EmptyState(
                icon: CupertinoIcons.wifi_slash,
                title: 'No saved servers yet',
                message:
                    'Add your PC or VPS to start coding and running tasks.',
              ),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _profiles.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, idx) {
                final p = _profiles[idx];
                final isActive = _activeProfile?.id == p.id;
                final status = _onlineStatus[p.id];
                final tone = status == true
                    ? AppTone.success
                    : (status == false ? AppTone.danger : AppTone.neutral);

                return InkWell(
                  onTap: () => _selectServer(p),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg,
                      AppSpace.md,
                      AppSpace.xs,
                      AppSpace.md,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isActive
                              ? CupertinoIcons.largecircle_fill_circle
                              : CupertinoIcons.circle,
                          size: 18,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      p.name,
                                      style: theme.textTheme.titleSmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isActive) ...[
                                    const SizedBox(width: AppSpace.sm),
                                    const ToneBadge(
                                      label: 'Active',
                                      tone: AppTone.primary,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.backendUrl,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSpace.xs),
                              Wrap(
                                spacing: AppSpace.sm,
                                runSpacing: AppSpace.xs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  StatusPill(
                                    label: status == true
                                        ? 'Online'
                                        : (status == false
                                              ? 'Unreachable'
                                              : 'Checking'),
                                    tone: tone,
                                  ),
                                  _buildTransportBadge(p.transport),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(CupertinoIcons.pencil, size: 16),
                          tooltip: 'Edit Server',
                          onPressed: () => _editServer(p),
                        ),
                        IconButton(
                          icon: const Icon(CupertinoIcons.trash, size: 16),
                          color: AppColors.dangerText,
                          tooltip: 'Remove Server',
                          onPressed: () => _deleteServer(p),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

        const Divider(),

        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addDirectServer,
                    icon: const Icon(CupertinoIcons.plus, size: 16),
                    label: const Text('Add URL / Host'),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: FilledButton.icon(
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
        ),
      ],
    );
  }
}
