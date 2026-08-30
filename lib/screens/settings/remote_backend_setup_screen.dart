import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/remote_setup_service.dart';
import 'package:workfromphone/services/storage_service.dart';

class RemoteBackendSetupScreen extends StatefulWidget {
  const RemoteBackendSetupScreen({super.key});

  @override
  State<RemoteBackendSetupScreen> createState() =>
      _RemoteBackendSetupScreenState();
}

class _RemoteBackendSetupScreenState extends State<RemoteBackendSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'Development PC');
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _cloudflareHostnameController = TextEditingController();
  final _cloudflareTokenController = TextEditingController();
  final _setupService = RemoteSetupService();

  BackendTransport _transport = BackendTransport.sshTunnel;
  bool _rememberPassword = false;
  bool _obscurePassword = true;
  bool _obscureTunnelToken = true;
  bool _installing = false;
  String? _error;
  final List<String> _progress = [];

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _cloudflareHostnameController.dispose();
    _cloudflareTokenController.dispose();
    super.dispose();
  }

  bool get _looksPrivate {
    final host = _hostController.text.trim();
    final address = InternetAddress.tryParse(host);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return host == 'localhost' || host.endsWith('.local');
    }
    final parts = address.address.split('.').map(int.parse).toList();
    return parts[0] == 10 ||
        parts[0] == 127 ||
        (parts[0] == 192 && parts[1] == 168) ||
        (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31);
  }

  Future<bool> _verifyHostKey(String type, String fingerprint) async {
    final profiles = await StorageService.loadBackendProfiles();
    final matching = profiles.where(
      (profile) =>
          profile.host == _hostController.text.trim() &&
          profile.sshPort == int.tryParse(_portController.text.trim()),
    );
    if (matching.isNotEmpty &&
        matching.first.hostKeyFingerprint == fingerprint &&
        matching.first.hostKeyType == type) {
      return true;
    }
    if (!mounted) return false;

    final changed = matching.isNotEmpty;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: Icon(
              changed
                  ? CupertinoIcons.exclamationmark_triangle
                  : CupertinoIcons.lock,
              color: changed ? Colors.orange : null,
            ),
            title: Text(changed ? 'SSH host key changed' : 'Trust this host?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  changed
                      ? 'The saved identity for this host does not match. '
                            'Only continue if the server was reinstalled or its '
                            'SSH keys were intentionally rotated.'
                      : 'Confirm this fingerprint against the Linux host '
                            'before continuing.',
                ),
                const SizedBox(height: 14),
                SelectableText(
                  '$type\n$fingerprint',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(changed ? 'Trust new key' : 'Trust host'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _install() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _installing = true;
      _error = null;
      _progress.clear();
    });

    final request = RemoteSetupRequest(
      name: _nameController.text,
      host: _hostController.text.trim(),
      sshPort: int.parse(_portController.text.trim()),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      rememberPassword: _rememberPassword,
      transport: _transport,
      cloudflareHostname: _transport == BackendTransport.cloudflareTunnel
          ? _cloudflareHostnameController.text.trim()
          : null,
      cloudflareTunnelToken: _transport == BackendTransport.cloudflareTunnel
          ? _cloudflareTokenController.text.trim()
          : null,
    );

    try {
      final result = await _setupService.install(
        request: request,
        verifyHostKey: _verifyHostKey,
        onProgress: (message) {
          if (mounted) setState(() => _progress.add(message));
        },
      );
      var backendUrl = result.profile.backendUrl;
      if (result.sshClient != null) {
        final port = await SshTunnelManager.instance.start(result.sshClient!);
        backendUrl = 'http://127.0.0.1:$port';
      }

      await StorageService.saveBackendProfile(result.profile);
      await StorageService.saveBackendSecret(
        result.profile.id,
        'access_token',
        result.backendAccessToken,
      );
      if (_rememberPassword) {
        await StorageService.saveBackendSecret(
          result.profile.id,
          'ssh_password',
          request.password,
        );
      }

      final config = await StorageService.loadLLMConfig();
      final updated = config.copyWith(
        backendUrl: backendUrl,
        backendAccessToken: result.backendAccessToken,
      );
      await StorageService.saveLLMConfig(updated);
      ApiService.configureAccessToken(
        result.backendAccessToken,
        backendUrl: backendUrl,
      );

      if (!mounted) return;
      setState(() {
        _installing = false;
        _progress.add('Connected securely at $backendUrl');
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Linux backend is ready.')));
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final privateHost = _looksPrivate;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up Linux backend')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'Connect over SSH, verify the server identity, and install the '
              'matching WorkFromPhone backend release.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('remote-name-field'),
              controller: _nameController,
              enabled: !_installing,
              decoration: const InputDecoration(
                labelText: 'Computer name',
                prefixIcon: Icon(CupertinoIcons.desktopcomputer),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('remote-host-field'),
              controller: _hostController,
              enabled: !_installing,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
              decoration: const InputDecoration(
                labelText: 'SSH host or IP address',
                hintText: '192.168.1.20 or server.example.com',
                prefixIcon: Icon(CupertinoIcons.cube_box),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: const Key('remote-user-field'),
                    controller: _usernameController,
                    enabled: !_installing,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Required'
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(CupertinoIcons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _portController,
                    enabled: !_installing,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final port = int.tryParse(value ?? '');
                      return port == null || port < 1 || port > 65535
                          ? 'Invalid'
                          : null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('remote-password-field'),
              controller: _passwordController,
              enabled: !_installing,
              obscureText: _obscurePassword,
              validator: (value) =>
                  value == null || value.isEmpty ? 'Required' : null,
              decoration: InputDecoration(
                labelText: 'SSH password',
                prefixIcon: const Icon(CupertinoIcons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? CupertinoIcons.eye
                        : CupertinoIcons.eye_slash,
                  ),
                ),
              ),
            ),
            CheckboxListTile(
              value: _rememberPassword,
              onChanged: _installing
                  ? null
                  : (value) =>
                        setState(() => _rememberPassword = value ?? false),
              contentPadding: EdgeInsets.zero,
              title: const Text('Remember password securely'),
              subtitle: const Text(
                'Stored in the platform Keychain/Keystore for reconnection.',
              ),
            ),
            const SizedBox(height: 10),
            Text('Connection after setup', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<BackendTransport>(
              segments: const [
                ButtonSegment(
                  value: BackendTransport.sshTunnel,
                  icon: Icon(CupertinoIcons.lock),
                  label: Text('SSH tunnel'),
                ),
                ButtonSegment(
                  value: BackendTransport.cloudflareTunnel,
                  icon: Icon(CupertinoIcons.cloud),
                  label: Text('Cloudflare'),
                ),
              ],
              selected: {_transport},
              onSelectionChanged: _installing
                  ? null
                  : (selection) => setState(() => _transport = selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              privateHost
                  ? 'Private address detected. SSH works on this network; '
                        'choose Cloudflare for access away from home.'
                  : 'SSH tunnel keeps the backend bound to localhost and '
                        'does not expose its API port publicly.',
              style: theme.textTheme.bodySmall,
            ),
            if (_transport == BackendTransport.cloudflareTunnel) ...[
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('cloudflare-hostname-field'),
                controller: _cloudflareHostnameController,
                enabled: !_installing,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
                decoration: const InputDecoration(
                  labelText: 'Mapped Cloudflare hostname',
                  hintText: 'dev.example.com',
                  prefixIcon: Icon(CupertinoIcons.globe),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('cloudflare-token-field'),
                controller: _cloudflareTokenController,
                enabled: !_installing,
                obscureText: _obscureTunnelToken,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Named tunnel token',
                  prefixIcon: const Icon(CupertinoIcons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscureTunnelToken = !_obscureTunnelToken,
                    ),
                    icon: Icon(
                      _obscureTunnelToken
                          ? CupertinoIcons.eye
                          : CupertinoIcons.eye_slash,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Create the named tunnel and map this hostname to '
                'http://localhost:8000 in Cloudflare first. The token is sent '
                'only to this host.',
                style: TextStyle(fontSize: 11),
              ),
            ],
            if (_progress.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _progress
                        .map(
                          (message) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '› $message',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('install-remote-backend'),
              onPressed: _installing ? null : _install,
              icon: _installing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.arrow_down_circle),
              label: Text(
                _installing ? 'Installing securely…' : 'Connect and install',
              ),
            ),
            if (RemoteSetupService.releaseRepository.isEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Developer note: WFP_BACKEND_RELEASE_REPO is not configured '
                'in this build.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
