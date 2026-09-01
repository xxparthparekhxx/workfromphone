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
  static const _keyGeneralConversations = 'wfp_general_convs';
  static const _keyActiveGeneralConv = 'wfp_active_general_conv';
  static const _keyGeneralWebSearch = 'wfp_general_web_search';
  static const _keyBackendProfiles = 'wfp_backend_profiles';
  static const _keyActiveBackendProfile = 'wfp_active_backend_profile';
  static const _keyCentralHubProfile = 'wfp_central_hub_profile';
  static const _keyLLMApiKey = 'wfp_secret_llm_api_key';
  static const _keyBackendAccessToken = 'wfp_secret_backend_access_token';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
      migrateOnAlgorithmChange: true,
      storageNamespace: 'workfromphone',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _backendSecretNames = ['access_token', 'ssh_password'];
  static bool secretsPersistFailed = false;

  static Future<String?> _readSecret(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _writeSecret(String key, String value) async {
    try {
      if (value.isEmpty) {
        await _secureStorage.delete(key: key);
      } else {
        await _secureStorage.write(key: key, value: value);
      }
      secretsPersistFailed = false;
      return true;
    } catch (_) {
      // Secure storage can be unavailable in tests or headless Linux sessions.
      secretsPersistFailed = true;
      return false;
    }
  }

  static Future<LLMConfig> loadLLMConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final activeProfile = await loadActiveBackendProfile();
    final jsonStr = prefs.getString(_keyLLMConfig);
    if (jsonStr != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
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
        var config = LLMConfig.fromJson(map)
            .copyWith(apiKey: apiKey, backendAccessToken: accessToken);
        if (activeProfile != null) {
          config = config.copyWith(backendUrl: activeProfile.backendUrl);
        }
        return config;
      } catch (_) {}
    }
    if (activeProfile != null) {
      return LLMConfig(backendUrl: activeProfile.backendUrl);
    }
    return const LLMConfig();
  }

  static Future<void> saveLLMConfig(LLMConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKeySaved = await _writeSecret(_keyLLMApiKey, config.apiKey);
    final tokenSaved = await _writeSecret(
      _keyBackendAccessToken,
      config.backendAccessToken,
    );
    final map = config.toJson();
    map['backend_url'] = config.backendUrl;
    if (apiKeySaved) {
      map.remove('api_key');
    }
    if (tokenSaved) {
      map.remove('backend_access_token');
    } else {
      map['backend_access_token'] = config.backendAccessToken;
    }
    await prefs.setString(_keyLLMConfig, jsonEncode(map));
  }

  // --- Backend Profiles Management ---

  static Future<List<BackendProfile>> loadBackendProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyBackendProfiles);
    if (value == null) return [];
    try {
      final decoded = jsonDecode(value) as List<dynamic>;
      return decoded
          .map(
            (item) =>
                BackendProfile.fromJson(Map<String, dynamic>.from(item as Map)),
          )
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
    if (!profile.isHub) {
      await prefs.setString(_keyActiveBackendProfile, profile.id);
    }
  }

  static Future<void> deleteBackendProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await loadBackendProfiles();
    profiles.removeWhere((p) => p.id == profileId);
    await prefs.setString(
      _keyBackendProfiles,
      jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
    final activeId = prefs.getString(_keyActiveBackendProfile);
    if (activeId == profileId) {
      final remaining = profiles.where((p) => !p.isHub).toList();
      if (remaining.isNotEmpty) {
        await prefs.setString(_keyActiveBackendProfile, remaining.first.id);
      } else {
        await prefs.remove(_keyActiveBackendProfile);
      }
    }
    await _deleteBackendSecrets(profileId);
  }

  static Future<void> _deleteBackendSecrets(String profileId) async {
    for (final name in _backendSecretNames) {
      await _writeSecret('wfp_backend_${profileId}_$name', '');
    }
  }

  static Future<BackendProfile?> loadActiveBackendProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_keyActiveBackendProfile);
    if (activeId == null) return null;
    final profiles = await loadBackendProfiles();
    for (final profile in profiles) {
      if (profile.id == activeId && !profile.isHub) return profile;
    }
    return null;
  }

  static Future<void> setActiveBackendProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveBackendProfile, profileId);
  }

  // --- Dedicated Central Hub Profile ---

  static Future<BackendProfile?> loadCentralHubProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyCentralHubProfile);
    if (value == null) {
      // Check if one is in backend profiles list
      final profiles = await loadBackendProfiles();
      return profiles.where((p) => p.isHub).firstOrNull;
    }
    try {
      return BackendProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCentralHubProfile(BackendProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = profile.copyWith(type: BackendProfileType.centralHub);
    await prefs.setString(_keyCentralHubProfile, jsonEncode(updated.toJson()));
    await saveBackendProfile(updated);
  }

  static Future<void> deleteCentralHubProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCentralHubProfile);
    final profiles = await loadBackendProfiles();
    final hubProfiles = profiles.where((p) => p.isHub).toList();
    for (final hub in hubProfiles) {
      await deleteBackendProfile(hub.id);
    }
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

  // --- Recent Projects ---

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
    current.removeWhere((p) => p.path == project.path);
    current.insert(0, project);
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

  // --- General Chat Persistence ---

  static Future<List<ConversationSession>> loadGeneralConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyGeneralConversations);
    if (jsonStr != null) {
      try {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        final convs = list
            .map((e) => ConversationSession.fromJson(e as Map<String, dynamic>))
            .toList();
        convs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return convs;
      } catch (_) {}
    }
    return [];
  }

  static Future<void> saveGeneralConversation(
    ConversationSession session,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadGeneralConversations();
    final idx = list.indexWhere((c) => c.id == session.id);

    if (idx >= 0) {
      list[idx] = session;
    } else {
      list.insert(0, session);
    }

    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    await prefs.setString(
      _keyGeneralConversations,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> deleteGeneralConversation(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadGeneralConversations();
    list.removeWhere((c) => c.id == conversationId);

    await prefs.setString(
      _keyGeneralConversations,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );

    final activeId = await loadActiveGeneralConversationId();
    if (activeId == conversationId) {
      await prefs.remove(_keyActiveGeneralConv);
    }
  }

  static Future<String?> loadActiveGeneralConversationId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActiveGeneralConv);
  }

  static Future<void> saveActiveGeneralConversationId(
    String conversationId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveGeneralConv, conversationId);
  }

  static Future<bool> loadGeneralChatWebSearchEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyGeneralWebSearch) ?? false;
  }

  static Future<void> saveGeneralChatWebSearchEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGeneralWebSearch, enabled);
  }

  static Future<String> loadSearxngUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('wfp_searxng_url') ?? '';
  }

  static Future<void> saveSearxngUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wfp_searxng_url', url.trim());
  }
}
