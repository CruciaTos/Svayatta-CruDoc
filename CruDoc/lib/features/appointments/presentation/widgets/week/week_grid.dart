import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../day/day_block.dart';
import 'week_block.dart';
import 'week_focus.dart';
import 'week_metrics.dart';

/// One drawn session of the Week grid (the whole day while working hours
/// aren't stored): the hour gutter plus seven day columns that share the
/// same time range.
class WeekSessionGrid extends StatelessWidget {
  const WeekSessionGrid({
    super.key,
    required this.startMinute,
    required this.endMinute,
    required this.days,
    required this.groupsByDay,
    required this.today,
    required this.now,
    required this.onOpenVisit,
    this.focus = WeekFocus.none,
  });

  /// A column opening into its Day (it also sets the hour height).
  final WeekFocus focus;

  double get pxPerMinute => focus.pxPerMinute;

  /// Minutes since midnight.
  final int startMinute;
  final int endMinute;
  final List<DateTime> days;

  /// This session's overlap groups per day (groups starting in it).
  final Map<DateTime, List<OverlapGroup>> groupsByDay;
  final DateTime today;
  final DateTime now;
  final void Function(DateTime day, ApptItem item) onOpenVisit;

  double get _height => (endMinute - startMinute) * pxPerMinute;

  /// Now's y offset, or null when now isn't inside this session this week.
  double? get _nowY {
    if (!days.contains(today)) return null;
    final m = now.hour * 60 + now.minute;
    if (m < startMinute || m > endMinute) return null;
    return (m - startMinute) * pxPerMinute;
  }

  @override
  Widget build(BuildContext context) {
    final nowY = _nowY;
    return SizedBox(
      height: _height,
      child: WeekColumnsRow(
        focus: focus,
        gutter: _Gutter(
          startMinute: startMinute,
          endMinute: endMinute,
          now: now,
          nowY: nowY,
          focus: focus,
          // Opening another day than today: Day has no now line, so the
          // time pill fades as the column opens.
          nowOpacity: focus.active && days[focus.index!] != today
              ? 1 - focus.dayLook
              : 1,
        ),
        columns: [
          for (var i = 0; i < days.length; i++)
            _DayColumn(
              focus: focus,
              opening: focus.active && focus.index == i,
              day: days[i],
              startMinute: startMinute,
              endMinute: endMinute,
              groups: groupsByDay[days[i]] ?? const [],
              isToday: days[i] == today,
              nowY: days[i] == today ? nowY : null,
              onOpenVisit: (item) => onOpenVisit(days[i], item),
            ),
        ],
      ),
    );
  }
}

/// Whole hours inside [start, end] minutes.
List<int> _hours(int start, int end) {
  final first = ((start + 59) ~/ 60) * 60;
  return [for (var m = first; m <= end; m += 60) m];
}

class _Gutter extends StatelessWidget {
  const _Gutter({
    required this.startMinute,
    required this.endMinute,
    required this.now,
    required this.nowY,
    required this.focus,
    this.nowOpacity = 1,
  });

  final int startMinute;
  final int endMinute;
  final DateTime now;
  final double? nowY;

  /// The time pill's opacity; an hour label it hides shows as it fades.
  final double nowOpacity;

