// Golden images of the dashboard next to design/dashboard-redesign/screens.
//
// Rendered at 1.5x so each golden has the same pixel size as the design
// mock-up (1440x1148 -> 2160x1722 Day, 1440x988 -> 2160x1482 Evening).
// Uses fake providers (test/dashboard/dashboard_fixtures.dart) and the
// bundled Geist font. Regenerate with:
//   flutter test --update-goldens --tags golden
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dashboard_fixtures.dart';
import 'dashboard_harness.dart';

Future<void> _render(
  WidgetTester tester, {
  required bool evening,
  required Size logical,
}) async {
  tester.view.devicePixelRatio = 1.5;
  tester.view.physicalSize = logical * 1.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(dashboardApp(evening: evening));
  await tester.pump(); // stream providers deliver
  await tester.pump(const Duration(milliseconds: 400)); // settle animations
}

void main() {
  setUpAll(loadGeist);

  testWidgets('Day, 1440 x 1148', (tester) async {
    await _render(tester, evening: false, logical: const Size(1440, 1148));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dashboard_day.png'),
    );
  });

  testWidgets('Evening, 1440 x 988', (tester) async {
    await _render(tester, evening: true, logical: const Size(1440, 988));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dashboard_evening.png'),
    );
  });
}
