class LLMConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final String backendUrl;

  const LLMConfig({
    this.baseUrl = 'https://openrouter.ai/api/v1',
    this.apiKey = '',
    this.model = 'anthropic/claude-3.5-sonnet',
    this.temperature = 0.2,
    this.backendUrl = 'http://127.0.0.1:8000',
  });

  LLMConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
    String? backendUrl,
  }) {
    return LLMConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      backendUrl: backendUrl ?? this.backendUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'base_url': baseUrl,
      'api_key': apiKey,
      'model': model,
      'temperature': temperature,
    };
  }

  factory LLMConfig.fromJson(Map<String, dynamic> json) {
    return LLMConfig(
      baseUrl: json['base_url'] as String? ?? 'https://openrouter.ai/api/v1',
      apiKey: json['api_key'] as String? ?? '',
      model: json['model'] as String? ?? 'anthropic/claude-3.5-sonnet',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
      backendUrl: json['backend_url'] as String? ?? 'http://127.0.0.1:8000',
    );
  }
}
