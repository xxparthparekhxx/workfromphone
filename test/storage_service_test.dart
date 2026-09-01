import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/services/storage_service.dart';

class _FailingSecureStorage extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => false;

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => null;

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) {
    throw Exception('secure storage unavailable');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
  });

  test('deleting a backend profile also removes stored secrets', () async {
    const profile = BackendProfile(
      id: 'profile-1',
      name: 'Box',
      host: 'example.com',
      sshPort: 22,
      username: 'dev',
      transport: BackendTransport.sshTunnel,
      hostKeyType: 'ssh-ed25519',
      hostKeyFingerprint: 'SHA256:test',
      architecture: 'x86_64',
      installedVersion: '1.0.0',
    );

    await StorageService.saveBackendProfile(profile);
    await StorageService.saveBackendSecret(profile.id, 'access_token', 'tok');
    await StorageService.saveBackendSecret(profile.id, 'ssh_password', 'pw');

    expect(
      await StorageService.loadBackendSecret(profile.id, 'access_token'),
      'tok',
    );
    expect(
      await StorageService.loadBackendSecret(profile.id, 'ssh_password'),
      'pw',
    );

    await StorageService.deleteBackendProfile(profile.id);

    expect(await StorageService.loadBackendProfiles(), isEmpty);
    expect(
      await StorageService.loadBackendSecret(profile.id, 'access_token'),
      isNull,
    );
    expect(
      await StorageService.loadBackendSecret(profile.id, 'ssh_password'),
      isNull,
    );
  });

  test(
    'LLM API key falls back to prefs when secure storage is unavailable',
    () async {
      FlutterSecureStoragePlatform.instance = _FailingSecureStorage();

      await StorageService.saveLLMConfig(
        const LLMConfig(
          apiKey: 'sk-or-persisted-key',
          model: 'openai/gpt-4o',
          backendAccessToken: 'backend-token',
        ),
      );

      expect(StorageService.secretsPersistFailed, isTrue);

      final loaded = await StorageService.loadLLMConfig();
      expect(loaded.apiKey, 'sk-or-persisted-key');
      expect(loaded.backendAccessToken, 'backend-token');
      expect(loaded.model, 'openai/gpt-4o');
    },
  );
}
