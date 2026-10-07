import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/dental/dental_features.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Allows a dentist to pick any mix of dental features they use.
/// At least one feature must stay on.
class DentalFeaturesPicker extends StatelessWidget {
  const DentalFeaturesPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<DentalFeature> selected;
  final ValueChanged<Set<DentalFeature>> onChanged;

  @override
  Widget build(BuildContext context) {
    const allFeatures = DentalFeature.values;

    return CruCard(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
      child: Column(
        children: [
          for (var i = 0; i < allFeatures.length; i++) ...[
            if (i > 0) const CruSeparator(indent: CruSpace.s16),
            _DentalFeatureRow(
              feature: allFeatures[i],
              isSelected: selected.contains(allFeatures[i]),
              disabled:
                  selected.contains(allFeatures[i]) && selected.length == 1,
              onToggle: () {
                final f = allFeatures[i];
                final isSelected = selected.contains(f);
                if (isSelected && selected.length == 1) {
                  return;
                }
                final next = Set<DentalFeature>.from(selected);
                if (isSelected) {
                  next.remove(f);
                } else {
                  next.add(f);
                }
                onChanged(next);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DentalFeatureRow extends StatelessWidget {
  const _DentalFeatureRow({
    required this.feature,
    required this.isSelected,
    required this.disabled,
    required this.onToggle,
  });

  final DentalFeature feature;
  final bool isSelected;
  final bool disabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feature.label, style: CruType.row.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(feature.detail, style: CruType.caption.tint(c.label3)),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Checkbox(
            value: isSelected,
            onChanged: disabled ? null : (_) => onToggle(),
            activeColor: c.accent,
            checkColor: c.onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            side: BorderSide(color: c.separator, width: 1.5),
          ),
        ],
      ),
    );

    return CruPressable(
      onTap: disabled ? null : onToggle,
      builder: (_, _) => row,
    );
  }
}
