import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:workfromphone/models/git_status.dart';
import 'package:workfromphone/models/model_info.dart';
import 'package:workfromphone/models/preview_entry.dart';
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

/// Typed HTTP failure so UI can distinguish re-auth (401), rate limits
/// (429), oversized payloads (413) and offline/TLS errors instead of parsing
/// a generic `Exception('HTTP N')` string.
class ApiException implements Exception {
  final int? statusCode;
  final String detail;
  final String context;

  const ApiException(this.detail, {this.statusCode, this.context = ''});

  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;
  bool get isPayloadTooLarge => statusCode == 413;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => context.isEmpty ? detail : '$context: $detail';
}

/// Distinguishes "server unreachable" from "reachable but refusing".
enum ServerReachability { online, unauthorized, offline }

class ApiService {
  static String _accessToken = '';
  static String _authenticatedOrigin = '';

  static String cleanUrl(String url) => url.replaceAll(RegExp(r'/+$'), '');

  /// True when [url] would send the bearer token and LLM key over cleartext
  /// HTTP. Callers surface a warning; LAN/VPN use is the accepted exception.
  static bool isCleartextUrl(String url) {
    final trimmed = url.trim().toLowerCase();
    if (trimmed.startsWith('https://') || trimmed.startsWith('wss://')) {
      return false;
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('ws://')) {
      return true;
    }
    // Schemaless input is auto-prefixed with http:// (see _save flows).
    return true;
  }

