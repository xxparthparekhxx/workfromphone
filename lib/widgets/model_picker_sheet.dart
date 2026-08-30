import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:workfromphone/models/model_info.dart';

class ModelPickerSheet extends StatefulWidget {
  final String selectedModelId;
  final List<ModelInfo> availableModels;
  final ValueChanged<ModelInfo> onModelSelected;
  final Future<void> Function()? onRefresh;

  const ModelPickerSheet({
    super.key,
    required this.selectedModelId,
    required this.availableModels,
    required this.onModelSelected,
    this.onRefresh,
  });

  static const List<ModelInfo> defaultCuratedModels = [
    ModelInfo(
      id: 'anthropic/claude-3.7-sonnet',
      name: 'Claude 3.7 Sonnet',
      description: 'Hybrid reasoning and leading code-generation flagship model by Anthropic.',
      contextLength: 200000,
    ),
    ModelInfo(
      id: 'anthropic/claude-3.5-sonnet',
      name: 'Claude 3.5 Sonnet',
      description:
          'Industry-standard coding and autonomous agentic model by Anthropic.',
      contextLength: 200000,
    ),
    ModelInfo(
      id: 'anthropic/claude-3.5-haiku',
      name: 'Claude 3.5 Haiku',
      description: 'Ultra-fast and cost-effective Anthropic model.',
      contextLength: 200000,
    ),
    ModelInfo(
      id: 'anthropic/claude-3-opus',
      name: 'Claude 3 Opus',
      description: 'Deep reasoning and complex synthesis model by Anthropic.',
      contextLength: 200000,
    ),
    ModelInfo(
      id: 'meta-llama/llama-3.3-70b-instruct:free',
      name: 'Llama 3.3 70B Instruct (Free)',
      description: 'Free tier high-performance 70B open-weights model by Meta.',
      contextLength: 131072,
    ),
    ModelInfo(
      id: 'deepseek/deepseek-r1:free',
      name: 'DeepSeek R1 (Free)',
      description: 'Free tier advanced reasoning & chain-of-thought model.',
      contextLength: 64000,
    ),
    ModelInfo(
      id: 'deepseek/deepseek-chat:free',
      name: 'DeepSeek V3 (Free)',
      description: 'Free tier flagship general coding & conversation model.',
      contextLength: 64000,
    ),
    ModelInfo(
      id: 'google/gemini-2.0-flash-exp:free',
      name: 'Gemini 2.0 Flash Exp (Free)',
      description: 'Free experimental ultra-fast multimodal model by Google.',
      contextLength: 1048576,
    ),
    ModelInfo(
      id: 'qwen/qwen-2.5-coder-32b-instruct:free',
      name: 'Qwen 2.5 Coder 32B (Free)',
      description:
          'Free specialized coding model with deep repo understanding.',
      contextLength: 32768,
    ),
    ModelInfo(
      id: 'mistralai/mistral-7b-instruct:free',
      name: 'Mistral 7B Instruct (Free)',
      description: 'Free high-speed lightweight model by Mistral AI.',
      contextLength: 32768,
    ),
    ModelInfo(
      id: 'openai/gpt-4o',
      name: 'GPT-4o',
      description: 'Flagship multimodal omni intelligence model by OpenAI.',
      contextLength: 128000,
    ),
    ModelInfo(
      id: 'openai/gpt-4o-mini',
      name: 'GPT-4o Mini',
      description: 'Fast, compact, and affordable model by OpenAI.',
      contextLength: 128000,
    ),
    ModelInfo(
      id: 'openai/o3-mini',
      name: 'OpenAI o3-mini',
      description: 'Next-gen cost-efficient reasoning model optimized for STEM and coding.',
      contextLength: 200000,
    ),
    ModelInfo(
      id: 'deepseek/deepseek-chat',
      name: 'DeepSeek V3',
      description:
          'Powerful 671B mixture-of-experts model for software development.',
      contextLength: 64000,
    ),
    ModelInfo(
      id: 'deepseek/deepseek-r1',
      name: 'DeepSeek R1',
      description: 'Specialized deep reasoning model with open reflection.',
      contextLength: 64000,
    ),
    ModelInfo(
      id: 'google/gemini-2.0-flash-001',
      name: 'Gemini 2.0 Flash',
      description: 'High-speed 1M context multimodal model by Google.',
      contextLength: 1000000,
    ),
    ModelInfo(
      id: 'meta-llama/llama-3.3-70b-instruct',
      name: 'Llama 3.3 70B Instruct',
      description: 'High-capacity instruction-tuned model by Meta.',
      contextLength: 131072,
    ),
  ];

  static Future<void> show({
    required BuildContext context,
    required String selectedModelId,
    required List<ModelInfo> availableModels,
    required ValueChanged<ModelInfo> onModelSelected,
    Future<void> Function()? onRefresh,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ModelPickerSheet(
        selectedModelId: selectedModelId,
        availableModels: availableModels,
        onModelSelected: onModelSelected,
        onRefresh: onRefresh,
      ),
    );
  }

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedFilter = 'all'; // 'all', 'free', 'anthropic', 'openai', etc.
  bool _isRefreshing = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ModelInfo> get _allModels {
    if (widget.availableModels.isNotEmpty) {
      return widget.availableModels;
    }
    return ModelPickerSheet.defaultCuratedModels;
  }

