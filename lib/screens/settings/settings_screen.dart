import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/models/model_info.dart';
import 'package:workfromphone/screens/settings/on_device_setup_screen.dart';
import 'package:workfromphone/screens/settings/remote_backend_setup_screen.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/remote_setup_service.dart';
import 'package:workfromphone/services/storage_service.dart';
import 'package:workfromphone/theme/app_theme.dart';
import 'package:workfromphone/widgets/add_edit_backend_dialog.dart';
import 'package:workfromphone/widgets/app_ui.dart';
import 'package:workfromphone/widgets/model_picker_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _backendUrlCtrl = TextEditingController();
  final TextEditingController _backendAccessTokenCtrl = TextEditingController();
  final TextEditingController _hubUrlCtrl = TextEditingController();
  final TextEditingController _hubAccessTokenCtrl = TextEditingController();
  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();

  double _temperature = 0.2;
  bool _obscureApiKey = true;
  bool _obscureBackendToken = true;
  bool _obscureHubToken = true;
  bool _isTestingBackend = false;
  bool? _backendOnline;
  bool _isTestingHub = false;
  bool? _hubOnline;
  bool _isFetchingModels = false;
  List<ModelInfo> _modelsList = [];
  BackendProfile? _activeBackendProfile;
  BackendProfile? _centralHubProfile;
  List<BackendProfile> _devProfiles = [];
  bool _isReconnecting = false;
  bool _settingsLoaded = false;

  final List<Map<String, String>> _providerPresets = [
    {
      'name': 'OpenRouter',
      'url': 'https://openrouter.ai/api/v1',
      'defaultModel': 'anthropic/claude-3.5-sonnet',
    },
    {
      'name': 'OpenAI',
      'url': 'https://api.openai.com/v1',
      'defaultModel': 'gpt-4o',
    },
    {
      'name': 'Groq',
      'url': 'https://api.groq.com/openai/v1',
      'defaultModel': 'llama-3.3-70b-versatile',
    },
    {
      'name': 'Ollama (local)',
      'url': 'http://127.0.0.1:11434/v1',
      'defaultModel': 'qwen2.5-coder',
    },
  ];

  static const _suggestedModels = [
    'anthropic/claude-3.7-sonnet',
    'anthropic/claude-3.5-sonnet',
    'meta-llama/llama-3.3-70b-instruct:free',
    'deepseek/deepseek-r1:free',
    'openai/gpt-4o',
    'openai/o3-mini',
    'deepseek/deepseek-chat',
    'google/gemini-2.0-flash-001',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _backendUrlCtrl.dispose();
    _backendAccessTokenCtrl.dispose();
    _hubUrlCtrl.dispose();
    _hubAccessTokenCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive && _settingsLoaded) {
      unawaited(_saveSettings(showConfirmation: false));
    }
  }

  Future<void> _loadSettings() async {
    final cfg = await StorageService.loadLLMConfig();
    final activeProfile = await StorageService.loadActiveBackendProfile();
    final hubProfile = await StorageService.loadCentralHubProfile();
    final allProfiles = await StorageService.loadBackendProfiles();

    String hubToken = '';
    if (hubProfile != null) {
      hubToken =
          await StorageService.loadBackendSecret(
            hubProfile.id,
            'access_token',
          ) ??
          '';
    }

    setState(() {
      _backendUrlCtrl.text = cfg.backendUrl;
      _backendAccessTokenCtrl.text = cfg.backendAccessToken;
      _hubUrlCtrl.text = hubProfile?.backendUrl ?? '';
      _hubAccessTokenCtrl.text = hubToken;
      _baseUrlCtrl.text = cfg.baseUrl;
      _apiKeyCtrl.text = cfg.apiKey;
      _modelCtrl.text = cfg.model;
      _temperature = cfg.temperature;
      _activeBackendProfile = activeProfile;
      _centralHubProfile = hubProfile;
      _devProfiles = allProfiles.where((p) => !p.isHub).toList();
    });
    ApiService.configureAccessToken(
      cfg.backendAccessToken,
      backendUrl: cfg.backendUrl,
    );
    _testBackendConnection();
    if (_hubUrlCtrl.text.isNotEmpty) {
      _testHubConnection();
    }
    _settingsLoaded = true;
  }

  Future<String?> _promptForSshPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SSH password required'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            labelText:
                '${_activeBackendProfile?.username}@'
                '${_activeBackendProfile?.host}',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    controller.dispose();
    return password;
  }

  Future<void> _reconnectSshTunnel() async {
    final profile = _activeBackendProfile;
    if (profile == null ||
        profile.transport != BackendTransport.sshTunnel ||
        _isReconnecting) {
      return;
    }
    var password = await StorageService.loadBackendSecret(
      profile.id,
      'ssh_password',
    );
    password ??= await _promptForSshPassword();
    if (password == null || password.isEmpty || !mounted) return;

    setState(() => _isReconnecting = true);
    try {
      final client = await RemoteSetupService().connectExisting(
        profile,
        password: password,
      );
      final port = await SshTunnelManager.instance.start(client);
      final token =
          await StorageService.loadBackendSecret(profile.id, 'access_token') ??
          '';
      final current = await StorageService.loadLLMConfig();
      final updated = current.copyWith(
        backendUrl: 'http://127.0.0.1:$port',
        backendAccessToken: token,
      );
      await StorageService.saveLLMConfig(updated);
      ApiService.configureAccessToken(token, backendUrl: updated.backendUrl);
      if (!mounted) return;
      setState(() {
        _backendUrlCtrl.text = updated.backendUrl;
        _backendAccessTokenCtrl.text = token;
        _backendOnline = true;
      });
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          'SSH reconnection failed: $error',
          tone: AppTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _isReconnecting = false);
    }
  }

  Future<void> _switchDevProfile(BackendProfile profile) async {
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
    setState(() {
      _activeBackendProfile = profile;
      _backendUrlCtrl.text = updated.backendUrl;
      _backendAccessTokenCtrl.text = token;
    });
    _testBackendConnection();
  }

  Future<void> _addNewDirectServer() async {
    final result = await AddEditBackendDialog.show(context);
    if (result != null) {
      await _loadSettings();
    }
  }

  Future<void> _editProfile(BackendProfile profile) async {
    final result = await AddEditBackendDialog.show(context, profile: profile);
    if (result != null) {
      await _loadSettings();
    }
  }

  Future<void> _deleteProfile(BackendProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${profile.name}?'),
        content: const Text(
          'This will remove the saved server profile from this device.',
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
      await _loadSettings();
    }
  }

  Future<void> _saveSettings({bool showConfirmation = true}) async {
    final backendUrl = _backendUrlCtrl.text.trim();
    final accessToken = _backendAccessTokenCtrl.text.trim();
    final updated = LLMConfig(
      backendUrl: backendUrl,
      baseUrl: _baseUrlCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      temperature: _temperature,
      backendAccessToken: accessToken,
    );

    await StorageService.saveLLMConfig(updated);
    ApiService.configureAccessToken(
      updated.backendAccessToken,
      backendUrl: updated.backendUrl,
    );

    // Save Central Hub if configured
    final hubUrl = _hubUrlCtrl.text.trim();
    final hubToken = _hubAccessTokenCtrl.text.trim();
    if (hubUrl.isNotEmpty) {
      final hub = BackendProfile(
        id: _centralHubProfile?.id ?? 'hub_central',
        name: 'Dedicated Cloud Hub',
        host: hubUrl,
        sshPort: 22,
        username: 'admin',
        transport: BackendTransport.directHttp,
        type: BackendProfileType.centralHub,
        directUrl: hubUrl,
        hostKeyType: '',
        hostKeyFingerprint: '',
        architecture: 'x86_64',
        installedVersion: '1.0.0',
      );
      await StorageService.saveCentralHubProfile(hub);
      if (hubToken.isNotEmpty) {
        await StorageService.saveBackendSecret(
          hub.id,
          'access_token',
          hubToken,
        );
      }
      setState(() => _centralHubProfile = hub);
    } else if (_centralHubProfile != null) {
      await StorageService.deleteCentralHubProfile();
      setState(() => _centralHubProfile = null);
    }

    if (mounted && showConfirmation) {
      if (StorageService.secretsPersistFailed) {
        showAppSnackBar(
          context,
          'Settings saved, but secure storage was unavailable. Secrets were not persisted.',
          tone: AppTone.warning,
        );
      } else {
        showAppSnackBar(context, 'Settings saved', tone: AppTone.success);
      }
    }
  }

  Future<void> _testBackendConnection() async {
    setState(() {
      _isTestingBackend = true;
      _backendOnline = null;
    });

    ApiService.configureAccessToken(
      _backendAccessTokenCtrl.text.trim(),
      backendUrl: _backendUrlCtrl.text.trim(),
    );
    final online = await ApiService.testServer(_backendUrlCtrl.text.trim());
    if (mounted) {
      setState(() {
        _isTestingBackend = false;
        _backendOnline = online;
      });
    }
  }

  Future<void> _testHubConnection() async {
    final url = _hubUrlCtrl.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isTestingHub = true;
      _hubOnline = null;
    });

    final online = await ApiService.testServer(url);
    if (mounted) {
      setState(() {
        _isTestingHub = false;
        _hubOnline = online;
      });
    }
  }

  Future<List<ModelInfo>> _fetchModels() async {
    setState(() {
      _isFetchingModels = true;
    });

    try {
      final current = await StorageService.loadLLMConfig();
      await StorageService.saveLLMConfig(
        current.copyWith(
          baseUrl: _baseUrlCtrl.text.trim(),
          apiKey: _apiKeyCtrl.text.trim(),
          model: _modelCtrl.text.trim(),
        ),
      );

      final list = await ApiService.fetchProviderModels(
        backendUrl: _backendUrlCtrl.text.trim(),
        baseUrl: _baseUrlCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
      );

      if (mounted) {
        setState(() {
          _modelsList = list;
          _isFetchingModels = false;
        });
        showAppSnackBar(context, 'Loaded ${list.length} models from provider');
      }
      return list;
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingModels = false;
        });
        showAppSnackBar(
          context,
          'Failed to load models: $e',
          tone: AppTone.danger,
        );
      }
      return _modelsList;
    }
  }

  void _applyProviderPreset(Map<String, String> preset) {
    setState(() {
      _baseUrlCtrl.text = preset['url']!;
      _modelCtrl.text = preset['defaultModel']!;
    });
  }

  void _openModelPicker() {
    ModelPickerSheet.show(
      context: context,
      selectedModelId: _modelCtrl.text,
      availableModels: _modelsList,
      onRefresh: _fetchModels,
      onModelSelected: (m) {
        setState(() {
          _modelCtrl.text = m.id;
        });
      },
    );
  }

  Future<void> _openSetupScreen(Widget screen) async {
    final configured = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (configured == true) {
      await _loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          Tooltip(
            message: 'Save Settings',
            child: TextButton(
              onPressed: _saveSettings,
              child: const Text('Save'),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          AppSpace.xxl,
        ),
        children: [
          const SectionLabel('Backend'),
          _buildConnectionCard(),
          const SizedBox(height: AppSpace.md),
          _buildSavedServersCard(),
          const SizedBox(height: AppSpace.md),
          _buildSetupCard(),
          const SizedBox(height: AppSpace.xl),
          const SectionLabel('AI provider'),
          _buildProviderCard(),
          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Cloud hub · optional'),
          _buildHubCard(),
        ],
      ),
    );
  }

  Widget _connectionStatus({required bool testing, required bool? online}) {
    if (testing) {
      return const StatusPill(
        label: 'Checking',
        tone: AppTone.neutral,
        busy: true,
      );
    }
    if (online == null) return const SizedBox.shrink();
    return StatusPill(
      label: online ? 'Connected' : 'Unreachable',
      tone: online ? AppTone.success : AppTone.danger,
    );
  }

  Widget _cardTitle(String title, {String? subtitle, Widget? trailing}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _secretToggle(bool obscured, VoidCallback onToggle) {
    return IconButton(
      icon: Icon(
        obscured ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
        size: 18,
      ),
      tooltip: obscured ? 'Show' : 'Hide',
      onPressed: onToggle,
    );
  }

  Widget _buildConnectionCard() {
    final isSshTunnel =
        _activeBackendProfile?.transport == BackendTransport.sshTunnel;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(
              'Active connection',
              subtitle: 'The FastAPI backend this app talks to.',
              trailing: _connectionStatus(
                testing: _isTestingBackend,
                online: _backendOnline,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: _backendUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Backend URL',
                hintText: 'http://127.0.0.1:8000',
                prefixIcon: Icon(CupertinoIcons.link, size: 18),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                ActionChip(
                  label: const Text('127.0.0.1:8000'),
                  onPressed: () =>
                      _backendUrlCtrl.text = 'http://127.0.0.1:8000',
                ),
                ActionChip(
                  label: const Text('10.0.2.2:8000 · emulator'),
                  onPressed: () =>
                      _backendUrlCtrl.text = 'http://10.0.2.2:8000',
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              key: const Key('backend-access-token-field'),
              controller: _backendAccessTokenCtrl,
              obscureText: _obscureBackendToken,
              decoration: InputDecoration(
                labelText: 'Access token (optional)',
                hintText: 'ACCESS_TOKEN configured on the server',
                prefixIcon: const Icon(CupertinoIcons.lock, size: 18),
                suffixIcon: _secretToggle(
                  _obscureBackendToken,
                  () => setState(
                    () => _obscureBackendToken = !_obscureBackendToken,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: _isTestingBackend ? null : _testBackendConnection,
                  icon: const Icon(CupertinoIcons.wifi, size: 16),
                  label: const Text('Test connection'),
                ),
                if (isSshTunnel)
                  OutlinedButton.icon(
                    key: const Key('reconnect-ssh-backend'),
                    onPressed: _isReconnecting ? null : _reconnectSshTunnel,
                    icon: _isReconnecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(CupertinoIcons.arrow_uturn_left, size: 16),
                    label: Text(
                      _isReconnecting ? 'Connecting…' : 'Reconnect SSH tunnel',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedServersCard() {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.sm,
              AppSpace.md,
            ),
            child: _cardTitle(
              'Saved servers',
              trailing: TextButton.icon(
                onPressed: _addNewDirectServer,
                icon: const Icon(CupertinoIcons.plus, size: 14),
                label: const Text('Add'),
              ),
            ),
          ),
          const Divider(),
          if (_devProfiles.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Text(
                'No saved servers yet. Add one by URL, or set up a machine below.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            for (var i = 0; i < _devProfiles.length; i++) ...[
              if (i > 0) const Divider(),
              _buildProfileRow(_devProfiles[i]),
            ],
        ],
      ),
    );
  }

  Widget _buildProfileRow(BackendProfile p) {
    final theme = Theme.of(context);
    final isActive = _activeBackendProfile?.id == p.id;
    return InkWell(
      onTap: () => _switchDevProfile(p),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm,
          AppSpace.xs,
          AppSpace.sm,
        ),
        child: Row(
          children: [
            Icon(
              isActive
                  ? CupertinoIcons.largecircle_fill_circle
                  : CupertinoIcons.circle,
              size: 18,
              color: isActive ? AppColors.primary : AppColors.textMuted,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: AppSpace.sm),
                        const ToneBadge(label: 'Active', tone: AppTone.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.backendUrl} · ${p.transport.name}',
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
              icon: const Icon(CupertinoIcons.pencil, size: 16),
              tooltip: 'Edit Server',
              onPressed: () => _editProfile(p),
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.trash, size: 16),
              color: AppColors.dangerText,
              tooltip: 'Remove Server',
              onPressed: () => _deleteProfile(p),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const IconTile(icon: CupertinoIcons.device_phone_portrait),
            title: const Text('Run backend on this phone'),
            subtitle: const Text('No-PC mode: a Debian container on-device'),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
            onTap: () => _openSetupScreen(const OnDeviceSetupScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const IconTile(icon: CupertinoIcons.desktopcomputer),
            title: const Text('Set up a Linux computer'),
            subtitle: const Text('Install or upgrade the backend over SSH'),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
            onTap: () => _openSetupScreen(const RemoteBackendSetupScreen()),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(
              'Provider',
              subtitle: 'OpenRouter or any OpenAI-compatible endpoint.',
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: _providerPresets.map((preset) {
                return ChoiceChip(
                  label: Text(preset['name']!),
                  selected: _baseUrlCtrl.text == preset['url'],
                  onSelected: (_) => _applyProviderPreset(preset),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: _baseUrlCtrl,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://openrouter.ai/api/v1',
                prefixIcon: Icon(CupertinoIcons.cloud, size: 18),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: 'sk-or-v1-… or sk-…',
                prefixIcon: const Icon(CupertinoIcons.lock, size: 18),
                suffixIcon: _secretToggle(
                  _obscureApiKey,
                  () => setState(() => _obscureApiKey = !_obscureApiKey),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            _cardTitle(
              'Model',
              trailing: TextButton.icon(
                onPressed: _openModelPicker,
                icon: _isFetchingModels
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.search, size: 14),
                label: const Text('Browse all'),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _modelCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Model ID',
                hintText: 'anthropic/claude-3.5-sonnet',
                prefixIcon: Icon(CupertinoIcons.sparkles, size: 18),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: _suggestedModels.map((m) {
                final isFree = m.contains(':free');
                return ChoiceChip(
                  avatar: isFree && _modelCtrl.text != m
                      ? const Icon(
                          CupertinoIcons.bolt_fill,
                          size: 12,
                          color: AppColors.success,
                        )
                      : null,
                  label: Text(m.split('/').lastOrNull ?? m),
                  tooltip: isFree ? '$m · free' : m,
                  selected: _modelCtrl.text == m,
                  onSelected: (_) => setState(() => _modelCtrl.text = m),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpace.xl),
            Row(
              children: [
                Text('Temperature', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  _temperature.toStringAsFixed(2),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            Slider(
              value: _temperature,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              label: _temperature.toStringAsFixed(2),
              onChanged: (val) => setState(() => _temperature = val),
            ),
            Text(
              'Lower is more focused and repeatable; higher is more varied.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHubCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(
              'Cloud hub',
              subtitle:
                  'Powers Firecracker sandboxes, live web search and secure '
                  'artifact sharing.',
              trailing: _connectionStatus(
                testing: _isTestingHub,
                online: _hubOnline,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: _hubUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Hub URL',
                hintText: 'https://hub.example.com',
                prefixIcon: Icon(CupertinoIcons.cube_box, size: 18),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _hubAccessTokenCtrl,
              obscureText: _obscureHubToken,
              decoration: InputDecoration(
                labelText: 'Hub access token (optional)',
                hintText: 'ACCESS_TOKEN configured on the hub',
                prefixIcon: const Icon(CupertinoIcons.lock, size: 18),
                suffixIcon: _secretToggle(
                  _obscureHubToken,
                  () => setState(() => _obscureHubToken = !_obscureHubToken),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            OutlinedButton.icon(
              onPressed: _isTestingHub ? null : _testHubConnection,
              icon: const Icon(CupertinoIcons.bolt, size: 16),
              label: const Text('Test hub'),
            ),
          ],
        ),
      ),
    );
  }
}
