import 'package:flutter/material.dart';
import 'package:workfromphone/models/chat_message.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/models/model_info.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/models/tool_event.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/chat_service.dart';
import 'package:workfromphone/services/storage_service.dart';

class ProjectChatScreen extends StatefulWidget {
  final ProjectDirectory project;

  const ProjectChatScreen({
    super.key,
    required this.project,
  });

  @override
  State<ProjectChatScreen> createState() => _ProjectChatScreenState();
}

class _ProjectChatScreenState extends State<ProjectChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final ChatService _chatService = ChatService();

  LLMConfig _llmConfig = const LLMConfig();
  List<ModelInfo> _availableModels = [];
  bool _isRunning = false;
  String? _currentStatus;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _chatService.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final cfg = await StorageService.loadLLMConfig();
    setState(() {
      _llmConfig = cfg;
    });
    _fetchModelsList();
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage([String? textToSend]) {
    final text = textToSend ?? _inputCtrl.text.trim();
    if (text.isEmpty || _isRunning) return;

    if (textToSend == null) {
      _inputCtrl.clear();
    }

    final userMsg = ChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: text,
    );

    final assistantMsg = ChatMessage(
      id: 'asst_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.assistant,
      isStreaming: true,
      statusMessage: 'Starting task...',
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(assistantMsg);
      _isRunning = true;
      _currentStatus = 'Connecting to model...';
    });

    _scrollToBottom();

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
          _scrollToBottom();
        }
      },
      onChunk: (chunk) {
        if (mounted) {
          setState(() {
            assistantMsg.content += chunk;
          });
          _scrollToBottom();
        }
      },
      onToolCallStart: (toolName, args) {
        if (mounted) {
          setState(() {
            assistantMsg.toolEvents.add(
              ToolEvent(
                toolName: toolName,
                args: args,
                isExecuting: true,
              ),
            );
            _currentStatus = 'Executing $toolName...';
          });
          _scrollToBottom();
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
          _scrollToBottom();
        }
      },
      onDone: (steps) {
        if (mounted) {
          setState(() {
            _isRunning = false;
            assistantMsg.isStreaming = false;
            assistantMsg.statusMessage = null;
            _currentStatus = null;
          });
          _scrollToBottom();
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
          });
          _scrollToBottom();
        }
      },
    );
  }

  void _showModelPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final models = _availableModels.isNotEmpty
            ? _availableModels
            : [
                const ModelInfo(id: 'anthropic/claude-3.5-sonnet', name: 'Claude 3.5 Sonnet'),
                const ModelInfo(id: 'openai/gpt-4o', name: 'GPT-4o'),
                const ModelInfo(id: 'openai/gpt-4o-mini', name: 'GPT-4o Mini'),
                const ModelInfo(id: 'deepseek/deepseek-chat', name: 'DeepSeek V3'),
                const ModelInfo(id: 'deepseek/deepseek-r1', name: 'DeepSeek R1'),
                const ModelInfo(id: 'meta-llama/llama-3.3-70b-instruct', name: 'Llama 3.3 70B'),
                const ModelInfo(id: 'google/gemini-2.0-flash-001', name: 'Gemini 2.0 Flash'),
              ];

        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtrl) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.psychology, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Select Active Model',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh Models',
                        onPressed: () {
                          Navigator.pop(ctx);
                          _fetchModelsList();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: models.length,
                    itemBuilder: (context, index) {
                      final m = models[index];
                      final isSelected = m.id == _llmConfig.model;
                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: isSelected ? Theme.of(context).colorScheme.primary : null,
                        ),
                        title: Text(
                          m.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          m.id,
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final updated = _llmConfig.copyWith(model: m.id);
                          await StorageService.saveLLMConfig(updated);
                          if (mounted) {
                            setState(() {
                              _llmConfig = updated;
                            });
                          }
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
    );
  }

  Widget _buildToolEventCard(ToolEvent event) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                event.isError ? Icons.error_outline : Icons.check_circle_outline,
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
          if (event.output != null && event.output!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                event.output!,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.role == MessageRole.user;
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tool call events if any
            if (msg.toolEvents.isNotEmpty) ...[
              for (final te in msg.toolEvents) _buildToolEventCard(te),
              const SizedBox(height: 6),
            ],

            // Content
            if (msg.content.isNotEmpty)
              SelectableText(
                msg.content,
                style: TextStyle(
                  color: isUser
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

            // Live status loader
            if (msg.isStreaming && msg.statusMessage != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    msg.statusMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.project.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              widget.project.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          // Model selector chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: const Icon(Icons.bolt, size: 16),
              label: Text(
                _llmConfig.model.split('/').lastOrNull ?? _llmConfig.model,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              onPressed: _showModelPicker,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Chat',
            onPressed: () {
              setState(() {
                _messages.clear();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Project banner / Empty state
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
                        Icons.smart_toy_outlined,
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
                          avatar: const Icon(Icons.explore_outlined, size: 16),
                          label: const Text('Analyze Project Structure'),
                          onPressed: () => _sendMessage('Analyze this project and explain what it does.'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.play_arrow_outlined, size: 16),
                          label: const Text('Run Tests'),
                          onPressed: () => _sendMessage('Run test suite in this project and report results.'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.commit_outlined, size: 16),
                          label: const Text('Git Status'),
                          onPressed: () => _sendMessage('Check git status and summarize modified files.'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.bug_report_outlined, size: 16),
                          label: const Text('Find Errors & Issues'),
                          onPressed: () => _sendMessage('Check for any syntax or linting errors in the project.'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),

          // Live task progress bar
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
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined, size: 20, color: Colors.red),
                    tooltip: 'Stop Task',
                    onPressed: () {
                      _chatService.cancel();
                      setState(() {
                        _isRunning = false;
                        _currentStatus = null;
                      });
                    },
                  ),
                ],
              ),
            ),

          // Input area
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Give a coding task or ask a question...',
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                    onPressed: _isRunning ? () => _chatService.cancel() : () => _sendMessage(),
                    icon: Icon(_isRunning ? Icons.stop : Icons.arrow_upward_rounded),
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