  List<ModelInfo> get _filteredModels {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filter = _selectedFilter.toLowerCase();

    return _allModels.where((m) {
      // Category filter
      if (filter == 'free') {
        if (!m.isFree) return false;
      } else if (filter == 'anthropic') {
        if (m.provider.toLowerCase() != 'anthropic' &&
            !m.id.toLowerCase().contains('claude')) {
          return false;
        }
      } else if (filter != 'all') {
        if (m.provider.toLowerCase() != filter &&
            !m.id.toLowerCase().startsWith('$filter/')) {
          return false;
        }
      }

      // Search query filter
      if (query.isNotEmpty) {
        final matchesName = m.name.toLowerCase().contains(query);
        final matchesId = m.id.toLowerCase().contains(query);
        final matchesProvider = m.provider.toLowerCase().contains(query);
        final matchesDesc =
            m.description?.toLowerCase().contains(query) ?? false;
        if (!matchesName && !matchesId && !matchesProvider && !matchesDesc) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  int _countForFilter(String filter) {
    final f = filter.toLowerCase();
    if (f == 'all') return _allModels.length;
    if (f == 'free') return _allModels.where((m) => m.isFree).length;
    if (f == 'anthropic') {
      return _allModels
          .where(
            (m) =>
                m.provider.toLowerCase() == 'anthropic' ||
                m.id.toLowerCase().contains('claude'),
          )
          .length;
    }
    return _allModels
        .where(
          (m) =>
              m.provider.toLowerCase() == f ||
              m.id.toLowerCase().startsWith('$f/'),
        )
        .length;
  }

  Widget _buildFilterChip({
    required String id,
    required String label,
    IconData? icon,
    bool isHighlight = false,
  }) {
    final isSelected = _selectedFilter == id;
    final count = _countForFilter(id);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        avatar: icon != null
            ? Icon(
                icon,
                size: 15,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : (isHighlight ? Colors.green : theme.colorScheme.primary),
              )
            : null,
        label: Text(
          count > 0 ? '$label ($count)' : label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? theme.colorScheme.onPrimary
                : (isHighlight ? Colors.green : null),
          ),
        ),
        selected: isSelected,
        selectedColor: theme.colorScheme.primary,
        checkmarkColor: theme.colorScheme.onPrimary,
        backgroundColor: isHighlight
            ? (isSelected
                  ? theme.colorScheme.primary
                  : Colors.green.withValues(alpha: 0.12))
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected
                ? theme.colorScheme.primary
                : (isHighlight
                      ? Colors.green.withValues(alpha: 0.4)
                      : theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.4,
                        )),
          ),
        ),
        onSelected: (selected) {
          setState(() {
            _selectedFilter = selected ? id : 'all';
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredModels;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.lightbulb,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Active Model',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${filtered.length} of ${_allModels.length} models available',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (widget.onRefresh != null)
                    IconButton(
                      icon: _isRefreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(CupertinoIcons.refresh),
                      tooltip: 'Refresh Models from Router',
                      onPressed: _isRefreshing
                          ? null
                          : () async {
                              setState(() {
                                _isRefreshing = true;
                              });
                              try {
                                await widget.onRefresh!();
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isRefreshing = false;
                                  });
                                }
                              }
                            },
                    ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search models by name, ID, or company...',
                  prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(CupertinoIcons.clear, size: 18),
                          onPressed: () {
                            setState(() {
                              _searchCtrl.clear();
                            });
                          },
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onChanged: (_) {
                  setState(() {});
                },
              ),
            ),

            // Filter chips row
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildFilterChip(id: 'all', label: 'All'),
                  _buildFilterChip(
                    id: 'free',
                    label: 'Free Models',
                    icon: CupertinoIcons.bolt,
                    isHighlight: true,
                  ),
                  _buildFilterChip(
                    id: 'anthropic',
                    label: 'Anthropic',
                    icon: CupertinoIcons.sparkles,
                  ),
                  _buildFilterChip(id: 'openai', label: 'OpenAI'),
                  _buildFilterChip(id: 'deepseek', label: 'DeepSeek'),
                  _buildFilterChip(id: 'google', label: 'Google'),
                  _buildFilterChip(id: 'meta', label: 'Meta'),
                  _buildFilterChip(id: 'mistral', label: 'Mistral'),
                  _buildFilterChip(id: 'qwen', label: 'Qwen'),
                ],
              ),
            ),

            const Divider(height: 12),

            // Model items list
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.search,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No models found',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _searchCtrl.text.isNotEmpty
                                  ? 'No matches for "${_searchCtrl.text}"'
                                  : 'No models found in this category.',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _searchCtrl.clear();
                                  _selectedFilter = 'all';
                                });
                              },
                              icon: const Icon(
                                CupertinoIcons.refresh,
                                size: 16,
                              ),
                              label: const Text('Reset Filters'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final m = filtered[index];
                        final isSelected = m.id == widget.selectedModelId;
                        final isFree = m.isFree;
                        final provider = m.provider;
                        final ctxFormatted = m.contextLengthFormatted;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Material(
                            color: isSelected
                                ? theme.colorScheme.primaryContainer.withValues(
                                    alpha: 0.4,
                                  )
                                : theme.colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.3),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              leading: Icon(
                                isSelected
                                    ? CupertinoIcons.check_mark_circled
                                    : CupertinoIcons.circle,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : null,
                                size: 22,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      m.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (isFree)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.green.withValues(
                                            alpha: 0.5,
                                          ),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            CupertinoIcons.bolt,
                                            size: 11,
                                            color: Colors.green,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            'FREE',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    m.id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (m.description != null &&
                                      m.description!.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      m.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          provider,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      if (ctxFormatted != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            ctxFormatted,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onModelSelected(m);
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
