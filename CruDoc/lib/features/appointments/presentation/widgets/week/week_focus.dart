import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../day/day_grid_metrics.dart';
import '../shell/appt_drag.dart';
import 'week_metrics.dart';

/// One Week column opening into its Day. [t] 0 is the plain week; at 1
/// that column fills the grid and the other six are squeezed to nothing.
class WeekFocus {
  const WeekFocus(this.index, this.t, {this.ringedId});

  static const none = WeekFocus(null, 0);

  /// The opening column, 0 = Monday; null when no day is opening.
  final int? index;
  final double t;

  /// The visit Day will show selected (ringed), so the ring is already
  /// there when Day takes over.
  final String? ringedId;

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

  /// How far an hour label sits above its line: Day centres it on it.
  double get hourLabelLift => lerpDouble(
    WeekMetrics.hourLabelLift,
    CruType.groupLabel.fontSize! * CruType.groupLabel.height! / 2,
    _p,
  )!;

  /// Blocks' gap to the column's sides: Day's 8 px at the end.
  double get blockInset =>
      lerpDouble(WeekMetrics.blockInset, DayGridMetrics.blockRight, _p)!;

  /// Week's look fading into Day's: chips into blocks, the column's own
  /// line and today's tint away. Starts a little after the column moves.
  double get dayLook =>
      active ? Curves.easeInOut.transform(((t - 0.15) / 0.7).clamp(0, 1)) : 0;
}

/// The hour gutter and the day columns of one Week row, sized by [focus].
/// The focused column's edges move out and its contents are laid out at
/// the new width, so its blocks widen with it. The others keep their week
/// layout and are squeezed, clipped and faded as they go.
class WeekColumnsRow extends StatefulWidget {
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
  State<WeekColumnsRow> createState() => _WeekColumnsRowState();
}

class _WeekColumnsRowState extends State<WeekColumnsRow>
    with SingleTickerProviderStateMixin {
  /// Columns still to slide: starts at the step's direction (±1) and eases
  /// to 0, so the days glide across instead of jumping.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    lowerBound: -1,
    upperBound: 1,
    value: 0,
  );
  int _seen = ApptSlide.steps.value.seq;

  @override
  void initState() {
    super.initState();
    ApptSlide.steps.addListener(_onStep);
  }

  void _onStep() {
    final s = ApptSlide.steps.value;
    if (s.seq == _seen) return;
    _seen = s.seq;
    _slide.value = s.dir.toDouble();
    _slide.animateTo(0, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    ApptSlide.steps.removeListener(_onStep);
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focus = widget.focus;
    final columns = widget.columns;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(0.0, constraints.maxWidth - focus.gutter);
        final even = columns.isEmpty ? 0.0 : available / columns.length;
        final cells = Row(
          crossAxisAlignment: widget.crossAxisAlignment,
          children: [
            for (var i = 0; i < columns.length; i++)
              _column(i, even, available),
          ],
        );
        return Row(
          crossAxisAlignment: widget.crossAxisAlignment,
          children: [
            SizedBox(width: focus.gutter, child: widget.gutter),
            if (focus.active)
              cells
            else
              SizedBox(
                width: available,
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _slide,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(_slide.value * even, 0),
                      child: child,
                    ),
                    child: cells,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _column(int i, double even, double available) {
    final focus = widget.focus;
    final columns = widget.columns;
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
