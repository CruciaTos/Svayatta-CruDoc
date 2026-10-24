import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Inventory", "49 items · ₹41,200 in stock", New order, Sterilization
/// (dentists), Scan and Add item.
class InventoryHeader extends StatelessWidget {
  const InventoryHeader({
    super.key,
    required this.view,
    required this.onNewOrder,
    required this.onAddItem,
    required this.onScan,
    this.onSterilization,
  });

  /// Null while loading (the subtitle shows a skeleton).
  final InventoryView? view;

  /// Opens the existing Orders (reorder queue) section.
  final VoidCallback onNewOrder;
  final VoidCallback onAddItem;
  final VoidCallback onScan;

  /// Opens the sterilization log; null hides the button (no sterilization
  /// for this login).
  final VoidCallback? onSterilization;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final v = view;
    final subtitle = v == null
        ? null
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: InventoryFormat.plural(v.all.length, 'item'),
                  style: CruType.text.tabular.tint(c.accentText),
                ),
                if (v.hasPrices) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: '${InventoryFormat.rupees(v.stockValue)} in stock',
                    style: CruType.text.tabular.tint(c.greenText),
                  ),
                ],
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );

    if (cruIsPhone(context)) {
      // Phone: title and count on left, scan and add item buttons at top right.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Inventory',
                    style: CruType.largeTitle
                        .copyWith(fontSize: 26)
                        .tint(c.label),
                  ),
                ),
                const SizedBox(height: CruSpace.s2),
                SizedBox(
                  height: CruType.text.fontSize! * CruType.text.height!,
                  child:
                      subtitle ??
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: SkeletonBox(width: 130, height: 12),
                      ),
                ),
              ],
            ),
          ),
          if (onSterilization != null) ...[
            const SizedBox(width: CruSpace.s8),
            CruSquareButton(
              icon: DentalIcons.shield,
              secondary: true,
              semanticLabel: 'Sterilization',
              tooltip: 'Sterilization',
              onPressed: onSterilization,
            ),
          ],
          const SizedBox(width: CruSpace.s8),
          CruSquareButton(
            icon: InventoryIcons.camera,
            secondary: true,
            semanticLabel: 'Scan item or bill',
            tooltip: 'Scan item',
            onPressed: onScan,
          ),
          const SizedBox(width: CruSpace.s8),
          CruButton(
            label: 'Add item',
            icon: CruIcons.plus,
            onPressed: onAddItem,
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Inventory',
                  style: CruType.largeTitle.tint(c.label),
                ),
              ),
              const SizedBox(height: CruSpace.s2),
              SizedBox(
                height: CruType.text.fontSize! * CruType.text.height!,
                child:
                    subtitle ??
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: SkeletonBox(width: 180, height: 12),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: CruSpace.s24),
        CruButton(
          label: 'New order',
          kind: CruButtonKind.secondary,
          icon: InventoryIcons.cart,
          onPressed: onNewOrder,
        ),
        if (onSterilization != null) ...[
          const SizedBox(width: CruSpace.s10),
          CruButton(
            label: 'Sterilization',
            kind: CruButtonKind.secondary,
            icon: DentalIcons.shield,
            onPressed: onSterilization,
          ),
        ],
        const SizedBox(width: CruSpace.s10),
        CruButton(
          label: 'Scan',
          kind: CruButtonKind.secondary,
          icon: InventoryIcons.camera,
          onPressed: onScan,
        ),
        const SizedBox(width: CruSpace.s10),
        CruButton(label: 'Add item', icon: CruIcons.plus, onPressed: onAddItem),
      ],
    );
  }
}
