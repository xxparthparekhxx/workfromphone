import 'package:flutter/material.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/models/model_info.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _backendUrlCtrl = TextEditingController();
  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();

  double _temperature = 0.2;
  bool _obscureApiKey = true;
  bool _isTestingBackend = false;
  bool? _backendOnline;
  bool _isFetchingModels = false;
  List<ModelInfo> _modelsList = [];

  final List<Map<String, String>> _providerPresets = [
    {
      'name': 'OpenRouter (Recommended)',
      'url': 'https://openrouter.ai/api/v1',
      'defaultModel': 'anthropic/claude-3.5-sonnet',
    },
    {
      'name': 'OpenAI Official',
      'url': 'https://api.openai.com/v1',
      'defaultModel': 'gpt-4o',
    },
    {
      'name': 'Groq Cloud',
      'url': 'https://api.groq.com/openai/v1',
      'defaultModel': 'llama-3.3-70b-versatile',
    },
    {
      'name': 'Ollama (Local on PC)',
      'url': 'http://127.0.0.1:11434/v1',
      'defaultModel': 'qwen2.5-coder',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _backendUrlCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final cfg = await StorageService.loadLLMConfig();
    setState(() {
      _backendUrlCtrl.text = cfg.backendUrl;
      _baseUrlCtrl.text = cfg.baseUrl;
      _apiKeyCtrl.text = cfg.apiKey;
      _modelCtrl.text = cfg.model;
      _temperature = cfg.temperature;
    });
    _testBackendConnection();
  }

  Future<void> _saveSettings() async {
    final updated = LLMConfig(
      backendUrl: _backendUrlCtrl.text.trim(),
      baseUrl: _baseUrlCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      temperature: _temperature,
    );

    await StorageService.saveLLMConfig(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _testBackendConnection() async {
    setState(() {
      _isTestingBackend = true;
      _backendOnline = null;
    });

    final online = await ApiService.testServer(_backendUrlCtrl.text.trim());
    if (mounted) {
      setState(() {
        _isTestingBackend = false;
        _backendOnline = online;
      });
    }
  }

  Future<void> _fetchModels() async {
    setState(() {
      _isFetchingModels = true;
    });

    try {
      final list = await ApiService.fetchModels(
        _backendUrlCtrl.text.trim(),
        _baseUrlCtrl.text.trim(),
        _apiKeyCtrl.text.trim(),
      );

      if (mounted) {
        setState(() {
          _modelsList = list;
          _isFetchingModels = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded ${list.length} models from router.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingModels = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load models: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _applyProviderPreset(Map<String, String> preset) {
    setState(() {
      _baseUrlCtrl.text = preset['url']!;
      _modelCtrl.text = preset['defaultModel']!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings & Harness',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Settings',
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: PC Backend Connection
          _buildSectionHeader('PC Backend Connection', Icons.computer),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _backendUrlCtrl,
                    decoration: InputDecoration(
                      labelText: 'FastAPI Backend URL',
                      hintText: 'http://127.0.0.1:8000',
                      prefixIcon: const Icon(Icons.link),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('127.0.0.1:8000'),
                        onPressed: () => _backendUrlCtrl.text = 'http://127.0.0.1:8000',
                      ),
                      ActionChip(
                        label: const Text('10.0.2.2:8000 (Android Emulator)'),
                        onPressed: () => _backendUrlCtrl.text = 'http://10.0.2.2:8000',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _isTestingBackend ? null : _testBackendConnection,
                        icon: _isTestingBackend
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.network_ping, size: 18),
                        label: const Text('Test Connection'),
                      ),
                      const SizedBox(width: 12),
                      if (_backendOnline != null)
                        Row(
                          children: [
                            Icon(
                              _backendOnline! ? Icons.check_circle : Icons.cancel,
                              color: _backendOnline! ? Colors.green : Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _backendOnline! ? 'Connected' : 'Unreachable',
                              style: TextStyle(
                                color: _backendOnline! ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section 2: LLM Router & Provider Config
          _buildSectionHeader('LLM Provider & Router', Icons.psychology),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Compatible with OpenRouter or any OpenAI-compatible router/endpoint.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),

                  // Presets
                  const Text(
                    'Quick Presets:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _providerPresets.map((preset) {
                      final isSelected = _baseUrlCtrl.text == preset['url'];
                      return ChoiceChip(
                        label: Text(preset['name']!),
                        selected: isSelected,
                        onSelected: (_) => _applyProviderPreset(preset),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // Base URL
                  TextField(
                    controller: _baseUrlCtrl,
                    decoration: InputDecoration(
                      labelText: 'OpenAI / Router Base URL',
                      hintText: 'https://openrouter.ai/api/v1',
                      prefixIcon: const Icon(Icons.cloud_queue),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // API Key
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: 'Router API Key',
                      hintText: 'sk-or-v1-... or sk-...',
                      prefixIcon: const Icon(Icons.key),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureApiKey = !_obscureApiKey;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Model Selection
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _modelCtrl,
                          decoration: InputDecoration(
                            labelText: 'Selected Model ID',
                            hintText: 'anthropic/claude-3.5-sonnet',
                            prefixIcon: const Icon(Icons.smart_toy),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: _isFetchingModels
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_download_outlined),
                        tooltip: 'Fetch Live Models',
                        onPressed: _isFetchingModels ? null : _fetchModels,
                      ),
                    ],
                  ),

                  // Quick model chips
                  const SizedBox(height: 10),
                  const Text(
                    'Recommended Models:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      'anthropic/claude-3.5-sonnet',
                      'openai/gpt-4o',
                      'openai/gpt-4o-mini',
                      'deepseek/deepseek-chat',
                      'deepseek/deepseek-r1',
                      'meta-llama/llama-3.3-70b-instruct',
                      'google/gemini-2.0-flash-001',
                    ].map((m) {
                      final isSelected = _modelCtrl.text == m;
                      final label = m.split('/').lastOrNull ?? m;
                      return ActionChip(
                        avatar: isSelected ? const Icon(Icons.check, size: 14) : null,
                        label: Text(label),
                        backgroundColor: isSelected
                            ? theme.colorScheme.primaryContainer
                            : null,
                        onPressed: () {
                          setState(() {
                            _modelCtrl.text = m;
                          });
                        },
                      );
                    }).toList(),
                  ),

                  // If fetched models exist, allow picking
                  if (_modelsList.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _modelsList.any((m) => m.id == _modelCtrl.text)
                          ? _modelCtrl.text
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Or choose from fetched models (${_modelsList.length})',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                      items: _modelsList.map((m) {
                        return DropdownMenuItem<String>(
                          value: m.id,
                          child: Text(
                            '${m.name} (${m.id})',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _modelCtrl.text = val;
                          });
                        }
                      },
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Temperature
                  Row(
                    children: [
                      const Text('Temperature:'),
                      const Spacer(),
                      Text(
                        _temperature.toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: _temperature,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label: _temperature.toStringAsFixed(2),
                    onChanged: (val) {
                      setState(() {
                        _temperature = val;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Save Button
          FilledButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: const Text('Save Configuration'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
