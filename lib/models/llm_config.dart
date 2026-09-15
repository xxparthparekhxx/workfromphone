class LLMConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final String backendUrl;
  final String backendAccessToken;

  const LLMConfig({
    this.baseUrl = 'https://openrouter.ai/api/v1',
    this.apiKey = '',
    this.model = 'anthropic/claude-3.5-sonnet',
    this.temperature = 0.2,
    this.backendUrl = 'http://127.0.0.1:8000',
    this.backendAccessToken = '',
  });

  LLMConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
    String? backendUrl,
    String? backendAccessToken,
  }) {
    return LLMConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      backendUrl: backendUrl ?? this.backendUrl,
      backendAccessToken: backendAccessToken ?? this.backendAccessToken,
    );
  }

  /// Serialize WITHOUT secrets by default so callers can never persist an
  /// LLM key or backend token to plaintext SharedPreferences by accident.
  /// Pass `includeSecrets: true` only for in-memory API payloads sent to the
  /// configured backend over the network (never for storage).
  Map<String, dynamic> toJson({bool includeSecrets = false}) {
    return {
      'base_url': baseUrl,
      if (includeSecrets) 'api_key': apiKey,
      'model': model,
      'temperature': temperature,
      'backend_url': backendUrl,
      if (includeSecrets) 'backend_access_token': backendAccessToken,
    };
  }

  /// Explicit secrets-included payload for backend API calls only.
  Map<String, dynamic> toApiJson() => toJson(includeSecrets: true);

  factory LLMConfig.fromJson(Map<String, dynamic> json) {
    return LLMConfig(
      baseUrl: json['base_url'] as String? ?? 'https://openrouter.ai/api/v1',
      apiKey: json['api_key'] as String? ?? '',
      model: json['model'] as String? ?? 'anthropic/claude-3.5-sonnet',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
      backendUrl: json['backend_url'] as String? ?? 'http://127.0.0.1:8000',
      backendAccessToken: json['backend_access_token'] as String? ?? '',
    );
  }
}
