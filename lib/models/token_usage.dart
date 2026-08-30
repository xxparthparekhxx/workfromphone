class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int reasoningTokens;
  final int cachedTokens;
  final double? cost;
  final int contextTokens;
  final bool exact;

  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.reasoningTokens = 0,
    this.cachedTokens = 0,
    this.cost,
    this.contextTokens = 0,
    this.exact = true,
  });

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      promptTokens: json['prompt_tokens'] as int? ?? 0,
      completionTokens: json['completion_tokens'] as int? ?? 0,
      totalTokens: json['total_tokens'] as int? ?? 0,
      reasoningTokens: json['reasoning_tokens'] as int? ?? 0,
      cachedTokens: json['cached_tokens'] as int? ?? 0,
      cost: (json['cost'] as num?)?.toDouble(),
      contextTokens: json['context_tokens'] as int? ?? 0,
      exact: json['exact'] as bool? ?? true,
    );
  }
}
