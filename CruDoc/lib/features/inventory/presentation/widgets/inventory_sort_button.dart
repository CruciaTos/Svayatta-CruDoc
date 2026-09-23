import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Sort  Runs out soonest ⌄" with a small on-token menu. "Runs out
/// soonest" is left out when no item has any usage.
class InventorySortButton extends ConsumerWidget {
  const InventorySortButton({
    super.key,
    required this.sort,
    required this.hasUsage,
  });

  /// The sort actually applied.
  final InventorySort sort;
  final bool hasUsage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final itemShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(CruRadius.control - CruSpace.s6),
    );
    final options = [
      for (final s in InventorySort.values)
        if (s != InventorySort.runsOut || hasUsage) s,
    ];
    return MenuAnchor(
      alignmentOffset: const Offset(0, CruSpace.s6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor:
            WidgetStatePropertyAll(c.surface.withValues(alpha: 0)),
        shadowColor: WidgetStatePropertyAll(c.label.withValues(alpha: 0.18)),
        elevation: WidgetStatePropertyAll(c.isEvening ? 0 : 8),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(CruSpace.s6)),
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(CruRadius.control),
            side: BorderSide(color: c.hairline),
          ),
        ),
      ),
      menuChildren: [
        for (final s in options)
          MenuItemButton(
            onPressed: () =>
                ref.read(inventoryControllerProvider.notifier).setSort(s),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(
                Size(0, CruSize.control),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: CruSpace.s12),
              ),
              shape: WidgetStatePropertyAll(itemShape),
              overlayColor: WidgetStatePropertyAll(
                c.hoverFill.withValues(alpha: 0),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused)
                    ? c.hoverFill
                    : c.surface,
              ),
            ),
            trailingIcon: s == sort
                ? CruIcon(
                    CruIcons.check,
                    size: 16,
                    strokeWidth: 2.2,
                    color: c.accentText,
                  )
                : null,
            child: Text(
              s.label,
              style: (s == sort ? CruType.text.w600 : CruType.text.w500)
                  .tint(c.label),
            ),
          ),
      ],
      builder: (context, controller, _) => CruPressable(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        semanticLabel: 'Sort by ${sort.label}',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.searchBar,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: hovered ? c.hoverFill : c.surface,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(color: c.hairline),
            ),
            shadows: c.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sort', style: CruType.text.w500.tint(c.label2)),
              const SizedBox(width: CruSpace.s6),
              Text(sort.label, style: CruType.text.w500.tint(c.label)),
              const SizedBox(width: CruSpace.s6),
              CruIcon(
                CruIcons.chevronDown,
                size: 14,
                strokeWidth: 2.2,
                color: c.label2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
