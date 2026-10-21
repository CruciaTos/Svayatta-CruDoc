import 'dart:io';

import 'package:crudoc_shared/theme/cru_theme.dart';
import 'package:doctor_management_app/core/services/local_storage_manager.dart';
import 'package:doctor_management_app/features/settings/presentation/storage_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('crudoc_storage_ui');
    // 1.2 MB on this "device", over a limit we set below.
    File('${root.path}/db').writeAsBytesSync(List.filled(1200 * 1024, 0));
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester, ThemeData theme, double width,
      {int limit = 0}) async {
    SharedPreferences.setMockInitialValues({
      'crudoc.localStorageLimitBytes': limit,
    });
    final manager = LocalStorageManager.forTesting(
      prefs: SharedPreferences.getInstance,
      appDir: () async => root,
      cloudSize: (_) async => null,
    );
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StorageSection(manager: manager),
          ),
        ),
      ),
    );
    // Reading the folder is real file I/O, outside the fake clock: let it
    // run until the numbers are in.
    for (var i = 0; i < 50 && find.text('Adding up…').evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Adding up…'), findsNothing);
  }

  for (final (name, theme) in [
    ('day', CruTheme.day()),
    ('evening', CruTheme.evening()),
  ]) {
    testWidgets('lays out on a phone and a desktop ($name)', (tester) async {
      for (final width in [360.0, 900.0]) {
        await pump(tester, theme, width);
        expect(tester.takeException(), isNull, reason: 'at $width');
        expect(find.text('Storage on this device'), findsOneWidget);
        expect(find.text('No limit'), findsWidgets);
        expect(find.text('No limit set: nothing is removed.'), findsOneWidget);
      }
    });
  }

  testWidgets('shows usage against the limit', (tester) async {
    await pump(tester, CruTheme.day(), 900, limit: 500 * 1024 * 1024);
    // 500 MB is the smallest stop, so 1.2 MB is within it.
    expect(find.text('Within the limit.'), findsOneWidget);
    expect(find.text('500 MB'), findsWidgets);
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(500 * 1024 * 1024), '500 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3 GB');
    expect(formatBytes(1288490188), '1.2 GB');
  });
}
