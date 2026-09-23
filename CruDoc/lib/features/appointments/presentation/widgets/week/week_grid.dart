import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'week_block.dart';
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
  });

  /// Minutes since midnight.
  final int startMinute;
  final int endMinute;
  final List<DateTime> days;

  /// This session's overlap groups per day (groups starting in it).
  final Map<DateTime, List<OverlapGroup>> groupsByDay;
  final DateTime today;
  final DateTime now;
  final void Function(DateTime day, ApptItem item) onOpenVisit;

  double get _height => (endMinute - startMinute) * WeekMetrics.pxPerMinute;

  /// Now's y offset, or null when now isn't inside this session this week.
  double? get _nowY {
    if (!days.contains(today)) return null;
    final m = now.hour * 60 + now.minute;
    if (m < startMinute || m > endMinute) return null;
    return (m - startMinute) * WeekMetrics.pxPerMinute;
  }

  @override
  Widget build(BuildContext context) {
    final nowY = _nowY;
    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: WeekMetrics.gutter,
            child: _Gutter(
              startMinute: startMinute,
              endMinute: endMinute,
              now: now,
              nowY: nowY,
            ),
          ),
          for (final d in days)
            Expanded(
              child: _DayColumn(
                day: d,
                startMinute: startMinute,
                endMinute: endMinute,
                groups: groupsByDay[d] ?? const [],
                isToday: d == today,
                nowY: d == today ? nowY : null,
                onOpenVisit: (item) => onOpenVisit(d, item),
              ),
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
  });

  final int startMinute;
  final int endMinute;
  final DateTime now;
  final double? nowY;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final labelStyle = CruType.micro.tabular.tint(c.label3);
    final hourFormat = DateFormat('h a');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final m in _hours(startMinute, endMinute))
          // The time pill replaces an hour label it would collide with.
          if (nowY == null ||
              ((m - startMinute) * WeekMetrics.pxPerMinute - nowY!).abs() >=
                  WeekMetrics.nowPill)
            Positioned(
              right: WeekMetrics.hourLabelEnd,
              top: (m - startMinute) * WeekMetrics.pxPerMinute -
                  WeekMetrics.hourLabelLift,
              child: Text(
                hourFormat.format(DateTime(2000, 1, 1, m ~/ 60 % 24)),
                maxLines: 1,
                softWrap: false,
                style: labelStyle,
              ),
            ),
        if (nowY != null)
          Positioned(
            right: CruSpace.s6,
            top: nowY! - WeekMetrics.nowPill / 2,
            height: WeekMetrics.nowPill,
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
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.startMinute,
    required this.endMinute,
    required this.groups,
    required this.isToday,
    required this.nowY,
    required this.onOpenVisit,
  });

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
    final height = (endMinute - startMinute) * WeekMetrics.pxPerMinute;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final inner = width - 2 * WeekMetrics.blockInset;
        final blocks = <Widget>[];
        for (final g in groups) {
          final cols = g.columns < 1 ? 1 : g.columns;
          final bw = (inner - WeekMetrics.overlapGap * (cols - 1)) / cols;
          for (final item in g.items) {
            final col = g.columnOf[item.id] ?? 0;
            final m = item.start.hour * 60 + item.start.minute;
            blocks.add(Positioned(
              left: WeekMetrics.blockInset + col * (bw + WeekMetrics.overlapGap),
              width: bw < 0 ? 0 : bw,
              top: (m - startMinute) * WeekMetrics.pxPerMinute + 1,
              height: WeekMetrics.blockHeight,
              child: WeekBlock(item: item, onTap: () => onOpenVisit(item)),
            ));
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (isToday) Positioned.fill(child: ColoredBox(color: c.accentWash)),
            for (final m in _hours(startMinute, endMinute))
              Positioned(
                left: 0,
                right: 0,
                top: ((m - startMinute) * WeekMetrics.pxPerMinute)
                    .clamp(0, height - 1)
                    .toDouble(),
                height: 1,
                child: ColoredBox(color: c.separator),
              ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 1,
              child: ColoredBox(color: c.separator),
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
              child: Text(
                'Break · ${DashFormat.timeRange(from, to)}',
                style: CruType.caption.tabular.tint(c.label2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
