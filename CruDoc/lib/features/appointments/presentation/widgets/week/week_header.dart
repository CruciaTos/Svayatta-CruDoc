import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'week_metrics.dart';

/// Column headers Mon–Sun above the Week grid, lined up with its columns.
class WeekHeaderRow extends StatelessWidget {
  const WeekHeaderRow({super.key, required this.days, required this.today});

  final List<DateTime> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(width: WeekMetrics.gutter),
        for (final d in days)
          Expanded(child: WeekDayHeader(date: d, today: today)),
      ],
    );
  }
}

/// Weekday, date (today in a filled accent circle) and the count line.
/// Clicking it opens that Day.
class WeekDayHeader extends ConsumerWidget {
  const WeekDayHeader({super.key, required this.date, required this.today});

  final DateTime date;
  final DateTime today;

  /// Past: "11 seen · 1 missed". Today and future: "13 booked" (today
  /// counts every visit that day). Nothing when the day is empty.
  static String countLine(ApptDayCounts? counts, DateTime date, DateTime today) {
    if (counts == null || counts.appointments == 0) return '';
    if (date.isBefore(today)) {
      final missed = counts.missed > 0 ? ' · ${counts.missed} missed' : '';
      return '${counts.seen} seen$missed';
    }
    return '${counts.appointments} booked';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final counts = ref.watch(apptDayCountsProvider(date)).value;
    final isToday = date == today;
    final line = countLine(counts, date, today);
    final overlap = counts?.hasUnsortedOverlap ?? false;

    return CruPressable(
      onTap: () =>
          ref.read(apptsControllerProvider.notifier).openDay(date),
      scaleOnPress: false,
      semanticLabel:
          '${DashFormat.dateLine(date)}${line.isEmpty ? '' : ', $line'}. Open day',
      builder: (context, hovered) => DecoratedBox(
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : Colors.transparent,
          shape: cruShape(CruRadius.control),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('E').format(date),
                style: CruType.groupLabel
                    .tint(isToday ? c.accentText : c.label2),
              ),
              const SizedBox(height: CruSpace.s2),
              SizedBox(
                height: WeekMetrics.dateCircle,
                child: Center(
                  child: isToday
                      ? Container(
                          width: WeekMetrics.dateCircle,
                          height: WeekMetrics.dateCircle,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${date.day}',
                            style: CruType.title2.tabular.tint(c.onAccent),
                          ),
                        )
                      : Text(
                          '${date.day}',
                          style: CruType.title2.tabular.tint(c.label),
                        ),
                ),
              ),
              const SizedBox(height: CruSpace.s2),
              SizedBox(
                height: CruType.caption.fontSize! * CruType.caption.height!,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.caption.tabular.tint(c.label3),
                      ),
                    ),
                    if (overlap) ...[
                      const SizedBox(width: CruSpace.s4),
                      const CruStatusDot(
                        CruDotKind.waiting,
                        size: CruSize.smallDot,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
