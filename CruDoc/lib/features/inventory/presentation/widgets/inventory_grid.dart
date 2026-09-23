import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_list.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_vial.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Grid view: compact 104 px tiles (three columns, two when narrow), then
/// the vial legend and "Showing N of M".
class InventoryGrid extends StatelessWidget {
  const InventoryGrid({
    super.key,
    required this.view,
    required this.selectedId,
    required this.onTap,
    this.selectedKey,
    this.empty,
  });

  final InventoryView view;
  final String? selectedId;
  final InventoryItemTap onTap;
  final GlobalKey? selectedKey;
  final Widget? empty;

  /// Columns for a grid [width] wide (the screen uses it for arrow keys).
  static int columnsFor(double width) =>
      width >= InventorySize.gridThreeColumns ? 3 : 2;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final items = view.visible;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth);
        final rows = <Widget>[];
        for (var start = 0; start < items.length; start += columns) {
          if (start > 0) {
            rows.add(const SizedBox(height: InventorySize.tileGap));
          }
          rows.add(
            SizedBox(
              height: InventorySize.tileHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = start; i < start + columns; i++) ...[
                    if (i > start)
                      const SizedBox(width: InventorySize.tileGap),
                    Expanded(
                      child: i < items.length
                          ? _tile(items[i])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isEmpty && empty != null)
              CruCard(
                semanticLabel: 'Items',
                padding: const EdgeInsets.all(CruSpace.s12),
                child: empty!,
              )
            else
              Semantics(
                container: true,
                label: 'Items',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: CruSpace.s16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
                child: Row(
                  children: [
                    Expanded(
                      child: view.hasUsualOrders
                          ? const _Legend()
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: CruSpace.s16),
                    Text(
                      'Showing ${InventoryFormat.count(items.length)} of '
                      '${InventoryFormat.count(view.rows.length)}',
                      style: CruType.subhead.tabular.tint(c.label3),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _tile(InventoryItem item) {
    final selected = item.id == selectedId;
    final tile = InventoryTile(
      item: item,
      now: view.now,
      showDaysLeft: view.hasUsage,
      selected: selected,
      onTap: () => onTap(item),
    );
    return selected && selectedKey != null
        ? KeyedSubtree(key: selectedKey, child: tile)
        : tile;
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        // A sample vial: it illustrates the encoding, not an item.
        const InventoryVial(
          width: InventorySize.legendVialWidth,
          height: InventorySize.legendVialHeight,
          fill: 0.6,
          notch: 0.32,
          state: StockState.okay,
        ),
        const SizedBox(width: CruSpace.s8),
        Expanded(
          child: Text(
            'Vial shows stock against your usual order · '
            'the notch is your reorder level',
            style: CruType.subhead.tint(c.label3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// One 104 px tile: vial, name + form, big quantity, and the right-hand
/// slot (days left, or the expiry month when it expires first).
class InventoryTile extends StatelessWidget {
  const InventoryTile({
    super.key,
    required this.item,
    required this.now,
    required this.showDaysLeft,
    required this.selected,
    required this.onTap,
  });

  final InventoryItem item;
  final DateTime now;

  /// False when no item has usage ("days left" is a GAP then).
  final bool showDaysLeft;
  final bool selected;
  final VoidCallback onTap;

  /// The right-hand slot text and whether it is amber.
  (String, bool, bool)? _slot() {
    final daysLeft = item.daysLeft;
    final expiry = item.medicine.expiryDate;
    // Low stock wins: how long it lasts is the urgent fact.
    if (item.low && showDaysLeft && daysLeft != null) {
      return (
        InventoryFormat.left(daysLeft, outOfStock: item.outOfStock),
        true,
        true,
      );
    }
    if (item.expiresFirst && expiry != null && item.daysToExpiry != null) {
      return (
        InventoryFormat.expiresIn(expiry, item.daysToExpiry!, now),
        true,
        true,
      );
    }
    if (showDaysLeft && daysLeft != null) {
      return (
        InventoryFormat.left(daysLeft, outOfStock: item.outOfStock),
        false,
        false,
      );
    }
    if (item.outOfStock) return ('Out of stock', true, true);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final form = InventoryFormat.form(item.unit);
    final unit = InventoryFormat.unitFor(item.unit, item.stock);
    final slot = _slot();
    final label = [
      item.name,
      InventoryFormat.quantity(item.stock, item.unit),
      if (slot != null) slot.$1,
    ].join(', ');

    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s14,
            CruSpace.s14,
            CruSpace.s14,
            CruSpace.s12,
          ),
          decoration: ShapeDecoration(
            color: selected
                ? c.accentWash
                : (hovered ? cruHoverShade(c.surface, c) : c.surface),
            shape: cruShape(InventorySize.tileRadius),
            shadows: selected ? null : c.cardShadow,
          ),
          // The ring is a foreground so it never changes the padding.
          foregroundDecoration: ShapeDecoration(
            shape: cruShape(
              InventorySize.tileRadius,
              side: selected
                  ? BorderSide(color: c.accent, width: InventorySize.tileRing)
                  : BorderSide(color: c.hairline),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InventoryVial(
                width: InventorySize.tileVialWidth,
                height: InventorySize.tileVialHeight,
                fill: item.level,
                notch: item.notch,
                state: item.stockState,
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: CruType.callout.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (form.isNotEmpty)
                      Text(
                        form,
                        style: CruType.caption.tint(c.label2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: InventoryFormat.count(item.stock),
                                  style: inventoryTileQuantity.tint(
                                    stockText(c, item.stockState),
                                  ),
                                ),
                                if (unit.isNotEmpty)
                                  TextSpan(
                                    text: ' $unit',
                                    style: CruType.caption.tint(c.label2),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (slot != null) ...[
                          const SizedBox(width: CruSpace.s8),
                          Text(
                            slot.$1,
                            style: (slot.$3
                                    ? CruType.caption.w600
                                    : CruType.caption)
                                .tabular
                                .tint(slot.$2 ? c.amberText : c.label2),
                            maxLines: 1,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
