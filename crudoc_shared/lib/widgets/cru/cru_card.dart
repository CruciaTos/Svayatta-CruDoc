import 'package:flutter/material.dart';

import 'package:crudoc_shared/theme/cru_theme.dart';

/// Continuous-corner shape used across the design.
ShapeBorder cruShape(double radius, {BorderSide side = BorderSide.none}) =>
    RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side,
    );

/// A surface card with a subtle outline and no elevation shadow.
class CruCard extends StatelessWidget {
  const CruCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CruSpace.s24),
    this.borderColor,
    this.borderWidth = 1,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final double borderWidth;

  /// Region name for assistive tech (the reference's `aria-label`).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final side = BorderSide(
      color: borderColor ?? c.cardBorder,
      width: borderWidth,
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surface,
          shape: cruShape(CruRadius.card, side: side),
          shadows: const [],
        ),
        // The border is painted inside the shape; inset the content
        // by it too so sizes match the reference (CSS border-box).
        child: Padding(
          padding: padding.add(EdgeInsets.all(borderWidth)),
          child: child,
        ),
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
    final isEv = c.isEvening;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          ),
          shape: cruShape(
            CruRadius.card,
            side: isEv
                ? BorderSide(color: c.inkBorder)
                : BorderSide(
                    color: const Color(0xFF60A5FA).withValues(alpha: 0.35),
                  ),
          ),
        ),
        child: Theme(
          data: theme.copyWith(extensions: [onInk]),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: onInk.label),
            child: Padding(
              // Evening adds a 1 px border (see CruCard).
              padding: c.isEvening
                  ? padding.add(const EdgeInsets.all(1))
                  : padding,
              child: child,
            ),
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
