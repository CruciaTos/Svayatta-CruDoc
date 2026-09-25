// Golden image of the Revenue Overview next to
// design/clinic-redesign/screens/revenue.png.
//
// Rendered at 1.5x so the golden has the mock-up's pixel size
// (1440x1088 -> 2160x1632). Uses fake providers
// (test/revenue/revenue_fixtures.dart) and the bundled Geist font.
// Regenerate with:
//   flutter test --update-goldens --tags golden test/revenue
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../patients/patients_fixtures.dart' show loadGeist;
import 'revenue_harness.dart';

void main() {
  setUpAll(loadGeist);

  testWidgets('Revenue Overview, Month, 1440 x 1088', (tester) async {
    setViewSize(tester, const Size(1440, 1088), dpr: 1.5);
    await tester.pumpWidget(revenueApp());
    await settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/revenue.png'),
    );
  });
}
