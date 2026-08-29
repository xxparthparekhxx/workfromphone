class ProjectDirectory {
  final String name;
  final String path;
  final String? projectType; // e.g. "flutter", "python", "node", "rust", "go", "git"
  final DateTime lastOpened;

  const ProjectDirectory({
    required this.name,
    required this.path,
    this.projectType,
    required this.lastOpened,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'project_type': projectType,
      'last_opened': lastOpened.toIso8601String(),
    };
  }

  factory ProjectDirectory.fromJson(Map<String, dynamic> json) {
    return ProjectDirectory(
      name: json['name'] as String? ?? 'Untitled Project',
      path: json['path'] as String? ?? '',
      projectType: json['project_type'] as String?,
      lastOpened: json['last_opened'] != null
          ? DateTime.tryParse(json['last_opened'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
