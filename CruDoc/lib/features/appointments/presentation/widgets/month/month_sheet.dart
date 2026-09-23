import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Dim backdrop behind the Month day panel when it shows as a sheet
/// (below 1200 px). Same look as the Patients preview backdrop.
class MonthSheetBackdrop extends StatelessWidget {
  const MonthSheetBackdrop({super.key, required this.onTap});

  final VoidCallback onTap;

  /// Backdrop dim, as on Patients (label at 24%).
  static const double _dim = 0.24;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      button: true,
      label: 'Close day',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: CruMotion.of(context, CruMotion.pane),
          curve: CruMotion.curve,
          builder: (context, t, _) => DecoratedBox(
            decoration: ShapeDecoration(
              color: c.label.withValues(alpha: _dim * t),
              shape: cruShape(CruRadius.card),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slides the sheet in from the right (16 px) while fading it in.
class MonthSheetSlide extends StatelessWidget {
  const MonthSheetSlide({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: CruMotion.of(context, CruMotion.pane),
      curve: CruMotion.curve,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(CruSpace.s16 * (1 - t), 0),
          child: child,
        ),
      ),
    );
  }
}
