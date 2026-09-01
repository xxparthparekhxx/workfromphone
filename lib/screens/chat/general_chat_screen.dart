import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/models/chat_message.dart';
import 'package:workfromphone/models/conversation_session.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/models/model_info.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/general_chat_service.dart';
import 'package:workfromphone/services/storage_service.dart';
import 'package:workfromphone/widgets/markdown_message_view.dart';
import 'package:workfromphone/widgets/model_picker_sheet.dart';
import 'package:workfromphone/widgets/model_provider_avatar.dart';

class GeneralChatScreen extends StatefulWidget {
  const GeneralChatScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<GeneralChatScreen> createState() => _GeneralChatScreenState();
}

class _GeneralChatScreenState extends State<GeneralChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  final GeneralChatService _chatService = GeneralChatService();

  LLMConfig _llmConfig = const LLMConfig();
  List<ModelInfo> _availableModels = [];
  BackendProfile? _centralHub;
  bool _webSearchEnabled = false;
  bool _isRunning = false;
  bool _autoScroll = true;

  ConversationSession? _currentSession;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _chatService.cancel();
    _inputCtrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GeneralChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _reloadLlmConfig();
    }
  }

  Future<void> _loadState() async {
    final search = await StorageService.loadGeneralChatWebSearchEnabled();
    if (mounted) {
      setState(() => _webSearchEnabled = search);
    }
    await _reloadLlmConfig(fetchModels: false);
    await _initSession();
    _fetchModelsList();
  }

  Future<void> _reloadLlmConfig({bool fetchModels = true}) async {
    final cfg = await StorageService.loadLLMConfig();
    final hub = await StorageService.loadCentralHubProfile();
    ApiService.configureAccessToken(
      cfg.backendAccessToken,
      backendUrl: cfg.backendUrl,
    );
    if (!mounted) return;
    final keepModel = _currentSession?.model ?? _llmConfig.model;
    setState(() {
      _llmConfig = keepModel.isNotEmpty ? cfg.copyWith(model: keepModel) : cfg;
      _centralHub = hub;
    });
    if (fetchModels) {
      await _fetchModelsList();
    }
  }

  Future<void> _initSession() async {
    final activeId = await StorageService.loadActiveGeneralConversationId();
    final list = await StorageService.loadGeneralConversations();
    ConversationSession? session;
    if (activeId != null) {
      session = list.where((c) => c.id == activeId).firstOrNull;
    }
    session ??= list.firstOrNull;

    if (session == null) {
      session = ConversationSession(
        id: 'gen_conv_${DateTime.now().millisecondsSinceEpoch}',
        projectPath: '__general__',
        title: 'New Chat',
        model: _llmConfig.model,
      );
      await StorageService.saveGeneralConversation(session);
      await StorageService.saveActiveGeneralConversationId(session.id);
    }

    if (mounted) {
      setState(() {
        _currentSession = session;
        _llmConfig = _llmConfig.copyWith(model: session!.model);
        _messages.clear();
        _messages.addAll(session.messages);
      });
      _scrollToBottom(force: true, animated: false);
    }
  }

  Future<void> _saveCurrentSession() async {
    if (_currentSession == null) return;
    final updated = _currentSession!.copyWith(
      messages: List.from(_messages),
      updatedAt: DateTime.now(),
      model: _llmConfig.model,
    );
    _currentSession = updated;
    await StorageService.saveGeneralConversation(updated);
    await StorageService.saveActiveGeneralConversationId(updated.id);
  }

  Future<void> _createNewChat() async {
    if (_isRunning) {
      _chatService.cancel();
    }
    await _saveCurrentSession();
    final newSession = ConversationSession(
      id: 'gen_conv_${DateTime.now().millisecondsSinceEpoch}',
      projectPath: '__general__',
      title: 'New Chat',
      model: _llmConfig.model,
    );
    await StorageService.saveGeneralConversation(newSession);
    await StorageService.saveActiveGeneralConversationId(newSession.id);
    if (mounted) {
      setState(() {
        _currentSession = newSession;
        _messages.clear();
        _isRunning = false;
      });
    }
  }

  Future<void> _switchChat(ConversationSession session) async {
    if (_isRunning) {
      _chatService.cancel();
    }
    await _saveCurrentSession();
    await StorageService.saveActiveGeneralConversationId(session.id);
    if (mounted) {
      setState(() {
        _currentSession = session;
        _llmConfig = _llmConfig.copyWith(model: session.model);
        _messages.clear();
        _messages.addAll(session.messages);
        _isRunning = false;
      });
      _scrollToBottom(force: true, animated: false);
    }
  }

  Future<List<ModelInfo>> _fetchModelsList() async {
    try {
      final list = await ApiService.fetchProviderModels(
        backendUrl: _llmConfig.backendUrl,
        baseUrl: _llmConfig.baseUrl,
        apiKey: _llmConfig.apiKey,
      );
      if (mounted && list.isNotEmpty) {
        setState(() => _availableModels = list);
      }
      return list;
    } catch (_) {
      return _availableModels;
    }
  }

  void _scrollToBottom({bool force = false, bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (!force && !_autoScroll) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if (animated) {
        _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  void _showModelPicker() {
    ModelPickerSheet.show(
      context: context,
      selectedModelId: _llmConfig.model,
      availableModels: _availableModels,
      onModelSelected: (m) async {
        final stored = await StorageService.loadLLMConfig();
        final updated = stored.copyWith(model: m.id);
        await StorageService.saveLLMConfig(updated);
        if (!mounted) return;
        setState(() {
          _llmConfig = updated;
          if (_currentSession != null) {
            _currentSession!.model = m.id;
          }
        });
        _saveCurrentSession();
      },
      onRefresh: _fetchModelsList,
    );
  }

  Future<void> _toggleWebSearch() async {
    final next = !_webSearchEnabled;
    setState(() => _webSearchEnabled = next);
    await StorageService.saveGeneralChatWebSearchEnabled(next);
  }

  Future<void> _sendMessage([String? promptOverride]) async {
    final text = (promptOverride ?? _inputCtrl.text).trim();
    if (text.isEmpty || _isRunning) return;

    final stored = await StorageService.loadLLMConfig();
    if (!mounted) return;
    final cfg = stored.copyWith(
      model: _llmConfig.model.isNotEmpty ? _llmConfig.model : stored.model,
    );
    ApiService.configureAccessToken(
      cfg.backendAccessToken,
      backendUrl: cfg.backendUrl,
    );
    setState(() => _llmConfig = cfg);

    if (cfg.apiKey.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please configure your Router API Key in Settings first.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (promptOverride == null) {
      _inputCtrl.clear();
    }

    final userMsg = ChatMessage(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}_u',
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    );

    final assistantMsg = ChatMessage(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}_a',
      role: MessageRole.assistant,
      content: '',
      isStreaming: true,
      timestamp: DateTime.now(),
      statusMessage: _webSearchEnabled
          ? 'Searching web & reasoning...'
          : 'Generating...',
    );

    if (_currentSession != null &&
        (_currentSession!.title == 'New Chat' ||
            _currentSession!.title.isEmpty)) {
      String cleanTitle = text.replaceAll('\n', ' ').trim();
      if (cleanTitle.length > 28) {
        cleanTitle = '${cleanTitle.substring(0, 28)}...';
      }
      _currentSession!.title = cleanTitle;
    }

    setState(() {
      _autoScroll = true;
      _messages.add(userMsg);
      _messages.add(assistantMsg);
      _isRunning = true;
    });

    _saveCurrentSession();
    _scrollToBottom(force: true, animated: true);

    _chatService.runGeneralChat(
      baseUrl: cfg.baseUrl,
      apiKey: cfg.apiKey.trim(),
      backendUrl: cfg.backendUrl,
      backendAccessToken: cfg.backendAccessToken,
      model: cfg.model,
      temperature: cfg.temperature,
      messages: _messages.sublist(0, _messages.length - 1),
      enableWebSearch: _webSearchEnabled,
      onStatus: (status) {
        if (mounted) {
          setState(() {
            assistantMsg.statusMessage = status;
          });
          _scrollToBottom(force: false, animated: false);
        }
      },
      onChunk: (chunk) {
        if (mounted) {
          setState(() {
            assistantMsg.appendChunk(chunk);
          });
          _scrollToBottom(force: false, animated: false);
        }
      },
      onUsage: (_) {},
      onDone: () {
        if (mounted) {
          setState(() {
            _isRunning = false;
            assistantMsg.isStreaming = false;
            assistantMsg.statusMessage = null;
          });
          _saveCurrentSession();
          _scrollToBottom(force: false, animated: true);
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _isRunning = false;
            assistantMsg.isStreaming = false;
            assistantMsg.isError = true;
            assistantMsg.content += '\n\n⚠️ $err';
            assistantMsg.statusMessage = null;
          });
          _saveCurrentSession();
          _scrollToBottom(force: true, animated: true);
        }
      },
    );
  }

  void _stopChat() {
    _chatService.cancel();
    setState(() {
      _isRunning = false;
      for (final msg in _messages.reversed) {
        if (msg.role == MessageRole.assistant && msg.isStreaming) {
          msg.isStreaming = false;
          msg.statusMessage = null;
          break;
        }
      }
    });
    _saveCurrentSession();
  }

  void _openHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FutureBuilder<List<ConversationSession>>(
        future: StorageService.loadGeneralConversations(),
        builder: (context, snapshot) {
          final sessions = snapshot.data ?? [];
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.3,
            expand: false,
            builder: (context, scrollCtrl) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.chat_bubble_2, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Chat History',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          const Spacer(),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _createNewChat();
                            },
                            icon: const Icon(CupertinoIcons.plus, size: 16),
                            label: const Text('New Chat'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    if (sessions.isEmpty)
                      const Expanded(
                        child: Center(child: Text('No previous chats found.')),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollCtrl,
                          itemCount: sessions.length,
                          itemBuilder: (context, idx) {
                            final item = sessions[idx];
                            final isCurrent = item.id == _currentSession?.id;
                            return ListTile(
                              selected: isCurrent,
                              leading: Icon(
                                isCurrent
                                    ? CupertinoIcons.chat_bubble_fill
                                    : CupertinoIcons.chat_bubble,
                                color: isCurrent
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                '${item.model.split('/').lastOrNull ?? item.model} • ${item.messages.length} messages',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  CupertinoIcons.trash,
                                  size: 18,
                                ),
                                onPressed: () async {
                                  await StorageService.deleteGeneralConversation(
                                    item.id,
                                  );
                                  if (isCurrent) {
                                    await _createNewChat();
                                  }
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _switchChat(item);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
      });
      await _saveCurrentSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _clearChat() async {
    if (_messages.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text(
          'Are you sure you want to clear all messages in this conversation?',
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
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _messages.clear();
      });
      await _saveCurrentSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat cleared'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                CupertinoIcons.sparkles,
                size: 38,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'AI General Assistant',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Uses your OpenRouter API key from Settings, with optional live web search.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Suggested Prompts:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(CupertinoIcons.globe, size: 16),
                  label: const Text('Latest AI tech news'),
                  onPressed: () {
                    setState(() => _webSearchEnabled = true);
                    _sendMessage(
                      'What are the most notable recent advancements in AI models this week?',
                    );
                  },
                ),
                ActionChip(
                  avatar: const Icon(CupertinoIcons.search, size: 16),
                  label: const Text('Search documentation'),
                  onPressed: () {
                    setState(() => _webSearchEnabled = true);
                    _sendMessage(
                      'Search Flutter documentation for best practices on WebSocket connection lifecycle.',
                    );
                  },
                ),
                ActionChip(
                  avatar: const Icon(
                    CupertinoIcons.chevron_left_slash_chevron_right,
                    size: 16,
                  ),
                  label: const Text('Write Python script'),
                  onPressed: () => _sendMessage(
                    'Write a Python script that parses JSON data and computes statistical metrics.',
                  ),
                ),
                ActionChip(
                  avatar: const Icon(CupertinoIcons.lightbulb, size: 16),
                  label: const Text('Architect a system'),
                  onPressed: () => _sendMessage(
                    'Explain how to design an event-driven architecture using microservices and Redis streams.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final theme = Theme.of(context);
    final isUser = msg.role == MessageRole.user;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isUser
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isUser
              ? theme.colorScheme.primary.withValues(alpha: 0.2)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isUser ? CupertinoIcons.person_fill : CupertinoIcons.sparkles,
                size: 15,
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.secondary,
              ),
              const SizedBox(width: 6),
              Text(
                isUser
                    ? 'You'
                    : (_llmConfig.model.split('/').lastOrNull ?? 'Assistant'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                tooltip: 'Copy text',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: msg.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  CupertinoIcons.trash,
                  size: 14,
                  color: theme.colorScheme.error.withValues(alpha: 0.8),
                ),
                tooltip: 'Delete message',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _deleteMessage(msg),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (msg.content.isNotEmpty)
            MarkdownMessageView(
              data: msg.content,
              isUser: isUser,
              isStreaming: msg.isStreaming,
            ),
          if (msg.isStreaming && msg.statusMessage != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    msg.statusMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _openHistorySheet,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _currentSession?.title ?? 'General Chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(CupertinoIcons.chevron_down, size: 16),
              ],
            ),
          ),
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(CupertinoIcons.trash, size: 18),
              tooltip: 'Clear Chat',
              onPressed: _clearChat,
            ),
          IconButton(
            icon: const Icon(CupertinoIcons.bubble_left, size: 20),
            tooltip: 'Chat History',
            onPressed: _openHistorySheet,
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.plus_bubble, size: 20),
            tooltip: 'New Chat',
            onPressed: _createNewChat,
          ),
        ],
      ),
      body: Column(
        children: [
          // Control Badges Bar (Model & Web Search Toggle)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.35,
              ),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.25,
                  ),
                ),
              ),
            ),
            child: Row(
              children: [
                // Model selector
                ActionChip(
                  key: const Key('general-chat-model-picker'),
                  avatar: ModelProviderAvatar(
                    modelId: _llmConfig.model,
                    size: 18,
                  ),
                  label: Text(
                    _llmConfig.model.split('/').lastOrNull ?? _llmConfig.model,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _isRunning ? null : _showModelPicker,
                ),

                const SizedBox(width: 8),

                // Web Search Toggle Chip
                FilterChip(
                  key: const Key('general-chat-web-search-chip'),
                  avatar: Icon(
                    CupertinoIcons.globe,
                    size: 15,
                    color: _webSearchEnabled
                        ? Colors.blue
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    _webSearchEnabled ? 'Web Search ON' : 'Web Search OFF',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: _webSearchEnabled
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: _webSearchEnabled ? Colors.blue : null,
                    ),
                  ),
                  selected: _webSearchEnabled,
                  onSelected: (_) => _toggleWebSearch(),
                ),

                const Spacer(),

                if (_centralHub != null)
                  Tooltip(
                    message: 'Connected to Central Hub: ${_centralHub!.name}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.purple.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.cube_box,
                            size: 12,
                            color: Colors.purple,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Hub',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.purple,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Message List or Empty State
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, idx) =>
                        _buildMessageBubble(_messages[idx]),
                  ),
          ),

          // Input Box
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('general-chat-input'),
                      controller: _inputCtrl,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _webSearchEnabled
                            ? 'Ask with live web search...'
                            : 'Ask anything or brainstorm...',
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('general-chat-send-button'),
                    onPressed: _isRunning ? _stopChat : () => _sendMessage(),
                    icon: Icon(
                      _isRunning
                          ? CupertinoIcons.stop
                          : CupertinoIcons.arrow_up,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
