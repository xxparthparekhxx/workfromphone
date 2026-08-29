class ModelInfo {
  final String id;
  final String name;
  final String? description;
  final int? contextLength;

  const ModelInfo({
    required this.id,
    required this.name,
    this.description,
    this.contextLength,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? '',
      description: json['description'] as String?,
      contextLength: json['context_length'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'context_length': contextLength,
    };
  }
}
