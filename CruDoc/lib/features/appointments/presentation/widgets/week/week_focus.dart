import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import '../day/day_grid_metrics.dart';
import 'week_metrics.dart';

/// One Week column opening into its Day. [t] 0 is the plain week; at 1
/// that column fills the grid and the other six are squeezed to nothing.
class WeekFocus {
  const WeekFocus(this.index, this.t);

  static const none = WeekFocus(null, 0);

  /// The opening column, 0 = Monday; null when no day is opening.
  final int? index;
  final double t;

  bool get active => index != null && t > 0;

  double get _p => active ? t : 0;

  /// An hour grows to Day's height.
  double get pxPerMinute =>
      lerpDouble(WeekMetrics.pxPerMinute, DayGridMetrics.pxPerMinute, _p)!;

  /// The time gutter widens to Day's.
  double get gutter =>
      lerpDouble(WeekMetrics.gutter, DayGridMetrics.gutter, _p)!;

  /// Gap between the hour labels and the first column, Day's at the end.
  double get hourLabelEnd => lerpDouble(
    WeekMetrics.hourLabelEnd,
    DayGridMetrics.gutter - DayGridMetrics.hourLabelWidth,
    _p,
  )!;
}

/// The hour gutter and the day columns of one Week row, sized by [focus].
/// The focused column's edges move out and its contents are laid out at
/// the new width, so its blocks widen with it. The others keep their week
/// layout and are squeezed, clipped and faded as they go.
class WeekColumnsRow extends StatelessWidget {
  const WeekColumnsRow({
    super.key,
    required this.focus,
    required this.columns,
    this.gutter = const SizedBox.shrink(),
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final WeekFocus focus;
  final List<Widget> columns;
  final Widget gutter;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(0.0, constraints.maxWidth - focus.gutter);
        final even = columns.isEmpty ? 0.0 : available / columns.length;
        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            SizedBox(width: focus.gutter, child: gutter),
            for (var i = 0; i < columns.length; i++)
              _column(i, even, available),
          ],
        );
      },
    );
  }

  Widget _column(int i, double even, double available) {
    final active = focus.active;
    final focused = i == focus.index;
    final t = focus.t;
    final width = !active
        ? even
        : focused
        ? lerpDouble(even, available, t)!
        : lerpDouble(even, 0, t)!;
    // The structure stays the same at rest and while opening, so nothing
    // inside is rebuilt from scratch when the animation starts.
    final layoutWidth = active && !focused ? even : width;
    return SizedBox(
      width: width,
      child: ClipRect(
        clipBehavior: active && !focused ? Clip.hardEdge : Clip.none,
        child: OverflowBox(
          // The header row has no fixed height: take the child's.
          fit: OverflowBoxFit.deferToChild,
          minWidth: layoutWidth,
          maxWidth: layoutWidth,
          child: Opacity(
            // The squeezed days are gone before they're fully closed.
            opacity: active && !focused ? (1 - t * 1.5).clamp(0.0, 1.0) : 1,
            child: columns[i],
          ),
        ),
      ),
    );
  }
}
