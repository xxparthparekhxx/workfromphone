import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/screens/settings/remote_backend_setup_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('backend profile serialization preserves trusted host identity', () {
    const profile = BackendProfile(
      id: 'host-id',
      name: 'Build server',
      host: '10.0.0.8',
      sshPort: 2222,
      username: 'developer',
      transport: BackendTransport.cloudflareTunnel,
      hostKeyType: 'ssh-ed25519',
      hostKeyFingerprint: 'SHA256:trusted',
      cloudflareHostname: 'dev.example.com',
      architecture: 'aarch64',
      installedVersion: '1.2.3',
      rememberPassword: true,
    );

    final restored = BackendProfile.fromJson(profile.toJson());
    expect(restored.hostKeyFingerprint, 'SHA256:trusted');
    expect(restored.transport, BackendTransport.cloudflareTunnel);
    expect(restored.backendUrl, 'https://dev.example.com');
    expect(restored.rememberPassword, isTrue);
  });

  testWidgets('remote setup offers SSH and named Cloudflare tunnel modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RemoteBackendSetupScreen()),
    );

    expect(find.byKey(const Key('remote-host-field')), findsOneWidget);
    expect(find.byKey(const Key('remote-user-field')), findsOneWidget);
    expect(find.byKey(const Key('remote-password-field')), findsOneWidget);
    expect(find.text('SSH tunnel'), findsOneWidget);
    expect(find.text('Cloudflare'), findsOneWidget);
    expect(find.byKey(const Key('cloudflare-token-field')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('remote-host-field')),
      '192.168.1.20',
    );
    await tester.ensureVisible(find.text('Cloudflare'));
    await tester.tap(find.text('Cloudflare'));
    await tester.pump();

    expect(find.byKey(const Key('cloudflare-hostname-field')), findsOneWidget);
    expect(find.byKey(const Key('cloudflare-token-field')), findsOneWidget);
    expect(find.textContaining('Private address detected'), findsOneWidget);
  });
}
