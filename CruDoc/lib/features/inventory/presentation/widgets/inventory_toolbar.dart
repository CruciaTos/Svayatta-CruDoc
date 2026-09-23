import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_search_field.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_sort_button.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_view_toggle.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Items / Orders / Vendors / Usage, then (on Items) search, the list/grid
/// toggle and sort.
class InventoryToolbar extends ConsumerWidget {
  const InventoryToolbar({
    super.key,
    required this.tab,
    required this.searchFocus,
    required this.viewMode,
    required this.sort,
    required this.hasUsage,
  });

  final InventoryTab tab;
  final FocusNode searchFocus;
  final InventoryViewMode viewMode;

  /// The sort actually applied.
  final InventorySort sort;
  final bool hasUsage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = tab == InventoryTab.items;
    return Row(
      children: [
        CruSegmentedControl<InventoryTab>(
          semanticLabel: 'Inventory sections',
          segments: [
            for (final t in InventoryTab.values) CruSegment(t, t.label),
          ],
          selected: tab,
          onChanged: ref.read(inventoryControllerProvider.notifier).setTab,
        ),
        if (items) ...[
          const SizedBox(width: CruSpace.s12),
          Expanded(child: InventorySearchField(focusNode: searchFocus)),
          const SizedBox(width: CruSpace.s12),
          InventoryViewToggle(mode: viewMode),
          const SizedBox(width: CruSpace.s12),
          InventorySortButton(sort: sort, hasUsage: hasUsage),
        ],
      ],
    );
  }
}
