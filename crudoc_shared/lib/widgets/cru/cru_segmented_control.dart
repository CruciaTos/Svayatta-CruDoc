import 'package:flutter/material.dart';

import 'package:crudoc_shared/theme/cru_theme.dart';
import 'package:crudoc_shared/widgets/cru/cru_card.dart';
import 'package:crudoc_shared/widgets/cru/cru_pressable.dart';

class CruSegment<T> {
  const CruSegment(this.value, this.label, {this.enabled = true});
  final T value;
  final String label;
  final bool enabled;
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
    this.expand = false,
  });

  /// Fill the width given, every segment the same size (a phone's page
  /// switch); otherwise each segment is as wide as its label.
  final bool expand;

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
        // Scales down only when the labels can't fit (large system text on
        // a phone); otherwise it lays out exactly as a plain Row.
        child: expand
            ? Row(
                children: [
                  for (var i = 0; i < segments.length; i++) ...[
                    if (i > 0) const SizedBox(width: CruSpace.s2),
                    Expanded(
                      child: _Segment(
                        label: segments[i].label,
                        selected: segments[i].value == selected,
                        enabled: segments[i].enabled,
                        onTap: () => onChanged(segments[i].value),
                        fill: true,
                      ),
                    ),
                  ],
                ],
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < segments.length; i++) ...[
                      if (i > 0) const SizedBox(width: CruSpace.s2),
                      _Segment(
                        label: segments[i].label,
                        selected: segments[i].value == selected,
                        enabled: segments[i].enabled,
                        onTap: () => onChanged(segments[i].value),
                      ),
                    ],
                  ],
                ),
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
    this.fill = false,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Stretches to the width it is given (labels shrink to fit).
  final bool fill;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      enabled: enabled,
      child: CruPressable(
        onTap: enabled ? onTap : null,
        semanticLabel: label,
        scaleOnPress: false,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.segmentItem,
          padding: EdgeInsets.symmetric(
            horizontal: fill ? CruSpace.s4 : CruSpace.s14,
          ),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected
                ? c.segmentSelected
                : c.segmentSelected.withValues(alpha: 0),
            shape: cruShape(CruRadius.segmentInner),
            shadows: const [],
          ),
          child: AnimatedSwitcher(
            duration: CruMotion.of(context, CruMotion.fast),
            switchInCurve: CruMotion.curve,
            switchOutCurve: CruMotion.curve,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Opacity(
              opacity: enabled ? 1.0 : 0.45,
              child: _label(c, enabled && hovered),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(CruColors c, bool hovered) {
    final text = Text(
      label,
      key: ValueKey<String>(label),
      maxLines: 1,
      style: CruType.subhead.tabular.copyWith(
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected || hovered ? c.label : c.label2,
      ),
    );
    return fill
        ? FittedBox(fit: BoxFit.scaleDown, child: text)
        : text;
  }
}
