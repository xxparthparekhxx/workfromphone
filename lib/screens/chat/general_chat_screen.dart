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
import 'package:workfromphone/theme/app_theme.dart';
import 'package:workfromphone/widgets/app_ui.dart';
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
      showAppSnackBar(
        context,
        'Please configure your Router API Key in Settings first.',
        tone: AppTone.warning,
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
              return Column(
                children: [
                  const SizedBox(height: AppSpace.sm),
                  Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  SheetHeader(
                    title: 'Chat history',
                    subtitle: '${sessions.length} chats',
                    actions: [
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _createNewChat();
                        },
                        icon: const Icon(CupertinoIcons.plus, size: 16),
                        label: const Text('New Chat'),
                      ),
                      const SizedBox(width: AppSpace.sm),
                    ],
                  ),
                  const Divider(),
                  if (sessions.isEmpty)
                    const Expanded(
                      child: Center(
                        child: EmptyState(
                          icon: CupertinoIcons.chat_bubble,
                          title: 'No previous chats',
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        controller: scrollCtrl,
                        itemCount: sessions.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, idx) {
                          final item = sessions[idx];
                          final isCurrent = item.id == _currentSession?.id;
                          return ListTile(
                            selected: isCurrent,
                            title: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                            subtitle: Text(
                              '${item.model.split('/').lastOrNull ?? item.model} · ${item.messages.length} messages',
                            ),
                            trailing: IconButton(
                              icon: const Icon(CupertinoIcons.trash, size: 16),
                              color: AppColors.dangerText,
                              tooltip: 'Delete chat',
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
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
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
        showAppSnackBar(
          context,
          'Message deleted',
          duration: const Duration(seconds: 1),
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
        showAppSnackBar(
          context,
          'Chat cleared',
          duration: const Duration(seconds: 1),
        );
      }
    }
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xxl,
        AppSpace.lg,
        AppSpace.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EmptyState(
                icon: CupertinoIcons.sparkles,
                tone: AppTone.primary,
                title: 'Ask anything',
                message:
                    'Chat with your AI provider. Turn on web search for '
                    'up-to-date answers.',
              ),
              const SizedBox(height: AppSpace.xl),
              const SectionLabel('Try'),
              PromptSuggestion(
                icon: CupertinoIcons.globe,
                label: 'Latest AI news',
                onTap: () {
                  setState(() => _webSearchEnabled = true);
                  _sendMessage(
                    'What are the most notable recent advancements in AI models this week?',
                  );
                },
              ),
              PromptSuggestion(
                icon: CupertinoIcons.search,
                label: 'Search documentation',
                onTap: () {
                  setState(() => _webSearchEnabled = true);
                  _sendMessage(
                    'Search Flutter documentation for best practices on WebSocket connection lifecycle.',
                  );
                },
              ),
              PromptSuggestion(
                icon: CupertinoIcons.chevron_left_slash_chevron_right,
                label: 'Write a Python script',
                onTap: () => _sendMessage(
                  'Write a Python script that parses JSON data and computes statistical metrics.',
                ),
              ),
              PromptSuggestion(
                icon: CupertinoIcons.lightbulb,
                label: 'Architect a system',
                onTap: () => _sendMessage(
                  'Explain how to design an event-driven architecture using microservices and Redis streams.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.role == MessageRole.user;

    return MessageShell(
      isUser: isUser,
      leading: isUser
          ? const Icon(
              CupertinoIcons.person_fill,
              size: 14,
              color: AppColors.textMuted,
            )
          : ModelProviderAvatar(modelId: _llmConfig.model, size: 18),
      label: isUser
          ? 'You'
          : (_llmConfig.model.split('/').lastOrNull ?? 'Assistant'),
      actions: [
        if (!isUser && msg.isStreaming)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.sm),
            child: SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
        if (msg.content.isNotEmpty && !msg.isStreaming) ...[
          CompactIconButton(
            icon: CupertinoIcons.doc_on_doc,
            tooltip: 'Copy text',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: msg.content));
              showAppSnackBar(
                context,
                'Copied to clipboard',
                duration: const Duration(seconds: 1),
              );
            },
          ),
          CompactIconButton(
            icon: CupertinoIcons.trash,
            tooltip: 'Delete message',
            onPressed: () => _deleteMessage(msg),
          ),
        ],
      ],
      children: [
        if (msg.content.isNotEmpty)
          MarkdownMessageView(
            data: msg.content,
            isUser: isUser,
            isStreaming: msg.isStreaming,
          ),
        if (msg.isStreaming && msg.statusMessage != null) ...[
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  msg.statusMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpace.sm,
        title: InkWell(
          onTap: _openHistorySheet,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: AppSpace.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Assistant', style: theme.textTheme.titleSmall),
                    const SizedBox(width: AppSpace.xs),
                    const Icon(
                      CupertinoIcons.chevron_down,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
                Text(
                  _currentSession?.title ?? 'New Chat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_centralHub != null)
            Tooltip(
              message: 'Connected to Central Hub: ${_centralHub!.name}',
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.xs),
                child: ToneBadge(
                  label: 'Hub',
                  tone: AppTone.primary,
                  icon: CupertinoIcons.cube_box,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(CupertinoIcons.square_pencil),
            tooltip: 'New Chat',
            onPressed: _createNewChat,
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 18),
            onSelected: (value) {
              if (value == 'history') _openHistorySheet();
              if (value == 'clear') _clearChat();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(CupertinoIcons.clock, size: 16),
                    SizedBox(width: AppSpace.sm),
                    Text('Chat history'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                enabled: _messages.isNotEmpty,
                child: const Row(
                  children: [
                    Icon(
                      CupertinoIcons.trash,
                      size: 16,
                      color: AppColors.dangerText,
                    ),
                    SizedBox(width: AppSpace.sm),
                    Text(
                      'Clear chat',
                      style: TextStyle(color: AppColors.dangerText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                    itemCount: _messages.length,
                    itemBuilder: (context, idx) =>
                        _buildMessageBubble(_messages[idx]),
                  ),
          ),

          // Composer: input on top, model / web search / send underneath.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.sm,
                AppSpace.md,
                AppSpace.md,
              ),
              child: ComposerFrame(
                focusNode: _focusNode,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('general-chat-input'),
                      controller: _inputCtrl,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: composerInputDecoration.copyWith(
                        hintText: _webSearchEnabled
                            ? 'Ask with live web search'
                            : 'Message the assistant',
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.xs,
                        0,
                        AppSpace.xs + 2,
                        AppSpace.xs + 2,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: ActionChip(
                                    key: const Key('general-chat-model-picker'),
                                    tooltip: 'Choose model',
                                    avatar: ModelProviderAvatar(
                                      modelId: _llmConfig.model,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _llmConfig.model.split('/').lastOrNull ??
                                          _llmConfig.model,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    side: BorderSide.none,
                                    backgroundColor: Colors.transparent,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _isRunning
                                        ? null
                                        : _showModelPicker,
                                  ),
                                ),
                                const SizedBox(width: AppSpace.xs),
                                FilterChip(
                                  key: const Key(
                                    'general-chat-web-search-chip',
                                  ),
                                  tooltip: _webSearchEnabled
                                      ? 'Web search is on'
                                      : 'Web search is off',
                                  avatar: const Icon(
                                    CupertinoIcons.globe,
                                    size: 14,
                                  ),
                                  label: const Text('Web'),
                                  selected: _webSearchEnabled,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) => _toggleWebSearch(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpace.xs),
                          IconButton.filled(
                            key: const Key('general-chat-send-button'),
                            tooltip: _isRunning ? 'Stop' : 'Send',
                            onPressed: _isRunning
                                ? _stopChat
                                : () => _sendMessage(),
                            style: _isRunning
                                ? IconButton.styleFrom(
                                    backgroundColor: AppColors.surfaceOverlay,
                                    foregroundColor: AppColors.dangerText,
                                  )
                                : null,
                            icon: Icon(
                              _isRunning
                                  ? CupertinoIcons.stop_fill
                                  : CupertinoIcons.arrow_up,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
