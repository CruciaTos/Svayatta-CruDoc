import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// List / grid: two square icon buttons on an inset track, the chosen
/// one raised. Remembered per device.
class InventoryViewToggle extends ConsumerWidget {
  const InventoryViewToggle({super.key, required this.mode});

  final InventoryViewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    void pick(InventoryViewMode m) =>
        ref.read(inventoryControllerProvider.notifier).setViewMode(m);
    return Semantics(
      container: true,
      label: 'View',
      child: Container(
        height: CruSize.searchBar,
        padding: const EdgeInsets.all(CruSpace.s2 + 1),
        decoration: ShapeDecoration(
          color: c.inset,
          shape: cruShape(CruRadius.segmentOuter),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToggleButton(
              icon: InventoryIcons.list,
              label: 'List view',
              selected: mode == InventoryViewMode.list,
              onTap: () => pick(InventoryViewMode.list),
            ),
            const SizedBox(width: CruSpace.s2),
            _ToggleButton(
              icon: InventoryIcons.grid,
              label: 'Grid view',
              selected: mode == InventoryViewMode.grid,
              onTap: () => pick(InventoryViewMode.grid),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final CruIconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      button: true,
      toggled: selected,
      label: label,
      excludeSemantics: true,
      child: CruPressable(
        onTap: onTap,
        tooltip: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          width: CruSize.control,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected
                ? c.segmentSelected
                : (hovered ? c.hoverFill : c.inset.withValues(alpha: 0)),
            shape: cruShape(CruRadius.segmentInner),
            shadows: selected ? c.segmentShadow : null,
          ),
          child: CruIcon(
            icon,
            size: 18,
            strokeWidth: 1.9,
            color: selected ? c.label : c.label2,
          ),
        ),
      ),
    );
  }
}
