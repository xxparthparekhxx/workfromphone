class TaskStats {
  final int totalTokens;
  final int promptTokens;
  final int completionTokens;
  final double tokensPerSecond;
  final int durationMs;
  final int contextLimit;
  final int toolCallsCount;
  final int stepsCount;
  final bool isStreaming;
  final int contextTokens;
  final int reasoningTokens;
  final int cachedTokens;
  final double cost;
  final bool usageIsEstimated;

  const TaskStats({
    this.totalTokens = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.tokensPerSecond = 0.0,
    this.durationMs = 0,
    this.contextLimit = 200000,
    this.toolCallsCount = 0,
    this.stepsCount = 0,
    this.isStreaming = false,
    this.contextTokens = 0,
    this.reasoningTokens = 0,
    this.cachedTokens = 0,
    this.cost = 0.0,
    this.usageIsEstimated = true,
  });

  double get contextUsagePercent {
    if (contextLimit <= 0) return 0.0;
    return (effectiveContextTokens / contextLimit * 100).clamp(0.0, 100.0);
  }

  int get effectiveContextTokens =>
      contextTokens > 0 ? contextTokens : totalTokens;

  String get formattedContextRatio {
    String formatK(int num) {
      if (num >= 1000000) {
        final val = num / 1000000.0;
        return val == val.roundToDouble()
            ? '${val.toInt()}M'
            : '${val.toStringAsFixed(1)}M';
      }
      if (num >= 1000) {
        final val = num / 1000.0;
        return val == val.roundToDouble()
            ? '${val.toInt()}k'
            : '${val.toStringAsFixed(1)}k';
      }
      return '$num';
    }

    return '${formatK(effectiveContextTokens)} / ${formatK(contextLimit)} (${contextUsagePercent.toStringAsFixed(1)}%)';
  }

  String get formattedSessionTokens {
    if (totalTokens >= 1000000) {
      return '${(totalTokens / 1000000).toStringAsFixed(2)}M';
    }
    if (totalTokens >= 1000) {
      return '${(totalTokens / 1000).toStringAsFixed(1)}k';
    }
    return '$totalTokens';
  }

  String get formattedCost => cost > 0 ? '\$${cost.toStringAsFixed(4)}' : '—';

  String get formattedDuration {
    final s = durationMs / 1000.0;
    return '${s.toStringAsFixed(1)}s';
  }

  String get formattedTps {
    return '${tokensPerSecond.toStringAsFixed(1)} tps';
  }

  Map<String, dynamic> toJson() {
    return {
      'total_tokens': totalTokens,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'tps': tokensPerSecond,
      'duration_ms': durationMs,
      'context_limit': contextLimit,
      'tool_calls_count': toolCallsCount,
      'steps_count': stepsCount,
      'context_tokens': contextTokens,
      'reasoning_tokens': reasoningTokens,
      'cached_tokens': cachedTokens,
      'cost': cost,
      'usage_is_estimated': usageIsEstimated,
    };
  }

  factory TaskStats.fromJson(Map<String, dynamic> json) {
    return TaskStats(
      totalTokens: json['total_tokens'] as int? ?? 0,
      promptTokens: json['prompt_tokens'] as int? ?? 0,
      completionTokens: json['completion_tokens'] as int? ?? 0,
      tokensPerSecond: (json['tps'] as num?)?.toDouble() ?? 0.0,
      durationMs: json['duration_ms'] as int? ?? 0,
      contextLimit: json['context_limit'] as int? ?? 200000,
      toolCallsCount: json['tool_calls_count'] as int? ?? 0,
      stepsCount: json['steps_count'] as int? ?? 0,
      isStreaming: false,
      contextTokens: json['context_tokens'] as int? ?? 0,
      reasoningTokens: json['reasoning_tokens'] as int? ?? 0,
      cachedTokens: json['cached_tokens'] as int? ?? 0,
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
      usageIsEstimated: json['usage_is_estimated'] as bool? ?? true,
    );
  }

  TaskStats copyWith({
    int? totalTokens,
    int? promptTokens,
    int? completionTokens,
    double? tokensPerSecond,
    int? durationMs,
    int? contextLimit,
    int? toolCallsCount,
    int? stepsCount,
    bool? isStreaming,
    int? contextTokens,
    int? reasoningTokens,
    int? cachedTokens,
    double? cost,
    bool? usageIsEstimated,
  }) {
    return TaskStats(
      totalTokens: totalTokens ?? this.totalTokens,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      durationMs: durationMs ?? this.durationMs,
      contextLimit: contextLimit ?? this.contextLimit,
      toolCallsCount: toolCallsCount ?? this.toolCallsCount,
      stepsCount: stepsCount ?? this.stepsCount,
      isStreaming: isStreaming ?? this.isStreaming,
      contextTokens: contextTokens ?? this.contextTokens,
      reasoningTokens: reasoningTokens ?? this.reasoningTokens,
      cachedTokens: cachedTokens ?? this.cachedTokens,
      cost: cost ?? this.cost,
      usageIsEstimated: usageIsEstimated ?? this.usageIsEstimated,
    );
  }
}
