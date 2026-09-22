import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/cru_theme.dart';

/// Continuous-corner shape used across the design.
ShapeBorder cruShape(double radius, {BorderSide side = BorderSide.none}) =>
    RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side,
    );

/// A surface card: radius 24, hairline border, Day shadow.
class CruCard extends StatelessWidget {
  const CruCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CruSpace.s24),
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Region name for assistive tech (the reference's `aria-label`).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surface,
          shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
          shadows: c.cardShadow,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// The ink surface for the Up next card. Everything inside reads the
/// scoped on-ink colours (white text, translucent insets, white primary
/// button) from the theme.
class CruInkCard extends StatelessWidget {
  const CruInkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 22, 24, 24),
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.cru;
    final onInk = c.onInk();
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.ink,
          shape: cruShape(
            CruRadius.card,
            side: c.isEvening ? BorderSide(color: c.inkBorder) : BorderSide.none,
          ),
          shadows: c.inkShadow,
        ),
        child: Theme(
          data: theme.copyWith(extensions: [onInk]),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: onInk.label),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// A 1 px separator that can start at a text column.
class CruSeparator extends StatelessWidget {
  const CruSeparator({super.key, this.indent = 0, this.endIndent = 0});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      child: SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: context.cru.separator),
      ),
    );
  }
}