  /// Normalize user-typed backend input: trim, add an explicit scheme when
  /// missing (http, with a cleartext warning shown by the caller), strip
  /// trailing slashes.
  static String normalizeBackendUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.contains('://')) {
      url = 'http://$url';
    }
    return cleanUrl(url);
  }

  static void configureAccessToken(String token, {String? backendUrl}) {
    _accessToken = token.trim();
    _authenticatedOrigin = backendUrl == null || backendUrl.trim().isEmpty
        ? ''
        : _originOf(Uri.parse(cleanUrl(backendUrl)));
  }

  /// The comparable origin of [uri], or `''` when it has none.
  ///
  /// `ws`/`wss` are folded onto `http`/`https` so a WebSocket endpoint is
  /// matched against the same configured origin as the REST endpoints, and a
  /// URL without a usable scheme or host never matches anything.
  static String _originOf(Uri uri) {
    final normalized = switch (uri.scheme) {
      'ws' => uri.replace(scheme: 'http'),
      'wss' => uri.replace(scheme: 'https'),
      _ => uri,
    };
    try {
      return normalized.origin;
    } on StateError {
      return '';
    }
  }

  /// Whether the configured backend token may be sent to [uri].
  ///
  /// The token is scoped to the origin it was configured for, so it is never
  /// forwarded to another host after the backend URL changes.
  static bool _mayAuthenticate(Uri uri) {
    if (_accessToken.isEmpty || _authenticatedOrigin.isEmpty) return false;
    return _originOf(uri) == _authenticatedOrigin;
  }

  static Map<String, String> headers({bool json = false, Uri? uri}) {
    final maySendToken = uri != null && _mayAuthenticate(uri);
    return {
      if (json) 'Content-Type': 'application/json',
      if (maySendToken) 'Authorization': 'Bearer $_accessToken',
    };
  }

  /// Per-request auth headers for an explicit [token] without touching the
  /// global configured token. Use this for concurrent/secondary backend calls
  /// so a per-request token can never race the globally configured one.
  static Map<String, String> headersFor({
    required String token,
    required String backendUrl,
    required Uri uri,
    bool json = false,
  }) {
    final trimmed = token.trim();
    var maySend = false;
    if (trimmed.isNotEmpty) {
      final scope = backendUrl.trim().isEmpty
          ? ''
          : _originOf(Uri.parse(cleanUrl(backendUrl)));
      maySend = scope.isNotEmpty && _originOf(uri) == scope;
    }
    return {
      if (json) 'Content-Type': 'application/json',
      if (maySend) 'Authorization': 'Bearer $trimmed',
    };
  }

  /// Decode a JSON `detail`/`error.message` body, falling back to HTTP code.
  static String decodeErrorDetail(dynamic body, int statusCode) {
    var detail = 'HTTP $statusCode';
    try {
      final parsed = jsonDecode(body as String);
      if (parsed is Map<String, dynamic>) {
        final direct = parsed['detail'];
        if (direct is String && direct.isNotEmpty) return direct;
        final error = parsed['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        } else if (error is String && error.isNotEmpty) {
          return error;
        }
      }
    } catch (_) {}
    return detail;
  }

  static Never throwForStatus(dynamic resp, String context) {
    throw ApiException(
      decodeErrorDetail(resp.body, resp.statusCode),
      statusCode: resp.statusCode,
      context: context,
    );
  }

  /// Handshake headers for a WebSocket session connecting to [uri].
  ///
  /// [token] is only attached when [uri] targets the currently configured
  /// backend origin, so a session left over from a previous backend URL
  /// cannot leak its token to a new host.
  static Map<String, String> webSocketAuthHeaders(Uri uri, String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty || _authenticatedOrigin.isEmpty) return const {};
    if (_originOf(uri) != _authenticatedOrigin) return const {};
    return {'Authorization': 'Bearer $trimmed'};
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
    return (await probeServer(backendUrl)) == ServerReachability.online;
  }

  /// Probe distinguishing reachable (200), auth-guarded (401 on health means
  /// a capability probe — health itself is public, so any 401 here surfaces
  /// as unauthorized), and offline/TLS failures.
  static Future<ServerReachability> probeServer(String backendUrl) async {
    try {
      final uri = Uri.parse('${cleanUrl(backendUrl)}/api/v1/health');
      final resp = await _get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) return ServerReachability.online;
      if (resp.statusCode == 401) return ServerReachability.unauthorized;
      return ServerReachability.offline;
    } catch (_) {
      return ServerReachability.offline;
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
      throwForStatus(resp, 'Failed to browse directory');
    }
    return BrowseResult.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  static Future<QuickPathsData> getQuickPaths(String backendUrl) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/fs/quick-paths');
    final resp = await _get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throwForStatus(resp, 'Failed to load quick paths');
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
      throwForStatus(resp, 'Failed to list project files');
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
      throwForStatus(resp, 'Path validation failed');
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
      throwForStatus(resp, 'Failed to fetch models');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawList = data['models'] as List<dynamic>? ?? [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(ModelInfo.fromJson)
        .where((model) => model.id.isNotEmpty)
        .toList();
  }

  /// Live models from the configured provider, via the backend then directly.
  static Future<List<ModelInfo>> fetchProviderModels({
    required String backendUrl,
    required String baseUrl,
    required String apiKey,
  }) async {
    Object? backendError;
    try {
      final list = await fetchModels(backendUrl, baseUrl, apiKey);
      if (list.isNotEmpty) return list;
    } catch (error) {
      backendError = error;
    }
    try {
      return await fetchRouterModels(baseUrl: baseUrl, apiKey: apiKey);
    } catch (error) {
      throw backendError ?? error;
    }
  }

  /// Fetch models directly from OpenRouter or an OpenAI-compatible router.
  static Future<List<ModelInfo>> fetchRouterModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    var clean = cleanUrl(baseUrl);
    if (clean.isEmpty) {
      clean = 'https://openrouter.ai/api/v1';
    }
    final uri = Uri.parse('$clean/models');
    final headers = <String, String>{
      'Accept': 'application/json',
      'HTTP-Referer': 'https://workfromphone.app',
      'X-Title': 'WorkFromPhone',
    };
    final key = apiKey.trim();
    if (key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
    }
    final resp = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throwForStatus(resp, 'Failed to fetch models');
    }
    final decoded = jsonDecode(resp.body);
    final rawList = decoded is Map<String, dynamic>
        ? (decoded['data'] as List<dynamic>? ??
              decoded['models'] as List<dynamic>? ??
              [])
        : <dynamic>[];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(ModelInfo.fromJson)
        .where((model) => model.id.isNotEmpty)
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
      throwForStatus(resp, 'Failed to read file');
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
      throwForStatus(resp, 'Failed to write file');
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
      throwForStatus(resp, 'Failed to create item');
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
      throwForStatus(resp, 'Failed to delete item');
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
      throw ApiException(
        decodeErrorDetail(response.body, response.statusCode),
        statusCode: response.statusCode,
        context: 'Upload failed',
      );
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
      throwForStatus(resp, 'Terminal command execution failed');
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
      throwForStatus(resp, 'Failed to load Git status');
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
      throwForStatus(resp, 'Failed to load Git diff');
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
      throwForStatus(resp, 'Failed to stage files');
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
      throwForStatus(resp, 'Failed to unstage files');
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
      throwForStatus(resp, 'Failed to discard changes');
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
      throwForStatus(resp, 'Failed to commit');
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
      throwForStatus(resp, 'Failed to push');
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
      throwForStatus(resp, 'Failed to pull');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['success'] as bool? ?? false;
  }

  // --- Preview Browser ---

  static Future<List<PreviewEntry>> listPreviews(
    String backendUrl, {
    required String projectPath,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/preview')
        .replace(queryParameters: {'project_path': projectPath});
    final resp = await _get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throwForStatus(resp, 'Failed to list previews');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = (data['entries'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>();
    return raw.map(PreviewEntry.fromJson).toList();
  }

  static Future<PreviewEntry> registerPreview(
    String backendUrl, {
    required String projectPath,
    required int port,
    required String label,
    String basePath = '',
    String source = 'manual',
    String? id,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/preview/register');
    final resp = await _post(
      uri,
      body: jsonEncode({
        'project_path': projectPath,
        'port': port,
        'label': label,
        'base_path': basePath,
        'source': source,
        ?id: id,
      }),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throwForStatus(resp, 'Failed to register preview');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final entry = data['entry'] as Map<String, dynamic>?;
    if (entry == null) {
      throw const ApiException('Preview registration returned no entry');
    }
    return PreviewEntry.fromJson(entry);
  }

  static Future<void> unregisterPreview(
    String backendUrl, {
    required String id,
  }) async {
    final base = cleanUrl(backendUrl);
    final uri = Uri.parse('$base/api/v1/preview/unregister');
    final resp = await _post(
      uri,
      body: jsonEncode({'id': id}),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throwForStatus(resp, 'Failed to unregister preview');
    }
  }

  /// Build the in-app URL the WebView should load for [entry].
  ///
  /// The proxy lives at `/api/v1/preview/proxy/{id}/{path}`, which strips
  /// the `/api/v1` prefix concern out of the device and lets the WebView
  /// act on the same backend origin as every other request, so the
  /// bearer token is forwarded through `WebViewController.loadRequest`
  /// headers.
  static bool isPreviewNavigationAllowed({
    required String backendUrl,
    required String entryId,
    required String url,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (_originOf(uri) != _originOf(Uri.parse(cleanUrl(backendUrl)))) {
      return false;
    }
    final prefix = '/api/v1/preview/proxy/$entryId';
    return uri.path == prefix || uri.path.startsWith('$prefix/');
  }

  static Uri previewUri(
    String backendUrl, {
    required String entryId,
    String path = '/',
  }) {
    final base = cleanUrl(backendUrl);
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base/api/v1/preview/proxy/$entryId$normalized');
  }
}
