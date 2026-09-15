import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/remote_setup_service.dart';
import 'package:workfromphone/services/storage_service.dart';

/// Status snapshot reported by the native `wfp/container` channel.
class OnDeviceStatus {
  final bool installed;
  final String? version;
  final bool running;
  final int port;
  final bool healthy;
  final bool prootFound;
  final String workspace;
  final String abi;

  const OnDeviceStatus({
    required this.installed,
    required this.version,
    required this.running,
    required this.port,
    required this.healthy,
    required this.prootFound,
    required this.workspace,
    required this.abi,
  });

  factory OnDeviceStatus.fromMap(Map<dynamic, dynamic> map) {
    return OnDeviceStatus(
      installed: map['installed'] as bool? ?? false,
      version: map['version'] as String?,
      running: map['running'] as bool? ?? false,
      port: (map['port'] as num?)?.toInt() ?? 8000,
      healthy: map['healthy'] as bool? ?? false,
      prootFound: map['prootFound'] as bool? ?? false,
      workspace: map['workspace'] as String? ?? '',
      abi: map['abi'] as String? ?? 'unknown',
    );
  }
}

/// Rootfs release artifact resolved from `rootfs-manifest.json`.
class RootfsRelease {
  final String version;
  final String url;
  final String sha256;

  const RootfsRelease({
    required this.version,
    required this.url,
    required this.sha256,
  });
}

/// Result of the two-stage connection test: public `/health`, then the
/// authenticated `/system/snapshot` (proves ACCESS_TOKEN works on loopback).
class OnDeviceTestResult {
  final bool healthOk;
  final bool authOk;
  final String detail;

  const OnDeviceTestResult({
    required this.healthOk,
    required this.authOk,
    required this.detail,
  });

  bool get passed => healthOk && authOk;
}

/// Dart facade over the native on-device Debian container.
///
/// The container runs the FastAPI backend under proot and serves
/// `http://127.0.0.1:<port>`. ACCESS_TOKEN stays mandatory even on
/// loopback (any on-device app can reach localhost) and is kept only in
/// [StorageService] secure storage, scoped to the local URL.
class LocalContainerService {
  static const MethodChannel _channel = MethodChannel('wfp/container');
  static const EventChannel _progress = EventChannel('wfp/container_progress');

