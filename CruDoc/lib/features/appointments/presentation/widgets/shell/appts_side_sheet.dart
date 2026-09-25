import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Below [CruBreakpoint.splitPane] a right-hand panel becomes a sheet: it
/// slides in over [content] with a dim backdrop while [open] is true.
/// Tapping the backdrop calls [onClose]. Same pattern as the Patients
/// preview pane.
class ApptsSideSheet extends StatelessWidget {
  const ApptsSideSheet({
    super.key,
    required this.open,
    required this.content,
    required this.sheet,
    required this.onClose,
  });

  final bool open;
  final Widget content;
  final Widget sheet;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final duration = CruMotion.of(context, CruMotion.pane);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          CruSize.rightColumn,
          constraints.maxWidth - 2 * CruSpace.s16,
        );
        return Stack(
          children: [
            Positioned.fill(child: content),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !open,
                child: Semantics(
                  button: open,
                  label: open ? 'Close panel' : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: AnimatedContainer(
                      duration: duration,
                      curve: CruMotion.curve,
                      color: c.label.withValues(alpha: open ? 0.24 : 0),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: width,
              child: IgnorePointer(
                ignoring: !open,
                child: AnimatedSlide(
                  duration: duration,
                  curve: CruMotion.curve,
                  offset: open ? Offset.zero : const Offset(1.1, 0),
                  child: AnimatedOpacity(
                    duration: duration,
                    curve: CruMotion.curve,
                    opacity: open ? 1 : 0,
                    child: sheet,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
