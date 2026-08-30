import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfromphone/utils/material_icon_theme.dart';
import 'package:workfromphone/widgets/material_file_icon.dart';

void main() {
  testWidgets(
    'MaterialFileIcon renders proper file and folder icons and badges',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MaterialFileIcon(name: 'main.dart'),
                MaterialFileIcon(name: 'server.py'),
                MaterialFileIcon(name: 'index.ts'),
                MaterialFileIcon(name: 'pubspec.yaml'),
                MaterialFileIcon(name: 'package.json'),
                MaterialFileIcon(name: 'README.md'),
                MaterialFileIcon(name: 'Dockerfile'),
                MaterialFileIcon(name: 'lib', isDir: true),
                MaterialFileIcon(name: 'test', isDir: true),
                MaterialFileIcon(name: 'assets', isDir: true),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify icons are present
      expect(find.byType(MaterialFileIcon), findsNWidgets(10));
      // Verify badges (e.g. PY, TS, FL, JS)
      expect(find.text('PY'), findsOneWidget);
      expect(find.text('TS'), findsOneWidget);
      expect(find.text('FL'), findsOneWidget);
      expect(find.text('JS'), findsOneWidget);
    },
  );

  test('MaterialIconTheme resolves specific folder and file icons', () {
    final libFolder = MaterialIconTheme.getFolderIcon('lib');
    expect(libFolder.color, const Color(0xFF5DADE2));

    final testFolder = MaterialIconTheme.getFolderIcon('test');
    expect(testFolder.color, const Color(0xFF52BE80));

    final dartFile = MaterialIconTheme.getFileIcon('main.dart');
    expect(dartFile.icon, Icons.flutter_dash);

    final pyFile = MaterialIconTheme.getFileIcon('test.py');
    expect(pyFile.badgeText, 'PY');

    final jsonFile = MaterialIconTheme.getFileIcon('data.json');
    expect(jsonFile.icon, Icons.data_object);
  });
}
