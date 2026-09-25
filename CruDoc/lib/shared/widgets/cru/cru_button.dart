import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/cru_theme.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru_pressable.dart';

enum CruButtonKind {
  /// The one filled action in a region.
  primary,

  /// Surface fill + hairline (header "Add patient").
  secondary,

  /// Inset fill ("View history", "New visit" on the empty Up next card).
  inset,

  /// accentTint fill with accentText ("Close the day").
  tinted,

  /// Transparent with a 1 px separator ring and accentText ("Open full
  /// profile").
  outline,
}

/// A 40 or 44 px button with radius 12.
class CruButton extends StatelessWidget {
  const CruButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = CruButtonKind.primary,
    this.icon,
    this.large = false,
    this.expand = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final CruButtonKind kind;
  final CruIconData? icon;

  /// 44 px with 15 px text instead of 40 px with 14 px text.
  final bool large;

  /// Full width.
  final bool expand;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (Color fill, Color fg, Color? iconColor) = switch (kind) {
      CruButtonKind.primary => (c.primaryButtonFill, c.primaryButtonText, null),
      CruButtonKind.secondary => (c.surface, c.label, c.label2),
      CruButtonKind.inset => (c.inset, c.label, c.label2),
      CruButtonKind.tinted => (c.accentTint, c.accentText, null),
      CruButtonKind.outline => (c.surface, c.accentText, null),
    };
    final isPrimary = kind == CruButtonKind.primary;
    final base = large ? CruType.row : CruType.text;
    final style = base.copyWith(
      color: fg,
      fontWeight: isPrimary ||
              kind == CruButtonKind.tinted ||
              kind == CruButtonKind.outline
          ? FontWeight.w600
          : FontWeight.w500,
    );
    final height = large ? CruSize.actionButton : CruSize.control;
    final padding = large
        ? EdgeInsets.symmetric(horizontal: isPrimary ? 20 : 18)
        : (icon != null && isPrimary
            ? const EdgeInsets.fromLTRB(13, 0, 16, 0)
            : const EdgeInsets.symmetric(horizontal: 14));

    return CruPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel ?? label,
      builder: (context, hovered) {
        final bg = hovered ? cruHoverShade(fill, c) : fill;
        return AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: height,
          width: expand ? double.infinity : null,
          padding: padding,
          decoration: ShapeDecoration(
            color: bg,
            shape: cruShape(
              CruRadius.control,
              side: switch (kind) {
                CruButtonKind.secondary => BorderSide(color: c.hairline),
                CruButtonKind.outline => BorderSide(color: c.separator),
                _ => BorderSide.none,
              },
            ),
            shadows: kind == CruButtonKind.secondary ? c.cardShadow : null,
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                CruIcon(
                  icon!,
                  size: isPrimary ? 16 : 17,
                  strokeWidth: isPrimary ? 2.4 : 1.8,
                  color: iconColor ?? fg,
                ),
                const SizedBox(width: CruSpace.s6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum CruCapsuleKind {
  /// Inset fill (list actions: "Book", "Update", "Edit plan").
  inset,

  /// accentTint fill ("Call", "WhatsApp" beside a profile).
  tinted,

  /// Surface fill with a hairline ring and card shadow ("Send reminders",
  /// "Record payment" on an inset panel).
  surface,
}

/// A capsule for list actions: accentText 13/600, 30 px by default.
class CruCapsuleButton extends StatelessWidget {
  const CruCapsuleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.kind = CruCapsuleKind.inset,
    this.icon,
    this.height = CruSize.capsule,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final CruCapsuleKind kind;
  final CruIconData? icon;
  final double height;

  /// 13.5 px label instead of 13 px (36 px capsules).
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fill = switch (kind) {
      CruCapsuleKind.inset => c.inset,
      CruCapsuleKind.tinted => c.accentTint,
      CruCapsuleKind.surface => c.surface,
    };
    final style = (large ? CruType.chip : CruType.subhead).copyWith(
      color: c.accentText,
      fontWeight: FontWeight.w600,
    );
    return CruPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel ?? label,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(fill, c) : fill,
          shape: StadiumBorder(
            side: kind == CruCapsuleKind.surface
                ? BorderSide(color: c.hairline)
                : BorderSide.none,
          ),
          shadows: kind == CruCapsuleKind.surface ? c.cardShadow : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              CruIcon(icon!, size: 15, strokeWidth: 2, color: c.accentText),
              const SizedBox(width: CruSpace.s6),
            ],
            Text(label, style: style, maxLines: 1),
          ],
        ),
      ),
    );
  }
}

/// A filled square icon button: 36 px inset (preview pane ↗ and ×) or
/// 40 px secondary surface with hairline (the details "…").
class CruSquareButton extends StatelessWidget {
  const CruSquareButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.secondary = false,
    this.iconSize = 17,
    this.strokeWidth = 2,
    this.tooltip,
  });

  final CruIconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  /// 40 px surface + hairline + shadow instead of 36 px inset.
  final bool secondary;
  final double iconSize;
  final double strokeWidth;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final size = secondary ? CruSize.control : CruSize.squareButton;
    final fill = secondary ? c.surface : c.inset;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      tooltip: tooltip,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(fill, c) : fill,
          shape: cruShape(
            secondary ? CruRadius.control : CruRadius.iconTile,
            side: secondary ? BorderSide(color: c.hairline) : BorderSide.none,
          ),
          shadows: secondary ? c.cardShadow : null,
        ),
        child: CruIcon(
          icon,
          size: iconSize,
          strokeWidth: strokeWidth,
          color: c.label2,
        ),
      ),
    );
  }
}

/// A transparent square icon button (the Up next "…").
class CruIconButton extends StatelessWidget {
  const CruIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = CruSize.actionButton,
    this.iconSize = 20,
    this.tooltip,
  });

  final CruIconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      tooltip: tooltip,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: hovered ? c.inset : c.inset.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: CruIcon(icon, size: iconSize, color: c.label2),
      ),
    );
  }
}

/// An inline text link ("Show", "Upgrade", "Add a walk-in").
class CruLink extends StatelessWidget {
  const CruLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.style,
    this.trailing,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final TextStyle? style;
  final Widget? trailing;

  /// A leading icon ("‹ Patients").
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fg = color ?? c.accentText;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: label,
      scaleOnPress: false,
      builder: (context, hovered) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            IconTheme(data: IconThemeData(color: fg), child: leading!),
            const SizedBox(width: CruSpace.s2),
          ],
          Text(
            label,
            style: (style ?? CruType.subhead.w600).copyWith(
              color: hovered ? cruHoverShade(fg, c) : fg,
              decoration: hovered ? TextDecoration.underline : null,
              decorationColor: fg,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: CruSpace.s4),
            IconTheme(data: IconThemeData(color: fg), child: trailing!),
          ],
        ],
      ),
    );
  }
}
