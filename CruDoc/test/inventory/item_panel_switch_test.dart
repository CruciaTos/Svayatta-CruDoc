import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_builder.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_item_panel.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'inventory_fixtures.dart';

void main() {
  // Saving a bill's lines re-sorts the list after each one, so the panel
  // can leave an item and come back to it before its fade-out ends.
  // Two panels for one item used to crash with "Duplicate keys found".
  testWidgets('switching back to an item mid-fade does not crash', (
    tester,
  ) async {
    final a = InventoryBuilder.item(fixtureMedicines[0], const [], inventoryNow);
    final b = InventoryBuilder.item(fixtureMedicines[1], const [], inventoryNow);
    final selected = ValueNotifier(a);
    addTearDown(selected.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stockPurchasesProvider.overrideWith(
            (ref) async => const <StockTransactionModel>[],
          ),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder(
                valueListenable: selected,
                builder: (_, item, _) => InventoryItemPanel(
                  item: item,
                  now: inventoryNow,
                  hasUsage: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (final next in [b, a, b, a]) {
      selected.value = next;
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(a.name), findsWidgets);
    expect(find.text(b.name), findsNothing);
  });
}
