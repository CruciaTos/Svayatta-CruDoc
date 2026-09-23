import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/day_block.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/day_grid_marks.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/day_grid_metrics.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Day grid card: sessions at 1.6 px per minute with an hour line
/// every hour, blocks laid out in overlap columns, the now line (today
/// only), gutter markers for unsorted overlaps, and the legend under the
/// grid on days that have one. Scrolls inside the card.
class DayGrid extends ConsumerStatefulWidget {
  const DayGrid({
    super.key,
    required this.day,
    required this.items,
    required this.groups,
    required this.now,
    required this.ringedIds,
  });

  /// Date only.
  final DateTime day;
  final List<ApptItem> items;
  final List<OverlapGroup> groups;
  final DateTime now;

  /// Blocks drawn with the 2 px accent ring.
  final Set<String> ringedIds;

  @override
  ConsumerState<DayGrid> createState() => _DayGridState();
}

class _DayGridState extends ConsumerState<DayGrid> {
  final ScrollController _scroll = ScrollController();
  DateTime? _scrolledFor;

  /// Session label row and break band heights, for the initial scroll.
  static const double _labelRow = CruSpace.s16 + CruSpace.s12;
  static const double _band =
      DayGridMetrics.breakBand + CruSpace.s12 + CruSpace.s18;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the now line (today) or the first visit into view once per
  /// day, without moving when it's already visible.
  void _scrollIntoView(DayRange range) {
    if (_scrolledFor == widget.day) return;
    _scrolledFor = widget.day;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final isToday = ApptsBuilder.sameDay(widget.day, widget.now);
      final target = isToday
          ? widget.now
          : (widget.items.isEmpty ? null : widget.items.first.start);
      if (target == null) return;
      final y = _offsetOf(range, target);
      final viewport = _scroll.position.viewportDimension;
      if (y < viewport - CruSpace.s32 * 2) return;
      final to = (y - viewport / 3)
          .clamp(0.0, _scroll.position.maxScrollExtent)
          .toDouble();
      _scroll.jumpTo(to);
    });
  }

  double _offsetOf(DayRange range, DateTime t) {
    var y = 0.0;
    for (var i = 0; i < range.sessions.length; i++) {
      final s = range.sessions[i];
      if (s.label != null) y += _labelRow;
      y += DayGridMetrics.topInset;
      if (!t.isAfter(s.end) || i == range.sessions.length - 1) {
        final m = math.max(0, t.difference(s.start).inMinutes);
        return y + DayGridMetrics.minutes(m);
      }
      y += DayGridMetrics.minutes(s.end.difference(s.start).inMinutes) +
          DayGridMetrics.topInset +
          _band;
    }
    return y;
  }

  @override
  Widget build(BuildContext context) {
    final range = ApptsBuilder.range(widget.items, widget.day);
    final sessions = range.sessions;
    final showLegend = widget.groups
        .any((g) => g.isOverlap && g.kind == OverlapKind.unsorted);
    _scrollIntoView(range);

    return CruCard(
      semanticLabel: 'Day schedule',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s16,
        CruSpace.s20,
        CruSpace.s20,
        CruSpace.s22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < sessions.length; i++) ...[
                    if (sessions[i].label != null)
                      DaySessionLabel(
                        session: sessions[i],
                        booked: _inSession(sessions[i]).length,
                      ),
                    _SessionCanvas(
                      session: sessions[i],
                      items: _inSession(sessions[i]),
                      groups: widget.groups,
                      now: widget.now,
                      isToday: ApptsBuilder.sameDay(widget.day, widget.now),
                      ringedIds: widget.ringedIds,
                    ),
                    if (i < sessions.length - 1)
                      DayBreakBand(
                        from: sessions[i].end,
                        to: sessions[i + 1].start,
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (showLegend) const DayOverlapLegend(),
        ],
      ),
    );
  }

  List<ApptItem> _inSession(ClinicSession s) => [
        for (final i in widget.items)
          if (!i.start.isBefore(s.start) && i.start.isBefore(s.end)) i,
      ];
}

