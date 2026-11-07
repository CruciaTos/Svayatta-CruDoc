import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_header.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_toolbar.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

void main() {
  testWidgets('Phone inventory header renders whole-width Add item button above screen switch', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    bool added = false;
    bool scanned = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryControllerProvider.overrideWith(
            () => InventoryController(),
          ),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InventoryHeader(
                    view: null,
                    onNewOrder: () {},
                    onAddItem: () => added = true,
                    onScan: () => scanned = true,
                  ),
                  const SizedBox(height: 20),
                  InventoryToolbar(
                    tab: InventoryTab.items,
                    searchFocus: FocusNode(),
                    viewMode: InventoryViewMode.list,
                    sort: InventorySort.name,
                    hasUsage: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Add item button exists
    final addItemFinder = find.widgetWithText(CruButton, 'Add item');
    expect(addItemFinder, findsOneWidget);

    // Verify it is whole-width (expand: true, so its RenderBox matches parent width)
    final renderBox = tester.renderObject<RenderBox>(addItemFinder);
    expect(renderBox.size.width, equals(390 - 32)); // 390 width - 16*2 padding

    // Verify the Add item button sits vertically ABOVE the screen switch (CruSegmentedControl)
    final segmentedFinder = find.byType(CruSegmentedControl<InventoryTab>);
    expect(segmentedFinder, findsOneWidget);

    final addItemBottom = tester.getBottomLeft(addItemFinder).dy;
    final segmentedTop = tester.getTopLeft(segmentedFinder).dy;
    expect(addItemBottom, lessThan(segmentedTop));

    // Verify tap triggers onAddItem
    await tester.tap(addItemFinder);
    expect(added, isTrue);

    // Verify Scan button is also accessible
    final scanFinder = find.bySemanticsLabel('Scan item or bill');
    expect(scanFinder, findsOneWidget);
    await tester.tap(scanFinder);
    expect(scanned, isTrue);
  });
}

