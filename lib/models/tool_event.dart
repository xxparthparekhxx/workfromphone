class ToolEvent {
  final String toolName;
  final Map<String, dynamic> args;
  String? output;
  bool isExecuting;
  bool isError;

  ToolEvent({
    required this.toolName,
    required this.args,
    this.output,
    this.isExecuting = true,
    this.isError = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'tool_name': toolName,
      'args': args,
      'output': output,
      'is_executing': isExecuting,
      'is_error': isError,
    };
  }

  factory ToolEvent.fromJson(Map<String, dynamic> json) {
    return ToolEvent(
      toolName: json['tool_name'] as String? ?? 'tool',
      args: (json['args'] as Map<String, dynamic>?) ?? {},
      output: json['output'] as String?,
      isExecuting: json['is_executing'] as bool? ?? false,
      isError: json['is_error'] as bool? ?? false,
    );
  }

  String get summary {
    switch (toolName) {
      case 'run_terminal_command':
        return '\$ ${args['command'] ?? ''}';
      case 'read_file':
        return 'Read ${args['relative_path'] ?? ''}';
      case 'write_file':
        return 'Write ${args['relative_path'] ?? ''}';
      case 'edit_file':
        return 'Edit ${args['relative_path'] ?? ''}';
      case 'list_directory':
        final p = args['relative_path'];
        return 'List ${p == null || p.toString().isEmpty ? 'root' : p}';
      case 'search_project':
        return 'Search "${args['query'] ?? ''}"';
      default:
        return toolName;
    }
  }
}