/// One session drawn to scale.
class _SessionCanvas extends ConsumerWidget {
  const _SessionCanvas({
    required this.session,
    required this.items,
    required this.groups,
    required this.now,
    required this.isToday,
    required this.ringedIds,
  });

  final ClinicSession session;
  final List<ApptItem> items;
  final List<OverlapGroup> groups;
  final DateTime now;
  final bool isToday;
  final Set<String> ringedIds;

  double _y(DateTime t) =>
      DayGridMetrics.minutes(t.difference(session.start).inMinutes);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final height = _y(session.end);
    final ids = {for (final i in items) i.id};
    final sessionGroups = [
      for (final g in groups)
        if (g.items.any((i) => ids.contains(i.id))) g,
    ];
    final showNow = isToday &&
        !now.isBefore(session.start) &&
        !now.isAfter(session.end);

    // Whole hours inside the session.
    final firstHour = session.start.minute == 0
        ? session.start
        : DateTime(session.start.year, session.start.month, session.start.day,
            session.start.hour + 1);
    final hours = <DateTime>[
      for (var h = firstHour;
          !h.isAfter(session.end);
          h = h.add(const Duration(hours: 1)))
        h,
    ];
    final labelHalf =
        CruType.groupLabel.fontSize! * CruType.groupLabel.height! / 2;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DayGridMetrics.topInset),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final lane =
                width - DayGridMetrics.blockLeft - DayGridMetrics.blockRight;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Empty time: New appointment at the snapped time.
                Positioned(
                  left: DayGridMetrics.gutter,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) {
                        final minutes =
                            (d.localPosition.dy / DayGridMetrics.pxPerMinute)
                                .floor();
                        final t = session.start.add(Duration(minutes: minutes));
                        ApptActions.newAppointment(
                          context,
                          ref,
                          start: ApptsBuilder.snap(t),
                        );
                      },
                    ),
                  ),
                ),
                for (final h in hours)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _y(h) - labelHalf,
                    child: DayHourMark(hour: h.hour),
                  ),
                for (final g in sessionGroups)
                  if (g.isOverlap && g.kind == OverlapKind.unsorted)
                    Positioned(
                      left: 0,
                      width: DayGridMetrics.blockLeft,
                      top: _y(g.start) + 1,
                      height: math.max(0, _y(g.end) - _y(g.start) - 2),
                      child: DayOverlapMarker(
                        group: g,
                        height: math.max(0, _y(g.end) - _y(g.start) - 2),
                      ),
                    ),
                for (final g in sessionGroups)
                  for (final item in g.items)
                    if (ids.contains(item.id))
                      _positioned(context, ref, g, item, lane),
                if (showNow)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _y(now) - DayGridMetrics.gutterPill / 2,
                    height: DayGridMetrics.gutterPill,
                    child: DayNowLine(now: now),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _positioned(
    BuildContext context,
    WidgetRef ref,
    OverlapGroup g,
    ApptItem item,
    double lane,
  ) {
    final cols = math.max(1, g.columns);
    final col = g.columnOf[item.id] ?? 0;
    final colWidth =
        (lane - DayGridMetrics.blockGap * (cols - 1)) / cols;
    final controller = ref.read(apptsControllerProvider.notifier);
    final unsorted = g.isOverlap && g.kind == OverlapKind.unsorted;
    return Positioned(
      key: ValueKey(item.id),
      left: DayGridMetrics.blockLeft + col * (colWidth + DayGridMetrics.blockGap),
      width: math.max(0, colWidth),
      top: _y(item.start) + 1,
      height: math.max(
        DayGridMetrics.minutes(item.durationMinutes) - 2,
        DayGridMetrics.minutes(5),
      ),
      child: DayBlock(
        item: item,
        ringed: ringedIds.contains(item.id),
        onTap: () =>
            unsorted ? controller.selectGroup(g) : controller.select(item.id),
        onDoubleTap: () => ApptActions.openVisit(context, item),
      ),
    );
  }
}
