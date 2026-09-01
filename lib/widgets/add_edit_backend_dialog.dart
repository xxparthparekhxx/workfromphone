import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/storage_service.dart';

class AddEditBackendDialog extends StatefulWidget {
  final BackendProfile? profile;
  final String? initialToken;

  const AddEditBackendDialog({super.key, this.profile, this.initialToken});

  static Future<BackendProfile?> show(
    BuildContext context, {
    BackendProfile? profile,
    String? initialToken,
  }) {
    return showDialog<BackendProfile>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AddEditBackendDialog(profile: profile, initialToken: initialToken),
    );
  }

  @override
  State<AddEditBackendDialog> createState() => _AddEditBackendDialogState();
}

class _AddEditBackendDialogState extends State<AddEditBackendDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _tokenCtrl;

  bool _obscureToken = true;
  bool _isTesting = false;
  bool? _isOnline;
  bool _setAsActive = true;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(text: p?.name ?? 'My Linux PC');
    _urlCtrl = TextEditingController(
      text: p?.backendUrl ?? 'http://127.0.0.1:8000',
    );
    _tokenCtrl = TextEditingController(text: widget.initialToken ?? '');

    if (p != null && widget.initialToken == null) {
      _loadExistingToken(p.id);
    }
  }

  Future<void> _loadExistingToken(String profileId) async {
    final token = await StorageService.loadBackendSecret(
      profileId,
      'access_token',
    );
    if (token != null && mounted) {
      setState(() {
        _tokenCtrl.text = token;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isTesting = true;
      _isOnline = null;
    });

    ApiService.configureAccessToken(_tokenCtrl.text.trim(), backendUrl: url);
    final online = await ApiService.testServer(url);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _isOnline = online;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    var url = _urlCtrl.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    // Remove trailing slash
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    final id =
        widget.profile?.id ??
        'profile_${DateTime.now().millisecondsSinceEpoch}';
    final token = _tokenCtrl.text.trim();

    final profile = BackendProfile(
      id: id,
      name: _nameCtrl.text.trim().isEmpty
          ? 'Linux Host'
          : _nameCtrl.text.trim(),
      host: url,
      sshPort: 22,
      username: 'user',
      transport: BackendTransport.directHttp,
      type: BackendProfileType.devHost,
      directUrl: url,
      hostKeyType: widget.profile?.hostKeyType ?? '',
      hostKeyFingerprint: widget.profile?.hostKeyFingerprint ?? '',
      architecture: widget.profile?.architecture ?? 'x86_64',
      installedVersion: widget.profile?.installedVersion ?? '1.0.0',
    );

    await StorageService.saveBackendProfile(profile);
    if (token.isNotEmpty) {
      await StorageService.saveBackendSecret(id, 'access_token', token);
    }

    if (_setAsActive) {
      await StorageService.setActiveBackendProfile(id);
      final current = await StorageService.loadLLMConfig();
      final updated = current.copyWith(
        backendUrl: url,
        backendAccessToken: token,
      );
      await StorageService.saveLLMConfig(updated);
      ApiService.configureAccessToken(token, backendUrl: url);
    }

    if (mounted) {
      Navigator.of(context).pop(profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.profile != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isEditing
                ? CupertinoIcons.pencil_circle_fill
                : CupertinoIcons.plus_circle_fill,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(isEditing ? 'Edit Backend Server' : 'Add Backend Server'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Connect to a computer or VPS running the FastAPI backend.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),

              // Server Name
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Server Friendly Name',
                  hintText: 'e.g. Home PC, Cloud VPS, Workstation',
                  prefixIcon: const Icon(CupertinoIcons.tag),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Please enter a name'
                    : null,
              ),

              const SizedBox(height: 12),

              // Backend URL
              TextFormField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'http://192.168.1.50:8000 or https://...',
                  prefixIcon: const Icon(CupertinoIcons.link),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter backend URL';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 8),

              // Quick IP chips
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ActionChip(
                    label: const Text(
                      '127.0.0.1:8000',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => _urlCtrl.text = 'http://127.0.0.1:8000',
                  ),
                  ActionChip(
                    label: const Text(
                      '10.0.2.2:8000 (Emulator)',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => _urlCtrl.text = 'http://10.0.2.2:8000',
                  ),
                  ActionChip(
                    label: const Text(
                      'localhost:8000',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () => _urlCtrl.text = 'http://localhost:8000',
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Access Token
              TextFormField(
                controller: _tokenCtrl,
                obscureText: _obscureToken,
                decoration: InputDecoration(
                  labelText: 'Access Token (Optional)',
                  hintText: 'Configured ACCESS_TOKEN on host',
                  prefixIcon: const Icon(CupertinoIcons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureToken
                          ? CupertinoIcons.eye
                          : CupertinoIcons.eye_slash,
                    ),
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),

              const SizedBox(height: 14),

              // Test Connection Row
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(CupertinoIcons.bolt, size: 16),
                    label: const Text(
                      'Test Connection',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_isOnline != null)
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            _isOnline!
                                ? CupertinoIcons.check_mark_circled_solid
                                : CupertinoIcons.xmark_circle_fill,
                            color: _isOnline! ? Colors.green : Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _isOnline! ? 'Online' : 'Unreachable',
                              style: TextStyle(
                                color: _isOnline! ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // Set as active checkbox
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Set as active server',
                  style: TextStyle(fontSize: 13),
                ),
                value: _setAsActive,
                onChanged: (val) => setState(() => _setAsActive = val ?? true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(CupertinoIcons.check_mark, size: 16),
          label: Text(isEditing ? 'Save Changes' : 'Add Server'),
        ),
      ],
    );
  }
}
