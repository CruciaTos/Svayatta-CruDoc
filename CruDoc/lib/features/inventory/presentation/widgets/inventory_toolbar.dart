import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_search_field.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_sort_button.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_view_toggle.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/swipe_pages.dart';

/// Items / Orders / Vendors / Usage, then (on Items, [tab]) search, the
/// list/grid toggle and sort.
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
    // Pinned while the sections slide, so every section's copy shows the
    // selected one.
    final sections = CruSegmentedControl<InventoryTab>(
      semanticLabel: 'Inventory sections',
      segments: [for (final t in InventoryTab.values) CruSegment(t, t.label)],
      selected: ref.watch(inventoryControllerProvider).tab,
      onChanged: ref.read(inventoryControllerProvider.notifier).setTab,
    );
    if (cruIsPhone(context)) {
      // Phone: the sections on one line, search and sort under them.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwipePinned(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: sections,
            ),
          ),
          if (items) ...[
            const SizedBox(height: CruSpace.s10),
            Row(
              children: [
                Expanded(child: InventorySearchField(focusNode: searchFocus)),
                const SizedBox(width: CruSpace.s8),
                InventorySortButton(sort: sort, hasUsage: hasUsage),
              ],
            ),
          ],
        ],
      );
    }
    // Items' own controls share the sections' row: they fade in place
    // while the sections slide, so they never slide across the switch.
    return Row(
      children: [
        SwipePinned(child: sections),
        if (items) ...[
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: SwipePinned.fade(
              child: InventorySearchField(focusNode: searchFocus),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          SwipePinned.fade(child: InventoryViewToggle(mode: viewMode)),
          const SizedBox(width: CruSpace.s12),
          SwipePinned.fade(
            child: InventorySortButton(sort: sort, hasUsage: hasUsage),
          ),
        ],
      ],
    );
  }
}
