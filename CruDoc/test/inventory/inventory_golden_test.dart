// Golden images of Inventory next to design/clinic-redesign/screens.
//
// Rendered at 1.5x so each golden has the same pixel size as the design
// mock-up (1440x1030 list, 1440x946 grid). Uses fake providers
// (inventory_fixtures.dart) and the bundled Geist font. Regenerate with:
//   flutter test --update-goldens --tags golden test/inventory
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../patients/patients_fixtures.dart' show loadGeist;
import 'inventory_harness.dart';

void main() {
  setUpAll(loadGeist);
  setUp(mockPreferences);

  testWidgets('List, 1440 x 1030', (tester) async {
    setViewSize(tester, const Size(1440, 1030), dpr: 1.5);
    await tester.pumpWidget(inventoryApp());
    await settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/inventory_1_list.png'),
    );
  });

  testWidgets('Grid, 1440 x 946', (tester) async {
    setViewSize(tester, const Size(1440, 946), dpr: 1.5);
    await tester.pumpWidget(inventoryApp(initial: gridState));
    await settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/inventory_2_grid.png'),
    );
  });
}
