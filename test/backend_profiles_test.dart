import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/models/backend_profile.dart';
import 'package:workfromphone/services/storage_service.dart';
import 'package:workfromphone/widgets/add_edit_backend_dialog.dart';
import 'package:workfromphone/widgets/server_picker_sheet.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AddEditBackendDialog adds a new direct HTTP backend server', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AddEditBackendDialog())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add Backend Server'), findsOneWidget);
    expect(find.text('Server Friendly Name'), findsOneWidget);
    expect(find.text('Backend URL'), findsOneWidget);

    // Enter name & URL
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Server Friendly Name'),
      'My Cloud VPS',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Backend URL'),
      'http://192.168.1.150:8000',
    );

    // Tap Save
    await tester.tap(find.text('Add Server'));
    await tester.pumpAndSettle();

    final profiles = await StorageService.loadBackendProfiles();
    expect(profiles.length, 1);
    expect(profiles.first.name, 'My Cloud VPS');
    expect(profiles.first.backendUrl, 'http://192.168.1.150:8000');

    final activeProfile = await StorageService.loadActiveBackendProfile();
    expect(activeProfile?.id, profiles.first.id);

    final config = await StorageService.loadLLMConfig();
    expect(config.backendUrl, 'http://192.168.1.150:8000');
  });

  testWidgets('ServerPickerSheet lists multiple servers and allows switching', (
    WidgetTester tester,
  ) async {
    const p1 = BackendProfile(
      id: 'srv_1',
      name: 'Home Linux PC',
      host: 'http://192.168.1.10:8000',
      sshPort: 22,
      username: 'user',
      transport: BackendTransport.directHttp,
      directUrl: 'http://192.168.1.10:8000',
      hostKeyType: '',
      hostKeyFingerprint: '',
      architecture: 'x86_64',
      installedVersion: '1.0.0',
    );
    const p2 = BackendProfile(
      id: 'srv_2',
      name: 'Work Laptop',
      host: 'http://192.168.1.20:8000',
      sshPort: 22,
      username: 'user',
      transport: BackendTransport.directHttp,
      directUrl: 'http://192.168.1.20:8000',
      hostKeyType: '',
      hostKeyFingerprint: '',
      architecture: 'x86_64',
      installedVersion: '1.0.0',
    );

    await StorageService.saveBackendProfile(p1);
    await StorageService.saveBackendProfile(p2);
    await StorageService.setActiveBackendProfile(p1.id);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ServerPickerSheet())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backend Servers'), findsOneWidget);
    expect(find.text('Home Linux PC'), findsOneWidget);
    expect(find.text('Work Laptop'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);

    // Tap on Work Laptop to switch
    await tester.tap(find.text('Work Laptop'));
    await tester.pumpAndSettle();

    final active = await StorageService.loadActiveBackendProfile();
    expect(active?.id, 'srv_2');
    expect(active?.name, 'Work Laptop');

    final config = await StorageService.loadLLMConfig();
    expect(config.backendUrl, 'http://192.168.1.20:8000');
  });
}
