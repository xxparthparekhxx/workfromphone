import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/screens/settings/settings_screen.dart';
import 'package:workfromphone/services/storage_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
  });

  testWidgets(
    'SettingsScreen renders and saves backend access token input field',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();

      final tokenFieldFinder = find.byKey(
        const Key('backend-access-token-field'),
      );
      expect(tokenFieldFinder, findsOneWidget);

      await tester.enterText(tokenFieldFinder, 'my-secret-access-token');
      await tester.pump();

      await tester.tap(find.byTooltip('Save Settings'));
      await tester.pumpAndSettle();

      final config = await StorageService.loadLLMConfig();
      expect(config.backendAccessToken, 'my-secret-access-token');
    },
  );
}
