import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:workfromphone/models/git_status.dart';
import 'package:workfromphone/models/model_info.dart';
import 'package:workfromphone/models/terminal_output.dart';

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

class FileContentResult {
  final String path;
  final int totalLines;
  final String content;

  FileContentResult({
    required this.path,
    required this.totalLines,
    required this.content,
  });

  factory FileContentResult.fromJson(Map<String, dynamic> json) {
    return FileContentResult(
      path: json['path'] as String? ?? '',
      totalLines: json['total_lines'] as int? ?? 0,
      content: json['content'] as String? ?? '',
    );
  }
}

class ProjectFilesData {
  final List<String> files;
  final bool truncated;

  const ProjectFilesData({required this.files, required this.truncated});

  factory ProjectFilesData.fromJson(Map<String, dynamic> json) {
    return ProjectFilesData(
      files: ((json['files'] as List<dynamic>?) ?? [])
          .whereType<String>()
          .toList(),
      truncated: json['truncated'] as bool? ?? false,
    );
  }
}

class UploadFileData {
  final String name;
  final int size;
  final Stream<List<int>> stream;

  const UploadFileData({
    required this.name,
    required this.size,
    required this.stream,
  });
}

class ApiService {
  static String _accessToken = '';
  static String _authenticatedOrigin = '';

  static String cleanUrl(String url) => url.replaceAll(RegExp(r'/+$'), '');

  static void configureAccessToken(String token, {String? backendUrl}) {
    _accessToken = token.trim();
    _authenticatedOrigin = backendUrl == null || backendUrl.trim().isEmpty
        ? ''
        : Uri.parse(cleanUrl(backendUrl)).origin;
  }

  static Map<String, String> headers({bool json = false, Uri? uri}) {
    final maySendToken =
        _accessToken.isNotEmpty &&
        uri != null &&
        uri.origin == _authenticatedOrigin;
    return {
      if (json) 'Content-Type': 'application/json',
      if (maySendToken) 'Authorization': 'Bearer $_accessToken',
    };
  }

  static Future<http.Response> _get(Uri uri) {
    return http.get(uri, headers: headers(uri: uri));
  }

  static Future<http.Response> _post(Uri uri, {Object? body}) {
    return http.post(
      uri,
      headers: headers(json: body != null, uri: uri),
      body: body,
    );
  }

  static Future<http.Response> _delete(Uri uri, {Object? body}) {
    return http.delete(
      uri,
      headers: headers(json: body != null, uri: uri),
      body: body,
    );
  }

