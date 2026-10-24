import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'week_focus.dart';
import 'week_grid.dart';
import 'week_header.dart';
import 'week_metrics.dart';
import 'week_skeleton.dart';

/// Appointments, Week: one full-width card with columns Monday to Sunday
/// for the week containing the controller's anchor. Every column shares
/// one time range (1.2 px per minute). Closed days aren't stored (GAP),
/// so no column is drawn as closed.
///
/// Opening a day (its date or one of its visits): that column's edges
/// move out until it fills the grid, the other days squeeze away, and the
/// card's right edge comes in to where Day's grid ends; then Day takes
/// over. Back from Day, Week starts there and folds back into the week.
class AppointmentsWeekView extends ConsumerStatefulWidget {
  const AppointmentsWeekView({super.key});

  @override
  ConsumerState<AppointmentsWeekView> createState() =>
      _AppointmentsWeekViewState();
}

class _AppointmentsWeekViewState extends ConsumerState<AppointmentsWeekView>
    with SingleTickerProviderStateMixin {
  static const EdgeInsets _cardPadding = EdgeInsets.fromLTRB(
    CruSpace.s12,
    CruSpace.s16,
    CruSpace.s16,
    CruSpace.s18,
  );

  /// Day's grid card sides; the card eases to them as a column opens (the
  /// top and bottom stay, so the hours already line up).
  static const EdgeInsets _dayPadding = EdgeInsets.fromLTRB(
    CruSpace.s16,
    CruSpace.s16,
    CruSpace.s20,
    CruSpace.s18,
  );

  /// 0 = the week, 1 = the opening column fills the grid.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: CruMotion.standard,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _open,
    curve: CruMotion.curve,
    reverseCurve: CruMotion.curve.flipped,
  );

  /// The column opening (or folding back), 0 = Monday.
  int? _focus;

  @override
  void initState() {
    super.initState();
    if (!ref.read(apptsControllerProvider.notifier).takeWeekFromDay()) return;
    final anchor = ref.read(apptsControllerProvider).anchor;
    final i = ApptsBuilder.weekDays(
      anchor,
    ).indexWhere((d) => DateUtils.isSameDay(d, anchor));
    if (i < 0) return;
    _focus = i;
    _open.value = 1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _foldBack());
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  /// Back from Day: Day fades out over the open column, then it folds.
  Future<void> _foldBack() async {
    if (!mounted) return;
    await Future<void>.delayed(CruMotion.of(context, CruMotion.fast));
    if (!mounted) return;
    _open.duration = CruMotion.of(context);
    await _open.reverse();
    if (mounted) setState(() => _focus = null);
  }

  /// Opens column [index]'s [day] once the column has filled the grid.
  Future<void> _openDay(int index, DateTime day, {String? visitId}) async {
    if (_open.isAnimating || _focus != null || index < 0) return;
    setState(() => _focus = index);
    _open.duration = CruMotion.of(context);
    await _open.forward(from: 0);
    if (!mounted) return;
    ref.read(apptsControllerProvider.notifier).openDay(day, visitId: visitId);
  }

  @override
  Widget build(BuildContext context) {
    final anchor = ref.watch(apptsControllerProvider.select((s) => s.anchor));
    final now = ref.watch(apptsNowProvider);
    final today = ApptsBuilder.dateOnly(now);
    final days = ApptsBuilder.weekDays(anchor);
    final async = ref.watch(apptItemsProvider);
    final all = async.value;

    if (all == null) {
      return SizedBox(
        width: double.infinity,
        child: async.hasError
            ? CruCard(
                child: Text(
                  "Couldn't load appointments.",
                  style: CruType.text.tint(context.cru.label2),
                ),
              )
            : const WeekSkeleton(),
      );
    }

    final last = days.last;
    final weekItems = ApptsBuilder.inRange(
      all,
      days.first,
      DateTime(last.year, last.month, last.day + 1),
    );
    // All seven columns share one range, built from the whole week.
    final range = ApptsBuilder.range(weekItems, days.first);
    final groups = <DateTime, List<OverlapGroup>>{
      for (final d in days)
        d: ref.watch(apptDayGroupsProvider(d)).value ?? const <OverlapGroup>[],
    };
    // Day's grid stops where its right column starts (split layout).
    final split = MediaQuery.sizeOf(context).width >= CruBreakpoint.splitPane;

    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth;
        final dayGrid = split
            ? full - CruSize.rightColumn - CruSpace.cardGap
            : full;
        return AnimatedBuilder(
          animation: _curve,
          builder: (context, _) {
            final t = _focus == null ? 0.0 : _curve.value;
            final focus = WeekFocus(_focus, t);
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: lerpDouble(full, dayGrid, t),
                child: CruCard(
                  padding: EdgeInsets.lerp(_cardPadding, _dayPadding, t)!,
                  semanticLabel: 'Week schedule',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Day has no date row: it folds away as the column
                      // opens, so the hours land where Day draws them.
                      ClipRect(
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: 1 - t,
                          child: Opacity(
                            opacity: 1 - t,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                WeekHeaderRow(
                                  days: days,
                                  today: today,
                                  focus: focus,
                                  onOpenDay: _openDay,
                                ),
                                const SizedBox(height: CruSpace.s10),
                                const CruSeparator(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(
                            top: WeekMetrics.gridTop,
                            bottom: WeekMetrics.gridBottom,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _grid(
                              range,
                              days,
                              groups,
                              today,
                              now,
                              focus,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _grid(
    DayRange range,
    List<DateTime> days,
    Map<DateTime, List<OverlapGroup>> groups,
    DateTime today,
    DateTime now,
    WeekFocus focus,
  ) {
    final sessions = range.sessions;
    final grid = <Widget>[];
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final start = WeekMetrics.minuteOf(s.start, s.start);
      final end = WeekMetrics.minuteOf(s.end, s.start);
      final isLast = i == sessions.length - 1;
      // Groups belong to the session they start in; the last session
      // takes anything after it, the first anything before it.
      bool inSession(OverlapGroup g) {
        final m = g.start.hour * 60 + g.start.minute;
        final afterStart = i == 0 || m >= start;
        final beforeEnd = isLast || m < end;
        return afterStart && beforeEnd;
      }

      if (i > 0) {
        grid.add(WeekBreakBand(from: sessions[i - 1].end, to: s.start));
      }
      grid.add(
        WeekSessionGrid(
          startMinute: start,
          endMinute: end,
          days: days,
          groupsByDay: {
            for (final e in groups.entries)
              e.key: e.value.where(inSession).toList(),
          },
          today: today,
          now: now,
          focus: focus,
          onOpenVisit: (day, item) =>
              _openDay(days.indexOf(day), day, visitId: item.id),
        ),
      );
    }
    return grid;
  }
}