  static const String profileId = 'ondevice_local';
  static const int defaultPort = 8000;

  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static Future<OnDeviceStatus> getStatus() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getStatus');
    return OnDeviceStatus.fromMap(raw ?? {});
  }

  static Stream<Map<dynamic, dynamic>> progressStream() {
    return _progress.receiveBroadcastStream().map(
      (event) => Map<dynamic, dynamic>.from(event as Map),
    );
  }

  static Future<void> beginSetup({
    required String url,
    required String sha256,
    required String version,
  }) async {
    await _channel.invokeMethod('beginSetup', {
      'url': url,
      'sha256': sha256,
      'version': version,
    });
  }

  static Future<void> start({
    required String accessToken,
    int port = defaultPort,
    String? workspacePath,
  }) async {
    await _channel.invokeMethod('start', {
      'accessToken': accessToken,
      'port': port,
      if (workspacePath != null && workspacePath.isNotEmpty)
        'workspacePath': workspacePath,
    });
  }

  static Future<void> stop() async {
    await _channel.invokeMethod('stop');
  }

  static Future<bool> isBatteryExemptionGranted() async {
    final granted = await _channel.invokeMethod<bool>(
      'isBatteryExemptionGranted',
    );
    return granted ?? true;
  }

  static Future<void> requestBatteryExemption() async {
    await _channel.invokeMethod('requestBatteryExemption');
  }

  /// Maps the device ABI to the release-arch naming used by manifests.
  static String releaseArchitecture(String abi) {
    final normalized = abi.toLowerCase();
    if (normalized.contains('arm64') || normalized.contains('aarch64')) {
      return 'aarch64';
    }
    return 'x86_64';
  }

  /// Resolves the rootfs download for this device from the release manifest.
  static Future<RootfsRelease> fetchRootfsRelease(String architecture) async {
    final repo = RemoteSetupService.releaseRepository.trim();
    if (repo.isEmpty) {
      throw const FormatException(
        'No release repository is configured. Build the app with '
        '--dart-define=WFP_BACKEND_RELEASE_REPO=owner/repository.',
      );
    }
    final uri = Uri.parse(
      'https://github.com/$repo/releases/latest/download/rootfs-manifest.json',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException(
        'Could not download rootfs manifest (HTTP ${response.statusCode}).',
      );
    }
    final manifest = jsonDecode(response.body) as Map<String, dynamic>;
    final artifacts = manifest['artifacts'] as Map<String, dynamic>? ?? {};
    final artifact = artifacts[architecture] as Map<String, dynamic>?;
    if (artifact == null) {
      throw FormatException(
        'On-device rootfs does not support $architecture yet.',
      );
    }
    final url = artifact['url'] as String? ?? '';
    final sha256 = artifact['sha256'] as String? ?? '';
    if (url.isEmpty || sha256.length != 64) {
      throw const FormatException('Rootfs release manifest is invalid.');
    }
    return RootfsRelease(
      version: manifest['version'] as String? ?? 'unknown',
      url: url,
      sha256: sha256,
    );
  }

  /// Returns the stored on-device token, generating and persisting one on
  /// first use. The token is scoped to the local backend URL only.
  static Future<String> ensureAccessToken() async {
    final existing = await StorageService.loadBackendSecret(
      profileId,
      'access_token',
    );
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    await StorageService.saveBackendSecret(profileId, 'access_token', token);
    return token;
  }

  static String localUrl(int port) => 'http://127.0.0.1:$port';

  /// Two-stage test: public `/health`, then authed `/system/snapshot`.
  static Future<OnDeviceTestResult> testConnection({
    required String baseUrl,
    required String token,
  }) async {
    final base = ApiService.cleanUrl(baseUrl);
    try {
      final health = await http
          .get(Uri.parse('$base/api/v1/health'))
          .timeout(const Duration(seconds: 5));
      if (health.statusCode != 200) {
        return OnDeviceTestResult(
          healthOk: false,
          authOk: false,
          detail: 'Backend answered HTTP ${health.statusCode} on /health.',
        );
      }
    } catch (e) {
      return OnDeviceTestResult(
        healthOk: false,
        authOk: false,
        detail: 'Backend is unreachable at $base ($e).',
      );
    }
    try {
      final snapshot = await http
          .get(
            Uri.parse('$base/api/v1/system/snapshot'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));
      if (snapshot.statusCode == 200) {
        return const OnDeviceTestResult(
          healthOk: true,
          authOk: true,
          detail: 'Connected: public health OK, token-auth snapshot OK.',
        );
      }
      return OnDeviceTestResult(
        healthOk: true,
        authOk: false,
        detail:
            'Backend is up but rejected the token (HTTP ${snapshot.statusCode}). Restart the container.',
      );
    } catch (e) {
      return OnDeviceTestResult(
        healthOk: true,
        authOk: false,
        detail: 'Authenticated snapshot failed ($e).',
      );
    }
  }

  /// Saves the on-device backend as the active `directHttp` profile and
  /// points the app at it. The token is never forwarded to any other host:
  /// [ApiService] scopes it to this origin.
  static Future<BackendProfile> saveAsActiveProfile({
    required int port,
    required String rootfsVersion,
    required String architecture,
  }) async {
    final token = await ensureAccessToken();
    final profile = BackendProfile(
      id: profileId,
      name: 'On-device container',
      host: '127.0.0.1',
      sshPort: 22,
      username: 'coder',
      transport: BackendTransport.directHttp,
      directUrl: localUrl(port),
      hostKeyType: '',
      hostKeyFingerprint: '',
      architecture: architecture,
      installedVersion: rootfsVersion,
    );
    await StorageService.saveBackendProfile(profile);
    await StorageService.saveBackendSecret(profileId, 'access_token', token);
    final current = await StorageService.loadLLMConfig();
    await StorageService.saveLLMConfig(
      current.copyWith(
        backendUrl: profile.backendUrl,
        backendAccessToken: token,
      ),
    );
    ApiService.configureAccessToken(token, backendUrl: profile.backendUrl);
    return profile;
  }
}
