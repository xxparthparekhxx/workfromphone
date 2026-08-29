import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/models/project_directory.dart';

class StorageService {
  static const _keyLLMConfig = 'wfp_llm_config';
  static const _keyRecentProjects = 'wfp_recent_projects';

  static Future<LLMConfig> loadLLMConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyLLMConfig);
    if (jsonStr != null) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return LLMConfig.fromJson(map);
      } catch (_) {}
    }
    return const LLMConfig();
  }

  static Future<void> saveLLMConfig(LLMConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final map = config.toJson();
    map['backend_url'] = config.backendUrl;
    await prefs.setString(_keyLLMConfig, jsonEncode(map));
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
}
