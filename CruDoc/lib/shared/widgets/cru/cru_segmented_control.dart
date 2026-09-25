import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/cru_theme.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_pressable.dart';

class CruSegment<T> {
  const CruSegment(this.value, this.label);
  final T value;
  final String label;
}

/// 36 px segmented control: inset track (radius 11), raised selected
/// segment (radius 8).
class CruSegmentedControl<T> extends StatelessWidget {
  const CruSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<CruSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      label: semanticLabel,
      container: true,
      child: Container(
        height: CruSize.segmentHeight,
        padding: const EdgeInsets.all(3),
        decoration: ShapeDecoration(
          color: c.inset,
          shape: cruShape(CruRadius.segmentOuter),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: CruSpace.s2),
              _Segment(
                label: segments[i].label,
                selected: segments[i].value == selected,
                onTap: () => onChanged(segments[i].value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: label,
        scaleOnPress: false,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.segmentItem,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected
                ? c.segmentSelected
                : c.segmentSelected.withValues(alpha: 0),
            shape: cruShape(CruRadius.segmentInner),
            shadows: selected ? c.segmentShadow : null,
          ),
          child: Text(
            label,
            style: CruType.subhead.tabular.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected || hovered ? c.label : c.label2,
            ),
          ),
        ),
      ),
    );
  }
}
