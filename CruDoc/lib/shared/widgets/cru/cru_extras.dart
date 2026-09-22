import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/cru_theme.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_icons.dart';

/// A 6 px linear progress bar on the track colour. Accent while in
/// progress; pass [complete] (or a green [color]) for paid / done.
class CruProgressBar extends StatelessWidget {
  const CruProgressBar({
    super.key,
    required this.value,
    this.color,
    this.semanticLabel,
  });

  /// 0–1.
  final double value;

  /// Defaults to accent.
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(v * 100).round()}%',
      child: SizedBox(
        height: CruSize.progressBar,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.track,
            borderRadius: BorderRadius.circular(CruRadius.thinBar),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: v),
              duration: CruMotion.of(context),
              curve: CruMotion.curve,
              builder: (context, t, _) => FractionallySizedBox(
                widthFactor: t,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color ?? c.accent,
                    borderRadius: BorderRadius.circular(CruRadius.thinBar),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum CruInfoPillTone {
  /// Inset fill, label text (phone, "No known allergies" in the pane).
  neutral,

  /// Surface fill with a hairline border (the details identity chips).
  outlined,

  /// redTint / redText, weight 600. Allergies only.
  allergy,
}

/// A fully round information pill: 28 px in the preview pane, 30 px
/// ([tall]) on Patient details.
class CruInfoPill extends StatelessWidget {
  const CruInfoPill({
    super.key,
    required this.text,
    this.icon,
    this.tone = CruInfoPillTone.neutral,
    this.tall = false,
    this.tabular = false,
  });

  final String text;
  final CruIconData? icon;
  final CruInfoPillTone tone;
  final bool tall;
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (Color bg, Color fg, Color iconColor) = switch (tone) {
      CruInfoPillTone.neutral => (c.inset, c.label, c.label2),
      CruInfoPillTone.outlined => (c.surface, c.label, c.label2),
      CruInfoPillTone.allergy => (c.redTint, c.redText, c.redText),
    };
    var style = (tall ? CruType.subhead : CruType.caption).copyWith(
      color: fg,
      fontWeight:
          tone == CruInfoPillTone.allergy ? FontWeight.w600 : FontWeight.w500,
    );
    if (tabular) style = style.tabular;
    return Container(
      height: tall ? CruSize.chip : CruSize.infoPill,
      padding: EdgeInsets.symmetric(
        horizontal: tall ? CruSpace.s12 : CruSpace.s10,
      ),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(
          side: tone == CruInfoPillTone.outlined
              ? BorderSide(color: c.hairline)
              : BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            CruIcon(icon!, size: tall ? 14 : 13, strokeWidth: 2.2, color: iconColor),
            const SizedBox(width: CruSpace.s6),
          ],
          Flexible(
            child: Text(
              text,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A 44×48 date tile: month over day. Upcoming dates use the accent tint.
class CruDateTile extends StatelessWidget {
  const CruDateTile({
    super.key,
    required this.month,
    required this.day,
    this.upcoming = false,
  });

  /// "SEP".
  final String month;

  /// "30".
  final String day;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final bg = upcoming ? c.accentTint : c.inset;
    final monthColor = upcoming ? c.accentText : c.label2;
    final dayColor = upcoming ? c.accentText : c.label;
    return Container(
      width: CruSize.dateTileWidth,
      height: CruSize.dateTileHeight,
      decoration: ShapeDecoration(
        color: bg,
        shape: cruShape(CruRadius.iconTile),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(month, style: CruType.dateMonth.tint(monthColor)),
          Text(day, style: CruType.dateDay.tint(dayColor)),
        ],
      ),
    );
  }
}
