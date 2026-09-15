import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/screens/settings/on_device_setup_screen.dart';
import 'package:workfromphone/services/api_service.dart';
import 'package:workfromphone/services/local_container_service.dart';
import 'package:workfromphone/services/storage_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
  });

  test('release architecture maps device ABI to manifest naming', () {
    expect(LocalContainerService.releaseArchitecture('arm64-v8a'), 'aarch64');
    expect(LocalContainerService.releaseArchitecture('aarch64'), 'aarch64');
    expect(LocalContainerService.releaseArchitecture('x86_64'), 'x86_64');
    expect(LocalContainerService.releaseArchitecture('unknown'), 'x86_64');
  });

  test('local URL always targets loopback', () {
    expect(LocalContainerService.localUrl(8000), 'http://127.0.0.1:8000');
    expect(LocalContainerService.localUrl(18765), 'http://127.0.0.1:18765');
  });

  test('on-device status distinguishes missing proot runtime libs', () {
    final incomplete = OnDeviceStatus.fromMap({
      'prootFound': true,
      'prootRuntimeReady': false,
    });
    expect(incomplete.prootFound, isTrue);
    expect(incomplete.prootRuntimeReady, isFalse);

    final ready = OnDeviceStatus.fromMap({'prootFound': true});
    expect(ready.prootRuntimeReady, isTrue);
  });

  test('saving the on-device profile pins directHttp loopback', () async {
    final profile = await LocalContainerService.saveAsActiveProfile(
      port: 8000,
      rootfsVersion: 'test-version',
      architecture: 'aarch64',
    );

    expect(profile.id, LocalContainerService.profileId);
    expect(profile.transport, BackendTransport.directHttp);
    expect(profile.backendUrl, 'http://127.0.0.1:8000');

    final stored = await StorageService.loadBackendSecret(
      LocalContainerService.profileId,
      'access_token',
    );
    expect(stored, isNotNull);
    expect(stored, isNotEmpty);

    // The token is scoped to the loopback origin only.
    ApiService.configureAccessToken(
      stored!,
      backendUrl: 'http://127.0.0.1:8000',
    );
    final headers = ApiService.headers(
      uri: Uri.parse('http://127.0.0.1:8000/api/v1/system/snapshot'),
    );
    expect(headers['Authorization'], 'Bearer $stored');
    final foreign = ApiService.headers(
      uri: Uri.parse('http://192.168.1.10:8000/api/v1/system/snapshot'),
    );
    expect(foreign.containsKey('Authorization'), isFalse);
  });

  testWidgets('setup wizard explains unsupported platforms', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnDeviceSetupScreen()));
    await tester.pumpAndSettle();

    // The test VM is not Android, so the wizard reports that directly.
    expect(find.textContaining('needs the Android app'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
