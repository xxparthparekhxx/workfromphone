import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfromphone/models/task_stats.dart';
import 'package:workfromphone/widgets/task_stats_bar.dart';

void main() {
  testWidgets('TaskStatsBar displays TPS, context ratio, and tools correctly', (WidgetTester tester) async {
    const stats = TaskStats(
      totalTokens: 12450,
      promptTokens: 8000,
      completionTokens: 4450,
      tokensPerSecond: 42.5,
      durationMs: 3400,
      contextLimit: 200000,
      toolCallsCount: 3,
      isStreaming: true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TaskStatsBar(stats: stats),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('42.5 tps'), findsOneWidget);
    expect(find.text('12.4k / 200k (6.2%)'), findsOneWidget);
    expect(find.text('🛠️ 3'), findsOneWidget);
    expect(find.text('3.4s'), findsOneWidget);
  });
}
