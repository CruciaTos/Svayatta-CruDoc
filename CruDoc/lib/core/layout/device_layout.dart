import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

/// The PC layout ([DesktopShell]) is laid out at least this wide. A window
/// or tablet narrower than this shows the same layout scaled down.
const double kDesktopLayoutMinWidth = 1024;

/// Shortest side (logical pixels) from which a touch device counts as a
/// tablet.
const double kTabletShortestSide = 600;

/// True when this device gets the PC layout: every Windows/macOS/Linux
/// window, and tablets in either orientation. Phones (including landscape)
/// get the phone layout.
///
/// Decided by device type, not window width. `shortestSide` does not change
/// when the device rotates, so the answer is stable.
bool usesDesktopLayout(BuildContext context) {
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return true;
  }
  return MediaQuery.sizeOf(context).shortestSide >= kTabletShortestSide;
}

/// Lays [child] out at [minWidth] logical pixels when less room is
/// available, scaled down uniformly to fit (scale = width / [minWidth],
/// logical height = height / scale). At [minWidth] or wider it adds
/// nothing.
///
/// Inside, [MediaQuery] reports the larger logical window: size, and the
/// padding, view padding and view insets (so the on-screen keyboard keeps
/// its true share of the screen) are divided by the scale. Hit testing
/// follows the scale.
class ScaleToMinWidth extends StatelessWidget {
  const ScaleToMinWidth({
    super.key,
    this.minWidth = kDesktopLayoutMinWidth,
    required this.child,
  });

  final double minWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (!width.isFinite || !height.isFinite || width >= minWidth) {
          return child;
        }
        final scale = width / minWidth;
        final logicalHeight = height / scale;
        final media = MediaQuery.of(context);
        return FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: minWidth,
            height: logicalHeight,
            child: MediaQuery(
              data: media.copyWith(
                size: Size(minWidth, logicalHeight),
                padding: media.padding / scale,
                viewPadding: media.viewPadding / scale,
                viewInsets: media.viewInsets / scale,
                systemGestureInsets: media.systemGestureInsets / scale,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
