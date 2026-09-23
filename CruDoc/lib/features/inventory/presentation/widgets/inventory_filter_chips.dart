import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// All, Low stock, Expiring soon, then one chip per category, each with
/// its count. A chip with nothing in it is hidden (except All).
class InventoryFilterChips extends ConsumerWidget {
  const InventoryFilterChips({
    super.key,
    required this.chips,
    required this.active,
  });

  final List<InventoryChip> chips;

  /// The filter actually applied.
  final InventoryFilter active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      container: true,
      label: 'Item lists',
      child: Wrap(
        spacing: CruSpace.s8,
        runSpacing: CruSpace.s8,
        children: [
          for (final chip in chips)
            if (chip.filter == InventoryFilter.all || chip.count > 0)
              _Chip(
                chip: chip,
                selected: chip.filter == active,
                onTap: () => ref
                    .read(inventoryControllerProvider.notifier)
                    .setFilter(chip.filter),
              ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.chip,
    required this.selected,
    required this.onTap,
  });

  final InventoryChip chip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final f = chip.filter;
    final fg = selected ? c.accentText : c.label;
    final label = selected ? CruType.chip.w600 : CruType.chip;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: '${f.label}, ${chip.count}',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.filterChip,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: selected
                ? c.accentTint
                : (hovered ? c.hoverFill : c.surface),
            // A transparent ring when selected so the size never changes.
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? c.hairline.withValues(alpha: 0) : c.hairline,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (f.attention) ...[
                Container(
                  width: CruSize.smallDot,
                  height: CruSize.smallDot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.amber,
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
              ],
              Text(f.label, style: label.tint(fg)),
              const SizedBox(width: CruSpace.s8),
              Text(
                InventoryFormat.count(chip.count),
                style: CruType.chip.tabular.tint(
                  selected ? c.accentText : c.label2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
