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
  String? _currentStatus;

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
    if (mounted) {
      setState(() {
        _llmConfig = cfg;
      });
    }
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
        _currentStatus = null;
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
        _currentStatus = null;
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
    );
  }

  Future<void> _fetchModelsList() async {
    try {
      final list = await ApiService.fetchModels(
        _llmConfig.backendUrl,
        _llmConfig.baseUrl,
        _llmConfig.apiKey,
      );
      if (mounted) {
        setState(() {
          _availableModels = list;
        });
      }
    } catch (_) {}
  }

  void _handleComposerChanged() {
    if (!mounted) return;
    final mention = ChatComposerService.mentionTrigger(_inputCtrl.value);
    if (mention != null && _projectFiles.isEmpty && !_isLoadingProjectFiles) {
      _loadProjectFiles();
    }
    setState(() {});
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
      _currentStatus = 'Connecting to model...';
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
            _currentStatus = status;
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
            _currentStatus = 'Executing $toolName...';
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
            _currentStatus = 'Tool completed';
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
            _currentStatus = null;
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
            assistantMsg.content += '\n\n⚠️ $err';
            assistantMsg.statusMessage = null;
            _currentStatus = null;
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
      _currentStatus = null;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
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
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            const ListTile(
              title: Text(
                'Chat commands',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Type a command in the message box.'),
            ),
            for (final command in ChatComposerService.commands)
              ListTile(
                dense: true,
                leading: const Icon(CupertinoIcons.command, size: 20),
                title: Text(
                  '/${command.name}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
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
      onRefresh: () async {
        await _fetchModelsList();
      },
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

  Widget _buildToolEventCard(ToolEvent event) {
    final theme = Theme.of(context);
    final output = event.output;
    final hasOutput = output != null && output.isNotEmpty;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: event.isExecuting,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: event.isExecuting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                event.isError
                    ? CupertinoIcons.exclamationmark_circle
                    : CupertinoIcons.check_mark_circled,
                size: 18,
                color: event.isError ? Colors.red : Colors.green,
              ),
        title: Text(
          event.summary,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          if (hasOutput)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top bar with line count and copy button
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.command,
                          size: 12,
                          color: Colors.greenAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${output.split('\n').length} lines',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: output));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Tool output copied to clipboard',
                                ),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.doc_on_doc,
                                  size: 11,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Copy',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontFamily: 'monospace',
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Scrollable output container
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(10),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SelectableText(
                            output,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.35,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: isUser
            ? (isDark
                  ? theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    )
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ))
            : (isDark
                  ? theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6)
                  : theme.colorScheme.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUser
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.45)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row: Avatar, Role/Model Label, Actions
          Row(
            children: [
              if (isUser)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.person_fill,
                    size: 13,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                )
              else
                ModelProviderAvatar(modelId: _llmConfig.model, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isUser
                      ? 'You'
                      : (_llmConfig.model.split('/').lastOrNull ??
                            _llmConfig.model),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (!isUser && msg.isStreaming) ...[
                const SizedBox(width: 6),
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              if (msg.content.isNotEmpty && !msg.isStreaming)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: msg.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isUser ? 'Prompt copied' : 'Message copied',
                        ),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.doc_on_doc,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.8,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Interleaved chronological elements (Text thoughts, Tool calls, Follow-up explanations)
          for (final element in msg.elements) ...[
            if (element is TextChatElement && element.text.isNotEmpty) ...[
              MarkdownMessageView(
                data: element.text,
                isUser: isUser,
                isStreaming: msg.isStreaming,
              ),
              const SizedBox(height: 8),
            ] else if (element is ToolChatElement) ...[
              _buildToolEventCard(element.event),
              const SizedBox(height: 8),
            ],
          ],

          // Live status loader
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

  Widget _buildComposerSuggestions(ThemeData theme) {
    final commandSuggestions = ChatComposerService.commandSuggestions(
      _inputCtrl.value,
    );
    final mention = ChatComposerService.mentionTrigger(_inputCtrl.value);
    if (commandSuggestions.isEmpty && mention == null) {
      return const SizedBox.shrink();
    }

    final fileSuggestions = mention == null
        ? const <String>[]
        : _matchingProjectFiles(mention.query);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        key: const Key('chat-composer-suggestions'),
        color: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final command in commandSuggestions)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(CupertinoIcons.command, size: 18),
                  title: Text(
                    '/${command.name}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(command.description),
                  onTap: () => _insertSlashCommand(command),
                ),
              if (mention != null && _isLoadingProjectFiles)
                const ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Loading project files...'),
                )
              else if (mention != null &&
                  _projectFilesError != null &&
                  _projectFiles.isEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(CupertinoIcons.refresh, size: 18),
                  title: const Text('Could not load project files'),
                  subtitle: Text(_projectFilesError!),
                  onTap: _loadProjectFiles,
                )
              else if (mention != null && fileSuggestions.isEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(CupertinoIcons.search, size: 18),
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
                    leading: const Icon(CupertinoIcons.doc, size: 18),
                    title: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    onTap: () => _insertFileMention(mention, path),
                  ),
              if (mention != null && _projectFilesTruncated)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Showing matches from the first 5,000 project files.',
                    style: TextStyle(fontSize: 11),
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
        // Live Task Statistics Bar (TPS, Context Usage, Duration, Tools)
        if (_showStatsBar && (_stats.totalTokens > 0 || _isRunning))
          TaskStatsBar(
            stats: _stats,
            onTap: () {
              showModalBottomSheet(
                context: context,
                builder: (ctx) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Session Statistics',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(
                          CupertinoIcons.bolt,
                          color: Colors.blue,
                        ),
                        title: const Text('Generation Speed'),
                        trailing: Text(
                          _stats.formattedTps,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(
                          CupertinoIcons.gear,
                          color: Colors.purple,
                        ),
                        title: const Text('Context Window Used'),
                        trailing: Text(
                          _stats.formattedContextRatio,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(CupertinoIcons.clock),
                        title: const Text('Total Duration'),
                        trailing: Text(
                          _stats.formattedDuration,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(CupertinoIcons.hammer),
                        title: const Text('Tool Executions'),
                        trailing: Text(
                          '${_stats.toolCallsCount}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        // Project chat history or Empty State
        if (_messages.isEmpty)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      CupertinoIcons.chat_bubble,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'AI Task Harness Ready',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connected to ${widget.project.name} at ${widget.project.path}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Quick Prompts:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ActionChip(
                        avatar: const Icon(CupertinoIcons.compass, size: 16),
                        label: const Text('Analyze Project Structure'),
                        onPressed: () => _sendMessage(
                          'Analyze this project and explain what it does.',
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(CupertinoIcons.play_arrow, size: 16),
                        label: const Text('Run Tests'),
                        onPressed: () => _sendMessage(
                          'Run test suite in this project and report results.',
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(
                          CupertinoIcons.arrow_up_circle,
                          size: 16,
                        ),
                        label: const Text('Git Status'),
                        onPressed: () => _sendMessage(
                          'Check git status and summarize modified files.',
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(
                          CupertinoIcons.exclamationmark_circle,
                          size: 16,
                        ),
                        label: const Text('Find Errors & Issues'),
                        onPressed: () => _sendMessage(
                          'Check for any syntax or linting errors in the project.',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is UserScrollNotification) {
                      if (notification.direction == ScrollDirection.forward) {
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
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
                ),
                if (!_autoScroll)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: Material(
                      elevation: 3,
                      shape: const CircleBorder(),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          setState(() => _autoScroll = true);
                          _scrollToBottom(force: true, animated: true);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            CupertinoIcons.chevron_down,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // Live task progress status bar
        if (_isRunning && _currentStatus != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _currentStatus!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.multiply_circle,
                    size: 20,
                    color: Colors.red,
                  ),
                  tooltip: 'Stop Task',
                  onPressed: _stopCurrentTask,
                ),
              ],
            ),
          ),

        // Chat Input Box
        SafeArea(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildComposerSuggestions(theme),
                Row(
                  children: [
                    ActionChip(
                      key: const Key('chat-model-picker'),
                      avatar: ModelProviderAvatar(
                        modelId: _llmConfig.model,
                        size: 18,
                      ),
                      label: Text(
                        _llmConfig.model.split('/').lastOrNull ??
                            _llmConfig.model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _isRunning ? null : _showModelPicker,
                    ),
                    const Spacer(),
                    Text(
                      '/ commands  •  @ files',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('chat-input'),
                        controller: _inputCtrl,
                        focusNode: _chatFocusNode,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Ask, use /commands, or mention @files...',
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
                      key: const Key('chat-send-button'),
                      onPressed: _isRunning
                          ? _stopCurrentTask
                          : () => _sendMessage(),
                      icon: Icon(
                        _isRunning
                            ? CupertinoIcons.stop
                            : CupertinoIcons.arrow_up,
                      ),
                    ),
                  ],
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
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(CupertinoIcons.chevron_down, size: 18),
                  ],
                ),
                Text(
                  _currentSession?.title ?? 'New Conversation',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.bubble_left, size: 20),
            tooltip: 'All Conversations',
            onPressed: _openConversationHistory,
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.chat_bubble_2, size: 20),
            tooltip: 'New Conversation',
            onPressed: _createNewConversation,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: const [
            Tab(
              icon: Tooltip(
                message: 'Chat',
                child: Icon(CupertinoIcons.chat_bubble, size: 20),
              ),
            ),
            Tab(
              icon: Tooltip(
                message: 'Terminal',
                child: Icon(CupertinoIcons.command, size: 20),
              ),
            ),
            Tab(
              icon: Tooltip(
                message: 'Files',
                child: Icon(CupertinoIcons.folder, size: 20),
              ),
            ),
            Tab(
              icon: Tooltip(
                message: 'Git',
                child: Icon(CupertinoIcons.doc_plaintext, size: 20),
              ),
            ),
            Tab(
              icon: Tooltip(
                message: 'System',
                child: Icon(CupertinoIcons.heart, size: 20),
              ),
            ),
            Tab(
              icon: Tooltip(
                message: 'Preview',
                child: Icon(CupertinoIcons.globe, size: 20),
              ),
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
