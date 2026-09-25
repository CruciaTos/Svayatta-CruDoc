import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The amber strip above the list and grid: "3 items will run out this
/// week", their names, and how many orders (one per supplier).
///
/// "Order all" is a GAP (no purchase-order flow) and is not shown.
class InventoryRunOutStrip extends StatelessWidget {
  const InventoryRunOutStrip({super.key, required this.strip});

  final RunOutStrip strip;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final n = strip.items.length;
    final k = strip.supplierCount;
    final title = n == 1
        ? '1 item will run out this week'
        : '${InventoryFormat.count(n)} items will run out this week';
    final detail = [
      InventoryFormat.names([for (final i in strip.items) i.name]),
      if (k == 1) '1 order',
      if (k > 1) '${InventoryFormat.count(k)} orders, one per supplier',
    ].join(' · ');

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: CruMotion.of(context, CruMotion.strip),
      curve: CruMotion.curve,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Semantics(
        container: true,
        label: '$title. $detail',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s18,
            CruSpace.s14,
            CruSpace.s14,
            CruSpace.s14,
          ),
          decoration: ShapeDecoration(
            color: c.amberTint,
            shape: cruShape(CruRadius.strip),
          ),
          child: Row(
            children: [
              Container(
                width: CruSize.iconTile,
                height: CruSize.iconTile,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.surface,
                  shape: cruShape(CruRadius.iconTile),
                ),
                child: CruIcon(
                  CruIcons.box,
                  size: 18,
                  strokeWidth: 1.9,
                  color: c.amberText,
                ),
              ),
              const SizedBox(width: CruSpace.s14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CruType.row.tabular.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      detail,
                      style: CruType.subhead.tabular.tint(c.label2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
