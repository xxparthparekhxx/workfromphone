import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/screens/chat/general_chat_screen.dart';
import 'package:workfromphone/services/storage_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
  });

  testWidgets(
    'GeneralChatScreen renders controls, model selector, and toggles web search',
    (WidgetTester tester) async {
      await StorageService.saveLLMConfig(
        const LLMConfig(apiKey: 'sk-or-test-key', model: 'openai/gpt-4o'),
      );

      await tester.pumpWidget(const MaterialApp(home: GeneralChatScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Ask anything'), findsWidgets);
      expect(
        find.byKey(const Key('general-chat-model-picker')),
        findsOneWidget,
      );
      final webSearchChip = find.byKey(
        const Key('general-chat-web-search-chip'),
      );
      expect(webSearchChip, findsOneWidget);
      expect(find.byKey(const Key('general-chat-input')), findsOneWidget);
      expect(find.byKey(const Key('general-chat-send-button')), findsOneWidget);

      // Verify default web search state is OFF
      expect(tester.widget<FilterChip>(webSearchChip).selected, isFalse);

      // Tap Web Search chip to toggle ON
      await tester.tap(webSearchChip);
      await tester.pump();

      expect(tester.widget<FilterChip>(webSearchChip).selected, isTrue);
      final isSaved = await StorageService.loadGeneralChatWebSearchEnabled();
      expect(isSaved, isTrue);

      // Tap again to toggle OFF
      await tester.tap(webSearchChip);
      await tester.pump();
      expect(tester.widget<FilterChip>(webSearchChip).selected, isFalse);
    },
  );

  testWidgets(
    'GeneralChatScreen picks up an OpenRouter key saved after the screen loaded',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: GeneralChatScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('general-chat-input')),
        'hello',
      );
      await tester.tap(find.byKey(const Key('general-chat-send-button')));
      await tester.pump();

      expect(
        find.text('Please configure your Router API Key in Settings first.'),
        findsOneWidget,
      );
      expect(find.text('hello'), findsOneWidget);

      await StorageService.saveLLMConfig(
        const LLMConfig(apiKey: 'sk-or-test-key', model: 'openai/gpt-4o'),
      );

      await tester.enterText(
        find.byKey(const Key('general-chat-input')),
        'hello again',
      );
      await tester.tap(find.byKey(const Key('general-chat-send-button')));
      await tester.pump();

      expect(find.text('hello again'), findsWidgets);
      // The empty state (with its prompt suggestions) is gone once a message
      // has been sent.
      expect(find.text('Ask anything'), findsNothing);
    },
  );
}