  static Future<bool> testServer(String backendUrl) async {
    try {
      final uri = Uri.parse('${cleanUrl(backendUrl)}/api/v1/health');
      final resp = await _get(uri).timeout(const Duration(seconds: 4));
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
    final resp = await _get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Failed to browse directory: HTTP ${resp.statusCode}');
    }
    return BrowseResult.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  static Future<QuickPathsData> getQuickPaths(String backendUrl) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/fs/quick-paths');
    final resp = await _get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load quick paths: HTTP ${resp.statusCode}');
    }
    return QuickPathsData.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  static Future<ProjectFilesData> listProjectFiles(
    String backendUrl, {
    required String projectPath,
    int limit = 5000,
  }) async {
    final uri = Uri.parse('${cleanUrl(backendUrl)}/api/v1/fs/project-files')
        .replace(
          queryParameters: {
            'project_path': projectPath,
            'limit': limit.toString(),
          },
        );
    final resp = await _get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('Failed to list project files: HTTP ${resp.statusCode}');
    }
    return ProjectFilesData.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  static Future<Map<String, dynamic>> validatePath(
    String backendUrl,
    String path,
  ) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/fs/validate');
    final resp = await _post(
      uri,
      body: jsonEncode({'path': path}),
    ).timeout(const Duration(seconds: 10));
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
    final resp = await _post(
      uri,
      body: jsonEncode({'base_url': baseUrl, 'api_key': apiKey}),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch models: HTTP ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawList = data['models'] as List<dynamic>? ?? [];
    return rawList
        .map((e) => ModelInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Filesystem File CRUD Operations ---

  static Future<FileContentResult> readFile(
    String backendUrl, {
    required String projectPath,
    required String relativePath,
    int? startLine,
    int? endLine,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/fs/file').replace(
      queryParameters: {
        'project_path': projectPath,
        'relative_path': relativePath,
        if (startLine != null) 'start_line': startLine.toString(),
        if (endLine != null) 'end_line': endLine.toString(),
      },
    );

    final resp = await _get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Failed to read file: HTTP ${resp.statusCode}');
    }
    return FileContentResult.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  static Future<bool> writeFile(
    String backendUrl, {
    required String projectPath,
    required String relativePath,
    required String content,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/fs/file');
    final resp = await _post(
      uri,
      body: jsonEncode({
        'project_path': projectPath,
        'relative_path': relativePath,
        'content': content,
      }),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Failed to write file: HTTP ${resp.statusCode}');
    }
    return true;
  }

  static Future<bool> createItem(
    String backendUrl, {
    required String projectPath,
    required String relativePath,
    bool isDir = false,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/fs/create');
    final resp = await _post(
      uri,
      body: jsonEncode({
        'project_path': projectPath,
        'relative_path': relativePath,
        'is_dir': isDir,
      }),
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw Exception('Failed to create item: HTTP ${resp.statusCode}');
    }
    return true;
  }

  static Future<bool> deleteItem(
    String backendUrl, {
    required String projectPath,
    required String relativePath,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/fs/file');
    final resp = await _delete(
      uri,
      body: jsonEncode({
        'project_path': projectPath,
        'relative_path': relativePath,
      }),
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw Exception('Failed to delete item: HTTP ${resp.statusCode}');
    }
    return true;
  }

  static Future<List<String>> uploadFiles(
    String backendUrl, {
    required String projectPath,
    required String relativeDirectory,
    required List<UploadFileData> files,
    bool overwrite = false,
  }) async {
    final uri = Uri.parse('${cleanUrl(backendUrl)}/api/v1/fs/upload');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers(uri: uri))
      ..fields['project_path'] = projectPath
      ..fields['relative_directory'] = relativeDirectory
      ..fields['overwrite'] = overwrite.toString();
    for (final file in files) {
      request.files.add(
        http.MultipartFile(
          'files',
          file.stream,
          file.size,
          filename: file.name,
        ),
      );
    }

    final streamed = await request.send().timeout(const Duration(minutes: 15));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      var detail = 'HTTP ${response.statusCode}';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        detail = body['detail']?.toString() ?? detail;
      } catch (_) {}
      throw Exception('Upload failed: $detail');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ((body['files'] as List<dynamic>?) ?? [])
        .whereType<Map<String, dynamic>>()
        .map((file) => file['path'] as String? ?? '')
        .where((path) => path.isNotEmpty)
        .toList();
  }

  static Uri fileDownloadUri(
    String backendUrl, {
    required String projectPath,
    required String relativePath,
  }) {
    return Uri.parse('${cleanUrl(backendUrl)}/api/v1/fs/download').replace(
      queryParameters: {
        'project_path': projectPath,
        'relative_path': relativePath,
      },
    );
  }

  // --- Terminal Execution Operations ---

  static Future<TerminalHistoryItem> runTerminalCommand(
    String backendUrl, {
    required String projectPath,
    required String command,
    double timeoutSeconds = 60.0,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/terminal/run');
    final resp = await _post(
      uri,
      body: jsonEncode({
        'project_path': projectPath,
        'command': command,
        'timeout_seconds': timeoutSeconds,
      }),
    ).timeout(Duration(seconds: timeoutSeconds.toInt() + 5));

    if (resp.statusCode != 200) {
      throw Exception(
        'Terminal command execution failed: HTTP ${resp.statusCode}',
      );
    }

    return TerminalHistoryItem.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  // --- Git Source Control Operations ---

  static Future<GitStatusData> getGitStatus(
    String backendUrl, {
    required String projectPath,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/git/status')
        .replace(queryParameters: {'project_path': projectPath});
    final resp = await _get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load Git status: HTTP ${resp.statusCode}');
    }
    return GitStatusData.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  static Future<String> getGitDiff(
    String backendUrl, {
    required String projectPath,
    String? relativePath,
    bool staged = false,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/git/diff').replace(
      queryParameters: {
        'project_path': projectPath,
        if (relativePath != null && relativePath.isNotEmpty)
          'relative_path': relativePath,
        'staged': staged.toString(),
      },
    );
    final resp = await _get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load Git diff: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['diff'] as String? ?? '';
  }

  static Future<bool> stageGitFiles(
    String backendUrl, {
    required String projectPath,
    List<String>? paths,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/git/stage');
    final resp = await _post(
      uri,
      body: jsonEncode({'project_path': projectPath, 'paths': paths}),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Failed to stage files: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['success'] as bool? ?? false;
  }

  static Future<bool> unstageGitFiles(
    String backendUrl, {
    required String projectPath,
    List<String>? paths,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/git/unstage');
    final resp = await _post(
      uri,
      body: jsonEncode({'project_path': projectPath, 'paths': paths}),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Failed to unstage files: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['success'] as bool? ?? false;
  }

  static Future<bool> discardGitChanges(
    String backendUrl, {
    required String projectPath,
    required List<String> paths,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/git/discard');
    final resp = await _post(
      uri,
      body: jsonEncode({'project_path': projectPath, 'paths': paths}),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Failed to discard changes: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['success'] as bool? ?? false;
  }

  static Future<bool> commitGit(
    String backendUrl, {
    required String projectPath,
    required String message,
    bool stageAll = false,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/git/commit');
    final resp = await _post(
      uri,
      body: jsonEncode({
        'project_path': projectPath,
        'message': message,
        'stage_all': stageAll,
      }),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Failed to commit: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['success'] as bool? ?? false;
  }

  static Future<bool> pushGit(
    String backendUrl, {
    required String projectPath,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/git/push')
        .replace(queryParameters: {'project_path': projectPath});
    final resp = await _post(uri).timeout(const Duration(seconds: 45));
    if (resp.statusCode != 200) {
      throw Exception('Failed to push: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['success'] as bool? ?? false;
  }

  static Future<bool> pullGit(
    String backendUrl, {
    required String projectPath,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/git/pull')
        .replace(queryParameters: {'project_path': projectPath});
    final resp = await _post(uri).timeout(const Duration(seconds: 45));
    if (resp.statusCode != 200) {
      throw Exception('Failed to pull: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['success'] as bool? ?? false;
  }
}
