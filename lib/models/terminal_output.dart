class TerminalHistoryItem {
  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;
  final DateTime timestamp;
  final bool isRunning;

  TerminalHistoryItem({
    required this.command,
    this.exitCode = 0,
    this.stdout = '',
    this.stderr = '',
    this.durationMs = 0,
    DateTime? timestamp,
    this.isRunning = false,
  }) : timestamp = timestamp ?? DateTime.now();

  TerminalHistoryItem copyWith({
    String? command,
    int? exitCode,
    String? stdout,
    String? stderr,
    int? durationMs,
    DateTime? timestamp,
    bool? isRunning,
  }) {
    return TerminalHistoryItem(
      command: command ?? this.command,
      exitCode: exitCode ?? this.exitCode,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      durationMs: durationMs ?? this.durationMs,
      timestamp: timestamp ?? this.timestamp,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  factory TerminalHistoryItem.fromJson(Map<String, dynamic> json) {
    return TerminalHistoryItem(
      command: json['command'] as String? ?? '',
      exitCode: json['exit_code'] as int? ?? 0,
      stdout: json['stdout'] as String? ?? '',
      stderr: json['stderr'] as String? ?? '',
      durationMs: json['duration_ms'] as int? ?? 0,
    );
  }
}
