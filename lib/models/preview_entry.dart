class PreviewEntry {
  final String id;
  final String projectPath;
  final int port;
  final String label;
  final String basePath;
  final DateTime registeredAt;
  final String source;

  const PreviewEntry({
    required this.id,
    required this.projectPath,
    required this.port,
    required this.label,
    required this.basePath,
    required this.registeredAt,
    required this.source,
  });

  factory PreviewEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['registered_at'];
    final parsed = raw is String
        ? DateTime.tryParse(raw)?.toLocal() ?? DateTime.now()
        : DateTime.now();
    return PreviewEntry(
      id: json['id'] as String? ?? '',
      projectPath: json['project_path'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      label: json['label'] as String? ?? '',
      basePath: json['base_path'] as String? ?? '',
      registeredAt: parsed,
      source: json['source'] as String? ?? 'manual',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_path': projectPath,
    'port': port,
    'label': label,
    'base_path': basePath,
    'registered_at': registeredAt.toUtc().toIso8601String(),
    'source': source,
  };
}
