import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfromphone/models/model_info.dart';
import 'package:workfromphone/widgets/model_picker_sheet.dart';

void main() {
  const testModels = [
    ModelInfo(
      id: 'anthropic/claude-3.5-sonnet',
      name: 'Claude 3.5 Sonnet',
      description: 'Flagship Anthropic model',
      contextLength: 200000,
    ),
    ModelInfo(
      id: 'anthropic/claude-3.7-sonnet',
      name: 'Claude 3.7 Sonnet',
      description: 'Hybrid reasoning Anthropic model',
      contextLength: 200000,
    ),
    ModelInfo(
      id: 'meta-llama/llama-3.3-70b-instruct:free',
      name: 'Llama 3.3 70B (Free)',
      description: 'Free Meta model',
      contextLength: 131072,
    ),
    ModelInfo(
      id: 'openai/gpt-4o',
      name: 'GPT-4o',
      description: 'OpenAI model',
      contextLength: 128000,
    ),
    ModelInfo(
      id: 'deepseek/deepseek-r1:free',
      name: 'DeepSeek R1 (Free)',
      description: 'Free DeepSeek model',
      contextLength: 64000,
    ),
  ];

  testWidgets('ModelPickerSheet displays models and allows selection', (WidgetTester tester) async {
    ModelInfo? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelPickerSheet(
            selectedModelId: 'anthropic/claude-3.5-sonnet',
            availableModels: testModels,
            onModelSelected: (m) {
              selected = m;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select Active Model'), findsOneWidget);
    expect(find.text('Claude 3.5 Sonnet'), findsOneWidget);
    expect(find.text('Claude 3.7 Sonnet'), findsOneWidget);

    // Tap on Claude 3.7 Sonnet
    await tester.tap(find.text('Claude 3.7 Sonnet'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.id, 'anthropic/claude-3.7-sonnet');
  });

  testWidgets('ModelPickerSheet searches models by text', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelPickerSheet(
            selectedModelId: 'anthropic/claude-3.5-sonnet',
            availableModels: testModels,
            onModelSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'Claude');
    await tester.pumpAndSettle();

    expect(find.text('Claude 3.5 Sonnet'), findsOneWidget);
    expect(find.text('Claude 3.7 Sonnet'), findsOneWidget);
    expect(find.text('GPT-4o'), findsNothing);
  });

  testWidgets('ModelPickerSheet filters by Free models chip', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelPickerSheet(
            selectedModelId: 'anthropic/claude-3.5-sonnet',
            availableModels: testModels,
            onModelSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find and tap Free Models filter chip
    final freeChip = find.widgetWithText(FilterChip, 'Free Models (2)');
    expect(freeChip, findsOneWidget);
    await tester.tap(freeChip);
    await tester.pumpAndSettle();

    // Only free models should appear
    expect(find.text('Llama 3.3 70B (Free)'), findsOneWidget);
    expect(find.text('DeepSeek R1 (Free)'), findsOneWidget);
    expect(find.text('Claude 3.5 Sonnet'), findsNothing);
    expect(find.text('GPT-4o'), findsNothing);
  });

  testWidgets('ModelPickerSheet filters by Anthropic chip', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelPickerSheet(
            selectedModelId: 'anthropic/claude-3.5-sonnet',
            availableModels: testModels,
            onModelSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find and tap Anthropic filter chip
    final anthropicChip = find.widgetWithText(FilterChip, 'Anthropic (2)');
    expect(anthropicChip, findsOneWidget);
    await tester.tap(anthropicChip);
    await tester.pumpAndSettle();

    // Only Anthropic models should appear
    expect(find.text('Claude 3.5 Sonnet'), findsOneWidget);
    expect(find.text('Claude 3.7 Sonnet'), findsOneWidget);
    expect(find.text('Llama 3.3 70B (Free)'), findsNothing);
    expect(find.text('GPT-4o'), findsNothing);
  });
}