  /// Sets the hour height, and moves the labels into Day's place and style
  /// as a column opens.
  final WeekFocus focus;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final pxPerMinute = focus.pxPerMinute;
    final labelEnd = focus.hourLabelEnd;
    final labelStyle = TextStyle.lerp(
      CruType.micro.tabular.tint(c.label3),
      CruType.groupLabel.w500.tabular.tint(c.label3),
      focus.active ? focus.t : 0,
    );
    final hourFormat = DateFormat('h a');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final m in _hours(startMinute, endMinute))
          Positioned(
            right: labelEnd,
            top: (m - startMinute) * pxPerMinute - focus.hourLabelLift,
            child: Opacity(
              // The time pill replaces an hour label it would collide with.
              opacity:
                  nowY != null &&
                      ((m - startMinute) * pxPerMinute - nowY!).abs() <
                          WeekMetrics.nowPill
                  ? 1 - nowOpacity
                  : 1,
              child: Text(
                hourFormat.format(DateTime(2000, 1, 1, m ~/ 60 % 24)),
                maxLines: 1,
                softWrap: false,
                style: labelStyle,
              ),
            ),
          ),
        if (nowY != null)
          Positioned(
            right: CruSpace.s6,
            top: nowY! - WeekMetrics.nowPill / 2,
            height: WeekMetrics.nowPill,
            child: Opacity(
              opacity: nowOpacity,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s6),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.accent,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  DashFormat.timeParts(now).$1,
                  maxLines: 1,
                  softWrap: false,
                  style: CruType.micro.w600.tabular.tint(c.onAccent),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.focus,
    required this.opening,
    required this.day,
    required this.startMinute,
    required this.endMinute,
    required this.groups,
    required this.isToday,
    required this.nowY,
    required this.onOpenVisit,
  });

  /// Sets the hour height, and how far the opening column has become Day.
  final WeekFocus focus;

  /// This column is opening into its Day: its chips grow into Day's blocks
  /// at Day's places, and its own line and today's tint fade away, so the
  /// last frame is Day itself.
  final bool opening;
  final DateTime day;
  final int startMinute;
  final int endMinute;
  final List<OverlapGroup> groups;
  final bool isToday;
  final double? nowY;
  final ValueChanged<ApptItem> onOpenVisit;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final pxPerMinute = focus.pxPerMinute;
    final height = (endMinute - startMinute) * pxPerMinute;
    final t = opening ? focus.t : 0.0;
    final dayLook = opening ? focus.dayLook : 0.0;
    final inset = opening ? focus.blockInset : WeekMetrics.blockInset;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final inner = width - 2 * inset;
        final blocks = <Widget>[];
        for (final g in groups) {
          final cols = g.columns < 1 ? 1 : g.columns;
          final bw = (inner - WeekMetrics.overlapGap * (cols - 1)) / cols;
          for (final item in g.items) {
            final col = g.columnOf[item.id] ?? 0;
            final m = item.start.hour * 60 + item.start.minute;
            final chip = WeekBlock(item: item, onTap: () => onOpenVisit(item));
            blocks.add(
              Positioned(
                left: inset + col * (bw + WeekMetrics.overlapGap),
                width: bw < 0 ? 0 : bw,
                top: (m - startMinute) * pxPerMinute + 1,
                // A 22 px chip grows as tall as Day draws the visit.
                height: opening
                    ? lerpDouble(
                        WeekMetrics.blockHeight,
                        math.max(
                          item.durationMinutes * pxPerMinute - 2,
                          5 * pxPerMinute,
                        ),
                        t,
                      )
                    : WeekMetrics.blockHeight,
                child: opening
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Opacity(opacity: 1 - dayLook, child: chip),
                          Opacity(
                            opacity: dayLook,
                            child: DayBlock(
                              item: item,
                              ringed: item.id == focus.ringedId,
                              onTap: () {},
                              onDoubleTap: () {},
                            ),
                          ),
                        ],
                      )
                    : chip,
              ),
            );
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (isToday)
              Positioned.fill(
                child: Opacity(
                  opacity: 1 - dayLook,
                  child: ColoredBox(color: c.accentWash),
                ),
              ),
            for (final m in _hours(startMinute, endMinute))
              Positioned(
                left: 0,
                right: 0,
                // Day draws the last line on the edge; Week keeps it in.
                top: ((m - startMinute) * pxPerMinute)
                    .clamp(0, height - 1 + dayLook)
                    .toDouble(),
                height: 1,
                child: ColoredBox(color: c.separator),
              ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 1,
              child: Opacity(
                opacity: 1 - dayLook,
                child: ColoredBox(color: c.separator),
              ),
            ),
            ...blocks,
            if (nowY != null) ...[
              Positioned(
                left: 0,
                right: 0,
                top: nowY! - WeekMetrics.nowLine / 2,
                height: WeekMetrics.nowLine,
                child: IgnorePointer(child: ColoredBox(color: c.accent)),
              ),
              Positioned(
                left: -WeekMetrics.nowDot / 2,
                top: nowY! - WeekMetrics.nowDot / 2,
                width: WeekMetrics.nowDot,
                height: WeekMetrics.nowDot,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The collapsed gap between two sessions, "Break · 1:30 to 5:00 PM", not
/// drawn to scale. Only used when working hours give more than one
/// session (they aren't stored today, so it never shows yet).
class WeekBreakBand extends StatelessWidget {
  const WeekBreakBand({super.key, required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s10, bottom: CruSpace.s14),
      child: Row(
        children: [
          const SizedBox(width: WeekMetrics.gutter),
          Expanded(
            child: Container(
              height: WeekMetrics.breakBand,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: c.inset,
                shape: cruShape(CruRadius.segmentInner),
              ),
              child: CruTimeText(
                'Break · ${DashFormat.timeRange(from, to)}',
                style: CruType.caption.tabular.tint(c.label2),
                timeColor: c.accentText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
