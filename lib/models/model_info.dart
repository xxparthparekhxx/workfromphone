class ModelInfo {
  final String id;
  final String name;
  final String? description;
  final int? contextLength;
  final Map<String, dynamic>? pricing;

  const ModelInfo({
    required this.id,
    required this.name,
    this.description,
    this.contextLength,
    this.pricing,
  });

  bool get isFree {
    if (id.contains(':free') || id.endsWith('/free')) return true;
    final lowerName = name.toLowerCase();
    if (lowerName.contains('(free)') ||
        lowerName.contains('free model') ||
        lowerName.endsWith(' free')) {
      return true;
    }
    if (pricing != null) {
      final p = pricing!['prompt']?.toString();
      final c = pricing!['completion']?.toString();
      if ((p == '0' || p == '0.0' || p == '0.00') &&
          (c == '0' || c == '0.0' || c == '0.00')) {
        return true;
      }
    }
    return false;
  }

  String get provider {
    final lowerId = id.toLowerCase();
    if (lowerId.startsWith('anthropic/') || lowerId.contains('claude')) {
      return 'Anthropic';
    }
    if (lowerId.startsWith('openai/') ||
        lowerId.contains('gpt') ||
        lowerId.startsWith('o1') ||
        lowerId.startsWith('o3')) {
      return 'OpenAI';
    }
    if (lowerId.startsWith('deepseek/')) return 'DeepSeek';
    if (lowerId.startsWith('google/') || lowerId.contains('gemini')) {
      return 'Google';
    }
    if (lowerId.startsWith('meta-llama/') ||
        lowerId.startsWith('meta/') ||
        lowerId.contains('llama')) {
      return 'Meta';
    }
    if (lowerId.startsWith('mistralai/') || lowerId.startsWith('mistral/')) {
      return 'Mistral';
    }
    if (lowerId.startsWith('qwen/') || lowerId.contains('qwen')) return 'Qwen';
    if (lowerId.startsWith('cohere/')) return 'Cohere';
    if (id.contains('/')) {
      final prefix = id.split('/').first;
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
    }
    return 'Other';
  }

  String? get contextLengthFormatted {
    if (contextLength == null || contextLength! <= 0) return null;
    if (contextLength! >= 1000000) {
      final m = contextLength! / 1000000.0;
      return '${m.toStringAsFixed(m % 1 == 0 ? 0 : 1)}M ctx';
    }
    if (contextLength! >= 1000) {
      return '${(contextLength! / 1000).round()}k ctx';
    }
    return '$contextLength ctx';
  }

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? '',
      description: json['description'] as String?,
      contextLength: json['context_length'] as int?,
      pricing: json['pricing'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'context_length': contextLength,
      'pricing': pricing,
    };
  }
}
