import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Inventory", "49 items · ₹41,200 in stock", New order and Add item.
class InventoryHeader extends StatelessWidget {
  const InventoryHeader({
    super.key,
    required this.view,
    required this.onNewOrder,
    required this.onAddItem,
  });

  /// Null while loading (the subtitle shows a skeleton).
  final InventoryView? view;

  /// Opens the existing Orders (reorder queue) section.
  final VoidCallback onNewOrder;
  final VoidCallback onAddItem;

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
      // Phone: title and count, then the two buttons side by side.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Inventory',
              style: CruType.largeTitle.copyWith(fontSize: 28).tint(c.label),
            ),
          ),
          const SizedBox(height: CruSpace.s2),
          SizedBox(
            height: CruType.text.fontSize! * CruType.text.height!,
            child: subtitle == null
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(width: 180, height: 12),
                  )
                : subtitle,
          ),
          const SizedBox(height: CruSpace.s14),
          Row(
            children: [
              CruButton(
                label: 'New order',
                kind: CruButtonKind.secondary,
                icon: InventoryIcons.cart,
                onPressed: onNewOrder,
              ),
              const SizedBox(width: CruSpace.s8),
              CruButton(
                label: 'Add item',
                icon: CruIcons.plus,
                onPressed: onAddItem,
              ),
            ],
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
                child: subtitle == null
                    ? const Align(
                        alignment: Alignment.centerLeft,
                        child: SkeletonBox(width: 180, height: 12),
                      )
                    : subtitle,
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
        const SizedBox(width: CruSpace.s10),
        CruButton(label: 'Add item', icon: CruIcons.plus, onPressed: onAddItem),
      ],
    );
  }
}
