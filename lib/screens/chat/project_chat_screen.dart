import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:workfromphone/models/chat_message.dart';
import 'package:workfromphone/models/conversation_session.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/models/model_info.dart';
import 'package:workfromphone/models/preview_entry.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/models/task_stats.dart';
import 'package:workfromphone/models/tool_event.dart';
import 'package:workfromphone/screens/chat/conversation_history_sheet.dart';
import 'package:workfromphone/screens/files/project_files_tab.dart';
import 'package:workfromphone/screens/git/project_git_tab.dart';
import 'package:workfromphone/screens/preview/project_preview_tab.dart';
import 'package:workfromphone/screens/system/project_system_tab.dart';
import 'package:workfromphone/screens/terminal/project_terminal_tab.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/chat_composer_service.dart';
import 'package:workfromphone/services/chat_service.dart';
import 'package:workfromphone/services/preview_session.dart';
import 'package:workfromphone/services/storage_service.dart';
import 'package:workfromphone/theme/app_theme.dart';
import 'package:workfromphone/widgets/app_ui.dart';
import 'package:workfromphone/widgets/markdown_message_view.dart';
import 'package:workfromphone/widgets/model_picker_sheet.dart';
import 'package:workfromphone/widgets/task_stats_bar.dart';
import 'package:workfromphone/widgets/model_provider_avatar.dart';

class ProjectChatScreen extends StatefulWidget {
  final ProjectDirectory project;

  const ProjectChatScreen({super.key, required this.project});

  @override
  State<ProjectChatScreen> createState() => _ProjectChatScreenState();
}

