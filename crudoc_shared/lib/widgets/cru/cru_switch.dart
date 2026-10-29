import 'package:flutter/material.dart';

import 'package:crudoc_shared/theme/cru_theme.dart';
import 'package:crudoc_shared/widgets/cru/cru_pressable.dart';

/// A 44 × 26 on/off switch: accent track when on, track colour when off,
/// white knob. Dimmed when [enabled] is false.
class CruSwitch extends StatelessWidget {
  const CruSwitch({
    super.key,
    required this.value,
    this.enabled = true,
    this.hovered = false,
  });

  final bool value;
  final bool enabled;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final track = value ? c.accent : c.track;
    return AnimatedOpacity(
      duration: CruMotion.of(context, CruMotion.fast),
      opacity: enabled ? 1 : 0.5,
      child: AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        width: CruSpace.s32 + CruSpace.s12,
        height: CruSpace.s24 + CruSpace.s2,
        padding: const EdgeInsets.all(CruSpace.s2),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(track, c) : track,
          shape: const StadiumBorder(),
        ),
        child: Container(
          width: CruSpace.s22,
          height: CruSpace.s22,
          decoration: ShapeDecoration(
            color: c.surface,
            shape: const CircleBorder(),
            shadows: c.isEvening ? const [] : c.cardShadow,
          ),
        ),
      ),
    );
  }
}

/// A setting that is on or off: title, an optional line under it, and the
/// switch at the right. The whole row toggles it.
class CruSwitchRow extends StatelessWidget {
  const CruSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;

  /// Null makes it read-only.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final enabled = onChanged != null;
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        child: CruPressable(
          onTap: enabled ? () => onChanged!(!value) : null,
          scaleOnPress: false,
          builder: (context, hovered) => Padding(
            padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: CruType.callout.tint(
                          enabled ? c.label : c.label2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: CruSpace.s2),
                        Text(subtitle!, style: CruType.subhead.tint(c.label2)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: CruSpace.s16),
                CruSwitch(value: value, enabled: enabled, hovered: hovered),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
