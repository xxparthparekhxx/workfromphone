import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/models/conversation_session.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/models/project_directory.dart';

class StorageService {
  static const _keyLLMConfig = 'wfp_llm_config';
  static const _keyRecentProjects = 'wfp_recent_projects';
  static const _prefixConversations = 'wfp_convs_';
  static const _prefixActiveConv = 'wfp_active_conv_';
  static const _keyBackendProfiles = 'wfp_backend_profiles';
  static const _keyActiveBackendProfile = 'wfp_active_backend_profile';
  static const _keyLLMApiKey = 'wfp_secret_llm_api_key';
  static const _keyBackendAccessToken = 'wfp_secret_backend_access_token';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static Future<String?> _readSecret(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeSecret(String key, String value) async {
    try {
      if (value.isEmpty) {
        await _secureStorage.delete(key: key);
      } else {
        await _secureStorage.write(key: key, value: value);
      }
    } catch (_) {
      // Secure storage can be unavailable in tests or headless Linux sessions.
    }
  }

  static Future<LLMConfig> loadLLMConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyLLMConfig);
    if (jsonStr != null) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final legacyApiKey = map['api_key'] as String? ?? '';
        final legacyAccessToken = map['backend_access_token'] as String? ?? '';
        final apiKey = await _readSecret(_keyLLMApiKey) ?? legacyApiKey;
        final accessToken =
            await _readSecret(_keyBackendAccessToken) ?? legacyAccessToken;
        if (legacyApiKey.isNotEmpty || legacyAccessToken.isNotEmpty) {
          await _writeSecret(_keyLLMApiKey, apiKey);
          await _writeSecret(_keyBackendAccessToken, accessToken);
          map.remove('api_key');
          map.remove('backend_access_token');
          await prefs.setString(_keyLLMConfig, jsonEncode(map));
        }
        return LLMConfig.fromJson(map)
            .copyWith(apiKey: apiKey, backendAccessToken: accessToken);
      } catch (_) {}
    }
    return const LLMConfig();
  }

  static Future<void> saveLLMConfig(LLMConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final map = config.toJson();
    map['backend_url'] = config.backendUrl;
    map.remove('api_key');
    map.remove('backend_access_token');
    await prefs.setString(_keyLLMConfig, jsonEncode(map));
    await _writeSecret(_keyLLMApiKey, config.apiKey);
    await _writeSecret(_keyBackendAccessToken, config.backendAccessToken);
  }

  static Future<List<BackendProfile>> loadBackendProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyBackendProfiles);
    if (value == null) return [];
    try {
      return (jsonDecode(value) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(BackendProfile.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveBackendProfile(BackendProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await loadBackendProfiles();
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index < 0) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    await prefs.setString(
      _keyBackendProfiles,
      jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(_keyActiveBackendProfile, profile.id);
  }

  static Future<BackendProfile?> loadActiveBackendProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_keyActiveBackendProfile);
    if (activeId == null) return null;
    final profiles = await loadBackendProfiles();
    for (final profile in profiles) {
      if (profile.id == activeId) return profile;
    }
    return null;
  }

  static Future<void> saveBackendSecret(
    String profileId,
    String name,
    String value,
  ) {
    return _writeSecret('wfp_backend_${profileId}_$name', value);
  }

  static Future<String?> loadBackendSecret(String profileId, String name) {
    return _readSecret('wfp_backend_${profileId}_$name');
  }

  static Future<List<ProjectDirectory>> loadRecentProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyRecentProjects);
    if (jsonStr != null) {
      try {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        return list
            .map((e) => ProjectDirectory.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  static Future<void> saveRecentProject(ProjectDirectory project) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadRecentProjects();
    // Remove if already exists (to bump to top)
    current.removeWhere((p) => p.path == project.path);
    current.insert(0, project);
    // Keep max 15 recent projects
    if (current.length > 15) {
      current.removeRange(15, current.length);
    }
    await prefs.setString(
      _keyRecentProjects,
      jsonEncode(current.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> removeRecentProject(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadRecentProjects();
    current.removeWhere((p) => p.path == path);
    await prefs.setString(
      _keyRecentProjects,
      jsonEncode(current.map((e) => e.toJson()).toList()),
    );
  }

  // --- Multi-Conversation Persistence per Project ---

  static String _projectConvKey(String projectPath) {
    return '$_prefixConversations${projectPath.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
  }

  static String _projectActiveConvKey(String projectPath) {
    return '$_prefixActiveConv${projectPath.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
  }

  static Future<List<ConversationSession>> loadConversations(
    String projectPath,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_projectConvKey(projectPath));
    if (jsonStr != null) {
      try {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        final convs = list
            .map((e) => ConversationSession.fromJson(e as Map<String, dynamic>))
            .toList();
        // Sort newest updated first
        convs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return convs;
      } catch (_) {}
    }
    return [];
  }

  static Future<void> saveConversation(
    String projectPath,
    ConversationSession session,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadConversations(projectPath);
    final idx = list.indexWhere((c) => c.id == session.id);

    if (idx >= 0) {
      list[idx] = session;
    } else {
      list.insert(0, session);
    }

    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    await prefs.setString(
      _projectConvKey(projectPath),
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> deleteConversation(
    String projectPath,
    String conversationId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadConversations(projectPath);
    list.removeWhere((c) => c.id == conversationId);

    await prefs.setString(
      _projectConvKey(projectPath),
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );

    // If active conversation was deleted, clear active key
    final activeId = await loadActiveConversationId(projectPath);
    if (activeId == conversationId) {
      await prefs.remove(_projectActiveConvKey(projectPath));
    }
  }

  static Future<String?> loadActiveConversationId(String projectPath) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_projectActiveConvKey(projectPath));
  }

  static Future<void> saveActiveConversationId(
    String projectPath,
    String conversationId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_projectActiveConvKey(projectPath), conversationId);
  }
}
