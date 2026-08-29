import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:workfromphone/models/model_info.dart';

class BrowseResult {
  final String currentPath;
  final String? parentPath;
  final String homePath;
  final List<DirectoryItemData> items;
  final bool isProject;
  final String? projectType;

  BrowseResult({
    required this.currentPath,
    this.parentPath,
    required this.homePath,
    required this.items,
    this.isProject = false,
    this.projectType,
  });

  factory BrowseResult.fromJson(Map<String, dynamic> json) {
    return BrowseResult(
      currentPath: json['current_path'] as String? ?? '',
      parentPath: json['parent_path'] as String?,
      homePath: json['home_path'] as String? ?? '',
      items: ((json['items'] as List<dynamic>?) ?? [])
          .map((e) => DirectoryItemData.fromJson(e as Map<String, dynamic>))
          .toList(),
      isProject: json['is_project'] as bool? ?? false,
      projectType: json['project_type'] as String?,
    );
  }
}

class DirectoryItemData {
  final String name;
  final String path;
  final bool isDir;
  final bool isProject;
  final String? projectType;
  final int? sizeBytes;
  final String? modifiedAt;

  DirectoryItemData({
    required this.name,
    required this.path,
    required this.isDir,
    this.isProject = false,
    this.projectType,
    this.sizeBytes,
    this.modifiedAt,
  });

  factory DirectoryItemData.fromJson(Map<String, dynamic> json) {
    return DirectoryItemData(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      isDir: json['is_dir'] as bool? ?? false,
      isProject: json['is_project'] as bool? ?? false,
      projectType: json['project_type'] as String?,
      sizeBytes: json['size_bytes'] as int?,
      modifiedAt: json['modified_at'] as String?,
    );
  }
}

class QuickPathsData {
  final String home;
  final String currentWorkspace;
  final List<DirectoryItemData> commonPaths;

  QuickPathsData({
    required this.home,
    required this.currentWorkspace,
    required this.commonPaths,
  });

  factory QuickPathsData.fromJson(Map<String, dynamic> json) {
    return QuickPathsData(
      home: json['home'] as String? ?? '',
      currentWorkspace: json['current_workspace'] as String? ?? '',
      commonPaths: ((json['common_paths'] as List<dynamic>?) ?? [])
          .map((e) => DirectoryItemData.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ApiService {
  static String cleanUrl(String url) => url.replaceAll(RegExp(r'/+$'), '');

  static Future<bool> testServer(String backendUrl) async {
    try {
      final uri = Uri.parse('${cleanUrl(backendUrl)}/api/v1/health');
      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<BrowseResult> browseDirectory(
    String backendUrl, {
    String? path,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/fs/browse').replace(
      queryParameters: path != null && path.isNotEmpty ? {'path': path} : null,
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Failed to browse directory: HTTP ${resp.statusCode}');
    }
    return BrowseResult.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  static Future<QuickPathsData> getQuickPaths(String backendUrl) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/fs/quick-paths');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load quick paths: HTTP ${resp.statusCode}');
    }
    return QuickPathsData.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  static Future<Map<String, dynamic>> validatePath(
    String backendUrl,
    String path,
  ) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/fs/validate');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'path': path}),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Path validation failed');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  static Future<List<ModelInfo>> fetchModels(
    String backendUrl,
    String baseUrl,
    String apiKey,
  ) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/llm/models');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'base_url': baseUrl,
            'api_key': apiKey,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch models: HTTP ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawList = data['models'] as List<dynamic>? ?? [];
    return rawList.map((e) => ModelInfo.fromJson(e as Map<String, dynamic>)).toList();
  }
}
