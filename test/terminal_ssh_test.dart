import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfromphone/models/project_directory.dart';
import 'package:workfromphone/screens/terminal/project_terminal_tab.dart';
import 'package:workfromphone/utils/ansi_parser.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('AnsiParser decodes ANSI color codes and resets correctly', () {
    const rawAnsi = '\x1B[32mSuccess\x1B[0m and \x1B[31mError\x1B[0m';
    final spans = AnsiParser.parse(rawAnsi);

    expect(spans.length, greaterThanOrEqualTo(3));
    expect(spans[0].text, 'Success');
    expect(spans[0].style?.color, const Color(0xFF9ECE6A)); // Green
    expect(spans[2].text, 'Error');
    expect(spans[2].style?.color, const Color(0xFFF7768E)); // Red
  });

  testWidgets('ProjectTerminalTab renders tabbed PTY controls', (
    WidgetTester tester,
  ) async {
    final project = ProjectDirectory(
      name: 'my_flutter_app',
      path: '/home/user/my_flutter_app',
      lastOpened: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectTerminalTab(
            project: project,
            backendUrl: 'http://127.0.0.1:8000',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TerminalView), findsOneWidget);
    expect(find.byKey(const Key('terminal-tab-bar')), findsOneWidget);
    expect(find.byKey(const Key('terminal-tab-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-add-tab')), findsOneWidget);
    expect(find.byKey(const Key('terminal-zoom-in')), findsOneWidget);
    expect(find.byKey(const Key('terminal-zoom-out')), findsOneWidget);
    expect(find.byKey(const Key('terminal-fullscreen')), findsOneWidget);
    expect(find.byKey(const Key('terminal-accessory-bar')), findsOneWidget);

    expect(find.text('ESC'), findsOneWidget);
    expect(find.text('TAB'), findsOneWidget);
    expect(find.text('CTRL'), findsOneWidget);
    expect(find.text('↑'), findsOneWidget);
    expect(find.text('↓'), findsOneWidget);
    expect(find.text('←'), findsOneWidget);
    expect(find.text('→'), findsOneWidget);
    expect(find.text('|'), findsOneWidget);
    expect(find.text('~'), findsOneWidget);

    expect(find.textContaining('SSH: 127.0.0.1'), findsNothing);
    expect(find.textContaining('WorkFromPhone SSH Engine'), findsNothing);
    expect(find.textContaining('user@wfp:'), findsNothing);
  });

  testWidgets('terminal tabs add, switch, close, and replace the last tab', (
    WidgetTester tester,
  ) async {
    final project = ProjectDirectory(
      name: 'my_flutter_app',
      path: '/home/user/my_flutter_app',
      lastOpened: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectTerminalTab(
            project: project,
            backendUrl: 'http://127.0.0.1:8000',
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('terminal-add-tab')));
    await tester.pump();
    expect(find.byKey(const Key('terminal-tab-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-tab-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('terminal-tab-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('terminal-close-2')));
    await tester.pump();
    expect(find.byKey(const Key('terminal-tab-2')), findsNothing);
    expect(find.byKey(const Key('terminal-tab-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('terminal-close-1')));
    await tester.pump();
    expect(find.byKey(const Key('terminal-tab-1')), findsNothing);
    expect(find.byKey(const Key('terminal-tab-3')), findsOneWidget);
    expect(find.byType(TerminalView), findsOneWidget);
  });

  testWidgets('terminal zoom is bounded and fullscreen preserves one surface', (
    WidgetTester tester,
  ) async {
    final project = ProjectDirectory(
      name: 'my_flutter_app',
      path: '/home/user/my_flutter_app',
      lastOpened: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectTerminalTab(
            project: project,
            backendUrl: 'http://127.0.0.1:8000',
          ),
        ),
      ),
    );
    await tester.pump();

    TerminalView view = tester.widget(find.byType(TerminalView));
    expect(view.textStyle.fontSize, 13);

    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byKey(const Key('terminal-zoom-in')));
      await tester.pump();
    }
    view = tester.widget(find.byType(TerminalView));
    expect(view.textStyle.fontSize, 22);

    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byKey(const Key('terminal-zoom-out')));
      await tester.pump();
    }
    view = tester.widget(find.byType(TerminalView));
    expect(view.textStyle.fontSize, 9);

    final center = tester.getCenter(find.byType(TerminalView));
    final firstFinger = await tester.createGesture(pointer: 1);
    final secondFinger = await tester.createGesture(pointer: 2);
    await firstFinger.down(center - const Offset(25, 0));
    await secondFinger.down(center + const Offset(25, 0));
    await firstFinger.moveTo(center - const Offset(45, 0));
    await secondFinger.moveTo(center + const Offset(45, 0));
    await tester.pump();
    await firstFinger.up();
    await secondFinger.up();
    view = tester.widget(find.byType(TerminalView));
    expect(view.textStyle.fontSize, greaterThan(9));

    await tester.tap(find.byTooltip('Collapse terminal keys'));
    await tester.pump();
    expect(
      find.byKey(const Key('terminal-accessory-collapsed')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('terminal-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terminal-fullscreen-bar')), findsOneWidget);
    expect(find.byType(TerminalView), findsOneWidget);

    await tester.tap(find.byKey(const Key('terminal-fullscreen-exit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terminal-fullscreen-bar')), findsNothing);
    expect(find.byType(TerminalView), findsOneWidget);
  });
}
