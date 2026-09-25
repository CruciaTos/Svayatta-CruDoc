import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Single-select filter chips with live counts. A chip with no patients
/// is hidden (except All).
class PatientsFilterChips extends ConsumerWidget {
  const PatientsFilterChips({
    super.key,
    required this.counts,
    required this.active,
  });

  final Map<PatientFilter, int> counts;

  /// The filter actually applied (a stale choice falls back to All).
  final PatientFilter active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = [
      for (final f in PatientFilter.values)
        if (f == PatientFilter.all || (counts[f] ?? 0) > 0)
          _FilterChip(
            filter: f,
            count: counts[f] ?? 0,
            selected: f == active,
            onTap: () =>
                ref.read(patientsListControllerProvider.notifier).setFilter(f),
          ),
    ];
    return Semantics(
      container: true,
      label: 'Patient lists',
      child: Wrap(
        spacing: CruSpace.s8,
        runSpacing: CruSpace.s8,
        children: chips,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.filter,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final PatientFilter filter;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fg = selected ? c.accentText : c.label;
    final label = selected ? CruType.chip.w600 : CruType.chip;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: '${filter.label}, $count',
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
              if (filter.attention) ...[
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
              Text(filter.label, style: label.tint(fg)),
              const SizedBox(width: CruSpace.s8),
              Text(
                '$count',
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