class _ProjectChatScreenState extends State<ProjectChatScreen>
    with SingleTickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  final ChatService _chatService = ChatService();
  late TabController _tabController;
  int _activeTabIndex = 0;
  bool _autoScroll = true;

  LLMConfig _llmConfig = const LLMConfig();
  List<ModelInfo> _availableModels = [];
  List<String> _projectFiles = [];
  bool _isLoadingProjectFiles = false;
  bool _projectFilesTruncated = false;
  String? _projectFilesError;
  bool _isRunning = false;

  // Multi-conversation state
  ConversationSession? _currentSession;

  // Real-time statistics state
  TaskStats _stats = const TaskStats();
  DateTime? _taskStartTime;
  int _streamedChars = 0;
  int _toolCallsCount = 0;
  final bool _showStatsBar = true;

  // Preview state
  List<PreviewEntry> _previewEntries = [];
  PreviewSession? _previewSession;
  PreviewSessionState _previewState = PreviewSessionState.disconnected;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_handleTabChange);
    _inputCtrl.addListener(_handleComposerChanged);
    _loadConfig();
  }

  void _handleTabChange() {
    if (_activeTabIndex == _tabController.index) return;
    final previous = _activeTabIndex;
    setState(() => _activeTabIndex = _tabController.index);
    final session = _previewSession;
    if (session == null) return;
    if (_activeTabIndex == 5) {
      unawaited(session.start());
    } else if (previous == 5) {
      unawaited(session.stop());
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _chatService.cancel();
    _inputCtrl.removeListener(_handleComposerChanged);
    _inputCtrl.dispose();
    _chatFocusNode.dispose();
    _scrollCtrl.dispose();
    _previewSession?.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final cfg = await StorageService.loadLLMConfig();
    ApiService.configureAccessToken(
      cfg.backendAccessToken,
      backendUrl: cfg.backendUrl,
    );
    // The screen may have been popped while the config was loading; creating
    // the preview session here would leak it (dispose already ran).
    if (!mounted) return;
    setState(() {
      _llmConfig = cfg;
    });
    _ensurePreviewSession(cfg);
    await _initConversationSession();
    _fetchModelsList();
  }

  void _ensurePreviewSession(LLMConfig cfg) {
    if (cfg.backendUrl.trim().isEmpty) {
      _previewSession?.dispose();
      _previewSession = null;
      return;
    }
    _previewSession?.dispose();
    final session = PreviewSession(
      backendUrl: cfg.backendUrl,
      accessToken: cfg.backendAccessToken,
      projectPath: widget.project.path,
      onEntries: (entries) {
        if (!mounted) return;
        setState(() => _previewEntries = entries);
      },
      onStateChange: (state) {
        if (!mounted) return;
        setState(() => _previewState = state);
      },
      onError: (_) {},
    );
    _previewSession = session;
    if (_activeTabIndex == 5) {
      unawaited(session.start());
    }
  }

  Future<void> _initConversationSession() async {
    final activeId = await StorageService.loadActiveConversationId(
      widget.project.path,
    );
    final list = await StorageService.loadConversations(widget.project.path);
    ConversationSession? session;
    if (activeId != null) {
      session = list.where((c) => c.id == activeId).firstOrNull;
    }
    session ??= list.firstOrNull;

    if (session == null) {
      session = ConversationSession(
        id: 'conv_${DateTime.now().millisecondsSinceEpoch}',
        projectPath: widget.project.path,
        title: 'New Conversation',
        model: _llmConfig.model,
      );
      await StorageService.saveConversation(widget.project.path, session);
      await StorageService.saveActiveConversationId(
        widget.project.path,
        session.id,
      );
    }

    if (mounted) {
      setState(() {
        _currentSession = session;
        _llmConfig = _llmConfig.copyWith(model: session!.model);
        _messages.clear();
        _messages.addAll(session.messages);
        _stats = session.stats;
      });
      _scrollToBottom(force: true, animated: false);
    }
  }

  Future<void> _saveCurrentSession() async {
    if (_currentSession == null) return;
    final updated = _currentSession!.copyWith(
      messages: List.from(_messages),
      stats: _stats,
      updatedAt: DateTime.now(),
      model: _llmConfig.model,
    );
    _currentSession = updated;
    await StorageService.saveConversation(widget.project.path, updated);
    await StorageService.saveActiveConversationId(
      widget.project.path,
      updated.id,
    );
  }

  Future<void> _createNewConversation() async {
    if (_isRunning) {
      _chatService.cancel();
    }
    await _saveCurrentSession();
    final newSession = ConversationSession(
      id: 'conv_${DateTime.now().millisecondsSinceEpoch}',
      projectPath: widget.project.path,
      title: 'New Conversation',
      model: _llmConfig.model,
    );
    await StorageService.saveConversation(widget.project.path, newSession);
    await StorageService.saveActiveConversationId(
      widget.project.path,
      newSession.id,
    );
    if (mounted) {
      setState(() {
        _currentSession = newSession;
        _messages.clear();
        _stats = const TaskStats();
        _isRunning = false;
      });
    }
  }

  Future<void> _switchConversation(ConversationSession session) async {
    if (_isRunning) {
      _chatService.cancel();
    }
    await _saveCurrentSession();
    await StorageService.saveActiveConversationId(
      widget.project.path,
      session.id,
    );
    if (mounted) {
      setState(() {
        _currentSession = session;
        _llmConfig = _llmConfig.copyWith(model: session.model);
        _messages.clear();
        _messages.addAll(session.messages);
        _stats = session.stats;
        _isRunning = false;
      });
      _scrollToBottom(force: true, animated: false);
    }
  }

  void _openConversationHistory() {
    ConversationHistorySheet.show(
      context,
      project: widget.project,
      activeConversationId: _currentSession?.id,
      onSelectConversation: _switchConversation,
      onNewConversation: _createNewConversation,
      onActiveConversationDeleted: _handleActiveConversationDeleted,
    );
  }

  /// The active conversation was deleted from the history sheet. Reset to a
  /// brand-new session so a later `_saveCurrentSession()` can never
  /// re-save (and resurrect) the deleted id.
  Future<void> _handleActiveConversationDeleted() async {
    if (_isRunning) {
      _chatService.cancel();
    }
    final fresh = ConversationSession(
      id: 'conv_${DateTime.now().millisecondsSinceEpoch}',
      projectPath: widget.project.path,
      title: 'New Conversation',
      model: _llmConfig.model,
    );
    await StorageService.saveConversation(widget.project.path, fresh);
    await StorageService.saveActiveConversationId(
      widget.project.path,
      fresh.id,
    );
    if (mounted) {
      setState(() {
        _currentSession = fresh;
        _messages.clear();
        _stats = const TaskStats();
        _isRunning = false;
      });
      _scrollToBottom(force: true, animated: false);
    }
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
        title: const Text('Clear Conversation'),
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
          'Conversation cleared',
          duration: const Duration(seconds: 1),
        );
      }
    }
  }

  Future<List<ModelInfo>> _fetchModelsList() async {
    try {
      final list = await ApiService.fetchProviderModels(
        backendUrl: _llmConfig.backendUrl,
        baseUrl: _llmConfig.baseUrl,
        apiKey: _llmConfig.apiKey,
      );
      if (mounted) {
        setState(() {
          _availableModels = list;
        });
      }
      return list;
    } catch (_) {
      return _availableModels;
    }
  }

  /// Keystrokes only lazily kick off the project-file fetch; the suggestions
  /// panel rebuilds itself via a ValueListenableBuilder on the controller,
  /// so no root setState (and full screen rebuild) happens per keystroke.
  void _handleComposerChanged() {
    final mention = ChatComposerService.mentionTrigger(_inputCtrl.value);
    if (mention != null && _projectFiles.isEmpty && !_isLoadingProjectFiles) {
      _loadProjectFiles();
    }
  }

  Future<void> _loadProjectFiles() async {
    if (_isLoadingProjectFiles) return;
    setState(() {
      _isLoadingProjectFiles = true;
      _projectFilesError = null;
    });
    try {
      final result = await ApiService.listProjectFiles(
        _llmConfig.backendUrl,
        projectPath: widget.project.path,
      );
      if (!mounted) return;
      setState(() {
        _projectFiles = result.files;
        _projectFilesTruncated = result.truncated;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _projectFilesError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingProjectFiles = false);
      }
    }
  }

  void _scrollToBottom({bool force = false, bool animated = false}) {
    if (!_autoScroll && !force) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (!_autoScroll && !force) return;
      final pos = _scrollCtrl.position;
      if (pos.maxScrollExtent <= 0) return;

      if (animated) {
        _scrollCtrl.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  int _findModelContextLimit(String modelId) {
    for (final m in _availableModels) {
      if (m.id == modelId && m.contextLength != null) {
        return m.contextLength!;
      }
    }
    final lower = modelId.toLowerCase();
    if (lower.contains('gemini-2.0') || lower.contains('gemini-1.5')) {
      return 1048576;
    }
    if (lower.contains('claude-3-7') ||
        lower.contains('claude-3.7') ||
        lower.contains('claude-3-5') ||
        lower.contains('claude-3.5')) {
      return 200000;
    }
    if (lower.contains('gpt-4o') || lower.contains('o3-mini')) return 128000;
    if (lower.contains('llama-3.3') || lower.contains('llama-3.1')) {
      return 131072;
    }
    if (lower.contains('deepseek')) return 64000;
    return 200000;
  }

  Future<void> _sendMessage([String? textToSend]) async {
    var text = (textToSend ?? _inputCtrl.text).trim();
    if (text.isEmpty) return;

    if (textToSend == null) {
      final parsed = ChatComposerService.parseSlashCommand(text);
      if (parsed != null) {
        final command = parsed.command;
        if (command == null) {
          _showComposerMessage(
            parsed.name.isEmpty
                ? 'Type a command after /. Use /help to see all commands.'
                : 'Unknown command /${parsed.name}. Use /help to see all commands.',
          );
          return;
        }
        switch (command.action) {
          case ChatCommandAction.showHelp:
            _inputCtrl.clear();
            _showCommandsSheet();
            return;
          case ChatCommandAction.newConversation:
            _inputCtrl.clear();
            await _createNewConversation();
            return;
          case ChatCommandAction.chooseModel:
            _inputCtrl.clear();
            _showModelPicker();
            return;
          case ChatCommandAction.stopTask:
            _inputCtrl.clear();
            _stopCurrentTask();
            return;
          case ChatCommandAction.openPreview:
            _inputCtrl.clear();
            _handleManualPreviewRegister(parsed.arguments);
            return;
          case ChatCommandAction.sendPrompt:
            text = command.expand(parsed.arguments);
        }
      }
    }

    if (_isRunning) return;

    if (textToSend == null) {
      _inputCtrl.clear();
    }

    final apiContent = ChatComposerService.buildApiContent(text);
    final userMsg = ChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: text,
      apiContent: apiContent == text ? null : apiContent,
    );

    final assistantMsg = ChatMessage(
      id: 'asst_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.assistant,
      isStreaming: true,
      statusMessage: 'Starting task...',
    );

    _taskStartTime = DateTime.now();
    _streamedChars = 0;
    _toolCallsCount = 0;

    final contextLimit = _findModelContextLimit(_llmConfig.model);
    final totalCharLen =
        _messages.fold<int>(0, (sum, m) => sum + m.content.length) +
        apiContent.length;
    final estimatedPromptTokens =
        (totalCharLen / 3.8).round() + 1200; // system prompt estimate
    final basePromptTokens = _stats.promptTokens;
    final baseCompletionTokens = _stats.completionTokens;
    final baseTotalTokens = _stats.totalTokens;
    final baseReasoningTokens = _stats.reasoningTokens;
    final baseCachedTokens = _stats.cachedTokens;
    final baseCost = _stats.cost;
    final baseToolCalls = _stats.toolCallsCount;
    final baseSteps = _stats.stepsCount;
    var receivedExactUsage = false;
    var exactTaskCompletionTokens = 0;

    if (_currentSession != null &&
        (_currentSession!.title == 'New Conversation' ||
            _currentSession!.title.isEmpty)) {
      String cleanTitle = text.replaceAll('\n', ' ').trim();
      if (cleanTitle.length > 32) {
        cleanTitle = '${cleanTitle.substring(0, 32)}...';
      }
      _currentSession!.title = cleanTitle;
    }

    setState(() {
      _autoScroll = true;
      _messages.add(userMsg);
      _messages.add(assistantMsg);
      _isRunning = true;
      _stats = _stats.copyWith(
        promptTokens: basePromptTokens + estimatedPromptTokens,
        completionTokens: baseCompletionTokens,
        totalTokens: baseTotalTokens + estimatedPromptTokens,
        contextTokens: estimatedPromptTokens,
        contextLimit: contextLimit,
        tokensPerSecond: 0,
        durationMs: 0,
        toolCallsCount: baseToolCalls,
        stepsCount: baseSteps,
        isStreaming: true,
        usageIsEstimated: true,
      );
    });

    _saveCurrentSession();
    _scrollToBottom(force: true, animated: true);

    _chatService.runTask(
      backendUrl: _llmConfig.backendUrl,
      projectPath: widget.project.path,
      messages: _messages.sublist(0, _messages.length - 1),
      llmConfig: _llmConfig,
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
          _streamedChars += chunk.length;
          final completionTokens = (_streamedChars / 3.8).round();
          final elapsedMs = _taskStartTime != null
              ? DateTime.now().difference(_taskStartTime!).inMilliseconds
              : 0;
          final tps = elapsedMs > 250
              ? (completionTokens / (elapsedMs / 1000.0))
              : 0.0;

          setState(() {
            assistantMsg.appendChunk(chunk);
            _stats = _stats.copyWith(
              promptTokens: basePromptTokens + estimatedPromptTokens,
              completionTokens: baseCompletionTokens + completionTokens,
              totalTokens:
                  baseTotalTokens + estimatedPromptTokens + completionTokens,
              contextTokens: estimatedPromptTokens + completionTokens,
              tokensPerSecond: tps,
              durationMs: elapsedMs,
              isStreaming: true,
              usageIsEstimated: true,
            );
          });
          _scrollToBottom(force: false, animated: false);
        }
      },
      onToolCallStart: (toolName, args) {
        if (mounted) {
          _toolCallsCount++;
          setState(() {
            assistantMsg.addToolEvent(
              ToolEvent(toolName: toolName, args: args, isExecuting: true),
            );
            _stats = _stats.copyWith(
              toolCallsCount: baseToolCalls + _toolCallsCount,
            );
          });
          _scrollToBottom(force: false, animated: false);
        }
      },
      onToolCallResult: (toolName, output) {
        if (mounted) {
          setState(() {
            final lastTool = assistantMsg.toolEvents.lastWhere(
              (t) => t.toolName == toolName && t.isExecuting,
              orElse: () => assistantMsg.toolEvents.last,
            );
            lastTool.output = output;
            lastTool.isExecuting = false;
            lastTool.isError = output.startsWith('Error:');
          });
          _scrollToBottom(force: false, animated: false);
        }
      },
      onUsage: (usage) {
        if (mounted) {
          receivedExactUsage = usage.exact;
          exactTaskCompletionTokens = usage.completionTokens;
          final elapsedMs = _taskStartTime != null
              ? DateTime.now().difference(_taskStartTime!).inMilliseconds
              : 0;
          final tps = elapsedMs > 250
              ? usage.completionTokens / (elapsedMs / 1000.0)
              : 0.0;
          setState(() {
            _stats = _stats.copyWith(
              promptTokens: basePromptTokens + usage.promptTokens,
              completionTokens: baseCompletionTokens + usage.completionTokens,
              totalTokens: baseTotalTokens + usage.totalTokens,
              contextTokens: usage.contextTokens,
              reasoningTokens: baseReasoningTokens + usage.reasoningTokens,
              cachedTokens: baseCachedTokens + usage.cachedTokens,
              cost: baseCost + (usage.cost ?? 0),
              tokensPerSecond: tps,
              durationMs: elapsedMs,
              usageIsEstimated: !usage.exact,
            );
          });
        }
      },
      onDone: (steps) {
        if (mounted) {
          final elapsedMs = _taskStartTime != null
              ? DateTime.now().difference(_taskStartTime!).inMilliseconds
              : 0;
          final completionTokens = (_streamedChars / 3.8).round();
          final completionTokensForSpeed = receivedExactUsage
              ? exactTaskCompletionTokens
              : completionTokens;
          final tps = elapsedMs > 250
              ? completionTokensForSpeed / (elapsedMs / 1000.0)
              : 0.0;

          setState(() {
            _isRunning = false;
            assistantMsg.isStreaming = false;
            assistantMsg.statusMessage = null;
            _stats = _stats.copyWith(
              promptTokens: receivedExactUsage
                  ? _stats.promptTokens
                  : basePromptTokens + estimatedPromptTokens,
              completionTokens: receivedExactUsage
                  ? _stats.completionTokens
                  : baseCompletionTokens + completionTokens,
              totalTokens: receivedExactUsage
                  ? _stats.totalTokens
                  : baseTotalTokens + estimatedPromptTokens + completionTokens,
              contextTokens: receivedExactUsage
                  ? _stats.contextTokens
                  : estimatedPromptTokens + completionTokens,
              tokensPerSecond: tps,
              durationMs: elapsedMs,
              stepsCount: baseSteps + (steps ?? 1),
              isStreaming: false,
              usageIsEstimated: !receivedExactUsage,
            );
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
            // Append a NEW trailing text element; the `content` setter would
            // overwrite the FIRST text element, mangling messages that have
            // multiple segments (text → tool card → text).
            assistantMsg.elements.add(TextChatElement('\n\n⚠️ $err'));
            assistantMsg.statusMessage = null;
            _stats = _stats.copyWith(isStreaming: false);
          });
          _saveCurrentSession();
          _scrollToBottom(force: true, animated: true);
        }
      },
    );
  }

  void _stopCurrentTask() {
    if (!_isRunning) {
      _showComposerMessage('There is no running task to stop.');
      return;
    }
    _chatService.cancel();
    setState(() {
      _isRunning = false;
      _stats = _stats.copyWith(isStreaming: false);
      for (final message in _messages.reversed) {
        if (message.role == MessageRole.assistant && message.isStreaming) {
          message.isStreaming = false;
          message.statusMessage = null;
          break;
        }
      }
    });
    _saveCurrentSession();
  }

  void _showComposerMessage(String message) {
    showAppSnackBar(context, message);
  }

  Future<void> _handleManualPreviewRegister(String arguments) async {
    final parts = arguments.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      _showComposerMessage(
        'Usage: /preview <port> [label]  '
        '(e.g. /preview 8080 vite)',
      );
      return;
    }
    final port = int.tryParse(parts.first);
    if (port == null || port < 1 || port > 65535) {
      _showComposerMessage('Port must be a number between 1 and 65535.');
      return;
    }
    final label = parts.length > 1
        ? parts.sublist(1).join(' ').trim()
        : 'Port $port';
    final backendUrl = _llmConfig.backendUrl.trim();
    if (backendUrl.isEmpty) {
      _showComposerMessage('Configure a backend URL first.');
      return;
    }
    try {
      final entry = await ApiService.registerPreview(
        backendUrl,
        projectPath: widget.project.path,
        port: port,
        label: label,
      );
      _showComposerMessage(
        'Registered "${entry.label}" on port ${entry.port}.',
      );
      _switchToPreviewTab();
    } catch (error) {
      _showComposerMessage('Failed to register preview: $error');
    }
  }

  void _switchToPreviewTab() {
    if (!_tabController.indexIsChanging) {
      _tabController.animateTo(5);
    }
  }

  void _showCommandsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          children: [
            const SheetHeader(
              title: 'Chat commands',
              subtitle: 'Type a command in the message box.',
            ),
            const Divider(),
            for (final command in ChatComposerService.commands)
              ListTile(
                dense: true,
                leading: const Icon(CupertinoIcons.command, size: 18),
                title: Text(
                  '/${command.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                subtitle: Text(command.description),
                onTap: () {
                  Navigator.of(context).pop();
                  _insertSlashCommand(command);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _insertSlashCommand(ChatSlashCommand command) {
    final text = '/${command.name} ';
    _inputCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _chatFocusNode.requestFocus();
  }

  List<String> _matchingProjectFiles(String query) {
    final normalized = query.toLowerCase();
    final matches = _projectFiles.where((path) {
      return normalized.isEmpty || path.toLowerCase().contains(normalized);
    }).toList();
    matches.sort((a, b) {
      final aLower = a.toLowerCase();
      final bLower = b.toLowerCase();
      final aName = aLower.split('/').last;
      final bName = bLower.split('/').last;
      final aScore = aLower.startsWith(normalized)
          ? 0
          : aName.startsWith(normalized)
          ? 1
          : 2;
      final bScore = bLower.startsWith(normalized)
          ? 0
          : bName.startsWith(normalized)
          ? 1
          : 2;
      return aScore == bScore ? aLower.compareTo(bLower) : aScore - bScore;
    });
    return matches.take(8).toList();
  }

  void _insertFileMention(FileMentionTrigger trigger, String path) {
    final current = _inputCtrl.value;
    final replacement = '@$path ';
    final updated = current.text.replaceRange(
      trigger.start,
      trigger.end,
      replacement,
    );
    final cursor = trigger.start + replacement.length;
    _inputCtrl.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _chatFocusNode.requestFocus();
  }

  void _showModelPicker() {
    ModelPickerSheet.show(
      context: context,
      selectedModelId: _llmConfig.model,
      availableModels: _availableModels,
      onRefresh: _fetchModelsList,
      onModelSelected: (selectedModel) async {
        final updated = _llmConfig.copyWith(model: selectedModel.id);
        await StorageService.saveLLMConfig(updated);
        if (mounted) {
          setState(() {
            _llmConfig = updated;
            _stats = _stats.copyWith(
              contextLimit:
                  selectedModel.contextLength ??
                  _findModelContextLimit(selectedModel.id),
            );
            _currentSession?.model = selectedModel.id;
          });
          await _saveCurrentSession();
        }
      },
    );
  }

  String get _modelLabel =>
      _llmConfig.model.split('/').lastOrNull ?? _llmConfig.model;

  Widget _buildToolEventCard(ToolEvent event) {
    final output = event.output;
    final hasOutput = output != null && output.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        initiallyExpanded: event.isExecuting,
        dense: true,
        visualDensity: VisualDensity.compact,
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        leading: event.isExecuting
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                event.isError
                    ? CupertinoIcons.exclamationmark_circle
                    : CupertinoIcons.check_mark_circled,
                size: 16,
                color: event.isError ? AppColors.dangerText : AppColors.success,
              ),
        title: Text(
          event.summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        children: [
          if (hasOutput)
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpace.md,
                      right: AppSpace.xs,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${output.split('\n').length} lines',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const Spacer(),
                        CompactIconButton(
                          icon: CupertinoIcons.doc_on_doc,
                          tooltip: 'Copy output',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: output));
                            showAppSnackBar(
                              context,
                              'Tool output copied to clipboard',
                              duration: const Duration(seconds: 2),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.md,
                          0,
                          AppSpace.md,
                          AppSpace.md,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SelectableText(
                            output,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
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
      label: isUser ? 'You' : _modelLabel,
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
            tooltip: isUser ? 'Copy prompt' : 'Copy message',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: msg.content));
              showAppSnackBar(
                context,
                isUser ? 'Prompt copied' : 'Message copied',
                duration: const Duration(seconds: 2),
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
        // Interleaved chronological elements (text, tool calls, follow-ups).
        for (final element in msg.elements) ...[
          if (element is TextChatElement && element.text.isNotEmpty) ...[
            MarkdownMessageView(
              data: element.text,
              isUser: isUser,
              isStreaming: msg.isStreaming,
            ),
            const SizedBox(height: AppSpace.sm),
          ] else if (element is ToolChatElement) ...[
            _buildToolEventCard(element.event),
            const SizedBox(height: AppSpace.xs),
          ],
        ],

        // Live status loader
        if (msg.isStreaming && msg.statusMessage != null) ...[
          const SizedBox(height: AppSpace.xs),
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

  Widget _buildComposerSuggestions(ThemeData theme) {
    // Rebuilds only this subtree per keystroke, via the controller.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _inputCtrl,
      builder: (context, value, _) {
        return _buildComposerSuggestionsFor(value, theme);
      },
    );
  }

  Widget _buildComposerSuggestionsFor(TextEditingValue value, ThemeData theme) {
    final commandSuggestions = ChatComposerService.commandSuggestions(value);
    final mention = ChatComposerService.mentionTrigger(value);
    if (commandSuggestions.isEmpty && mention == null) {
      return const SizedBox.shrink();
    }

    final fileSuggestions = mention == null
        ? const <String>[]
        : _matchingProjectFiles(mention.query);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        key: const Key('chat-composer-suggestions'),
        color: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            children: [
              for (final command in commandSuggestions)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(CupertinoIcons.command, size: 16),
                  title: Text(
                    '/${command.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  subtitle: Text(command.description),
                  onTap: () => _insertSlashCommand(command),
                ),
              if (mention != null && _isLoadingProjectFiles)
                const ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Loading project files...'),
                )
              else if (mention != null &&
                  _projectFilesError != null &&
                  _projectFiles.isEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(CupertinoIcons.refresh, size: 16),
                  title: const Text('Could not load project files'),
                  subtitle: Text(_projectFilesError!),
                  onTap: _loadProjectFiles,
                )
              else if (mention != null && fileSuggestions.isEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(CupertinoIcons.search, size: 16),
                  title: Text(
                    mention.query.isEmpty
                        ? 'No project files available'
                        : 'No files match "${mention.query}"',
                  ),
                )
              else if (mention != null)
                for (final path in fileSuggestions)
                  ListTile(
                    key: ValueKey('file-mention-$path'),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(CupertinoIcons.doc, size: 16),
                    title: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _insertFileMention(mention, path),
                  ),
              if (mention != null && _projectFilesTruncated)
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.xs,
                    AppSpace.lg,
                    AppSpace.sm,
                  ),
                  child: Text(
                    'Showing matches from the first 5,000 project files.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18),
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  void _showStatsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Session statistics',
              subtitle: _stats.usageIsEstimated
                  ? 'Token counts are estimated'
                  : 'Token counts reported by the provider',
            ),
            const Divider(),
            _buildStatRow(
              CupertinoIcons.bolt,
              'Generation speed',
              _stats.formattedTps,
            ),
            _buildStatRow(
              CupertinoIcons.chart_bar,
              'Context window used',
              _stats.formattedContextRatio,
            ),
            _buildStatRow(
              CupertinoIcons.clock,
              'Total duration',
              _stats.formattedDuration,
            ),
            _buildStatRow(
              CupertinoIcons.hammer,
              'Tool executions',
              '${_stats.toolCallsCount}',
            ),
            const SizedBox(height: AppSpace.md),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChat() {
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
              EmptyState(
                icon: CupertinoIcons.chat_bubble_2,
                tone: AppTone.primary,
                title: 'Start a task',
                message:
                    'The agent can read and edit files, run commands and '
                    'check git in ${widget.project.name}.',
              ),
              const SizedBox(height: AppSpace.xl),
              const SectionLabel('Try'),
              PromptSuggestion(
                icon: CupertinoIcons.compass,
                label: 'Explain this project',
                onTap: () => _sendMessage(
                  'Analyze this project and explain what it does.',
                ),
              ),
              PromptSuggestion(
                icon: CupertinoIcons.play_arrow,
                label: 'Run the test suite',
                onTap: () => _sendMessage(
                  'Run test suite in this project and report results.',
                ),
              ),
              PromptSuggestion(
                icon: CupertinoIcons.arrow_branch,
                label: 'Summarize git changes',
                onTap: () => _sendMessage(
                  'Check git status and summarize modified files.',
                ),
              ),
              PromptSuggestion(
                icon: CupertinoIcons.exclamationmark_triangle,
                label: 'Find errors and lint issues',
                onTap: () => _sendMessage(
                  'Check for any syntax or linting errors in the project.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatTab(ThemeData theme) {
    return Column(
      children: [
        // Live task statistics (speed, context usage, duration, tools).
        if (_showStatsBar && (_stats.totalTokens > 0 || _isRunning))
          TaskStatsBar(stats: _stats, onTap: _showStatsSheet),

        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyChat()
              : Stack(
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is UserScrollNotification) {
                          if (notification.direction ==
                              ScrollDirection.forward) {
                            if (_autoScroll) {
                              setState(() => _autoScroll = false);
                            }
                          }
                        }
                        if (_scrollCtrl.hasClients) {
                          final pos = _scrollCtrl.position;
                          if (pos.pixels >= pos.maxScrollExtent - 40) {
                            if (!_autoScroll) {
                              setState(() => _autoScroll = true);
                            }
                          }
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpace.sm,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessageBubble(_messages[index]);
                        },
                      ),
                    ),
                    if (!_autoScroll)
                      Positioned(
                        right: AppSpace.lg,
                        bottom: AppSpace.md,
                        child: Material(
                          color: AppColors.surfaceOverlay,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            side: const BorderSide(
                              color: AppColors.borderStrong,
                            ),
                          ),
                          child: IconButton(
                            tooltip: 'Scroll to latest',
                            icon: const Icon(
                              CupertinoIcons.chevron_down,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            onPressed: () {
                              setState(() => _autoScroll = true);
                              _scrollToBottom(force: true, animated: true);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
        ),

        // Composer
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              AppSpace.sm,
              AppSpace.md,
              AppSpace.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildComposerSuggestions(theme),
                ComposerFrame(
                  focusNode: _chatFocusNode,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const Key('chat-input'),
                        controller: _inputCtrl,
                        focusNode: _chatFocusNode,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: composerInputDecoration.copyWith(
                          hintText: 'Ask, type / for commands, @ for files',
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
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: ActionChip(
                                  key: const Key('chat-model-picker'),
                                  tooltip: 'Choose model',
                                  avatar: ModelProviderAvatar(
                                    modelId: _llmConfig.model,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _modelLabel,
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
                            ),
                            IconButton.filled(
                              key: const Key('chat-send-button'),
                              tooltip: _isRunning ? 'Stop task' : 'Send',
                              onPressed: _isRunning
                                  ? _stopCurrentTask
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
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _openConversationHistory,
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
                    Flexible(
                      child: Text(
                        widget.project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    const Icon(
                      CupertinoIcons.chevron_down,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
                Text(
                  _currentSession?.title ?? 'New Conversation',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.square_pencil),
            tooltip: 'New Conversation',
            onPressed: _createNewConversation,
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 18),
            onSelected: (value) {
              if (value == 'history') _openConversationHistory();
              if (value == 'clear') _clearChat();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(CupertinoIcons.clock, size: 16),
                    SizedBox(width: AppSpace.sm),
                    Text('All conversations'),
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
                      'Clear conversation',
                      style: TextStyle(color: AppColors.dangerText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpace.xs),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          tabs: const [
            Tab(
              height: 52,
              iconMargin: EdgeInsets.only(bottom: 3),
              icon: Icon(CupertinoIcons.chat_bubble, size: 18),
              text: 'Chat',
            ),
            Tab(
              height: 52,
              iconMargin: EdgeInsets.only(bottom: 3),
              icon: Icon(CupertinoIcons.command, size: 18),
              text: 'Terminal',
            ),
            Tab(
              height: 52,
              iconMargin: EdgeInsets.only(bottom: 3),
              icon: Icon(CupertinoIcons.folder, size: 18),
              text: 'Files',
            ),
            Tab(
              height: 52,
              iconMargin: EdgeInsets.only(bottom: 3),
              icon: Icon(CupertinoIcons.arrow_branch, size: 18),
              text: 'Git',
            ),
            Tab(
              height: 52,
              iconMargin: EdgeInsets.only(bottom: 3),
              icon: Icon(CupertinoIcons.gauge, size: 18),
              text: 'System',
            ),
            Tab(
              height: 52,
              iconMargin: EdgeInsets.only(bottom: 3),
              icon: Icon(CupertinoIcons.globe, size: 18),
              text: 'Preview',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatTab(theme),
          ProjectTerminalTab(
            project: widget.project,
            backendUrl: _llmConfig.backendUrl,
            accessToken: _llmConfig.backendAccessToken,
          ),
          ProjectFilesTab(
            project: widget.project,
            backendUrl: _llmConfig.backendUrl,
          ),
          ProjectGitTab(
            project: widget.project,
            backendUrl: _llmConfig.backendUrl,
          ),
          ProjectSystemTab(
            backendUrl: _llmConfig.backendUrl,
            accessToken: _llmConfig.backendAccessToken,
            stats: _stats,
            active: _activeTabIndex == 4,
          ),
          ProjectPreviewTab(
            backendUrl: _llmConfig.backendUrl,
            accessToken: _llmConfig.backendAccessToken,
            entries: _previewEntries,
            connectionState: _previewState,
            active: _activeTabIndex == 5,
          ),
        ],
      ),
    );
  }
}
