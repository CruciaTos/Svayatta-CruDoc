import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'week_grid.dart';
import 'week_header.dart';
import 'week_metrics.dart';
import 'week_skeleton.dart';

/// Appointments, Week: one full-width card with columns Monday to Sunday
/// for the week containing the controller's anchor. Every column shares
/// one time range (1.2 px per minute). Closed days aren't stored (GAP),
/// so no column is drawn as closed.
class AppointmentsWeekView extends ConsumerWidget {
  const AppointmentsWeekView({super.key});

  static const EdgeInsets _cardPadding = EdgeInsets.fromLTRB(
    CruSpace.s12,
    CruSpace.s16,
    CruSpace.s16,
    CruSpace.s18,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      grid.add(WeekSessionGrid(
        startMinute: start,
        endMinute: end,
        days: days,
        groupsByDay: {
          for (final e in groups.entries) e.key: e.value.where(inSession).toList(),
        },
        today: today,
        now: now,
        onOpenVisit: (day, item) => ref
            .read(apptsControllerProvider.notifier)
            .openDay(day, visitId: item.id),
      ));
    }

    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: double.infinity,
        child: CruCard(
          padding: _cardPadding,
          semanticLabel: 'Week schedule',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WeekHeaderRow(days: days, today: today),
              const SizedBox(height: CruSpace.s10),
              const CruSeparator(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    top: WeekMetrics.gridTop,
                    bottom: WeekMetrics.gridBottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: grid,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
