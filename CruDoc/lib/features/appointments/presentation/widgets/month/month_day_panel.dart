import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'appt_time_label.dart';
import 'month_metrics.dart';

/// The Month view's right day panel (384 px): eyebrow, date, summary, one
/// row per appointment, "Book on this day" and "Open day". The open-slot
/// count needs working hours and slot length (GAP), so the summary is
/// "9 booked · first at 9:30 AM".
class MonthDayPanel extends ConsumerWidget {
  const MonthDayPanel({super.key, required this.date});

  /// Date only.
  final DateTime date;

  static String eyebrow(DateTime date, DateTime today) {
    if (date == today) return 'Today';
    if (date == DateTime(today.year, today.month, today.day + 1)) {
      return 'Tomorrow';
    }
    return DashFormat.weekday(date);
  }

  /// Past: "11 seen · 1 missed". Today and future: "9 booked · first at
  /// 9:30 AM".
  static String summary(ApptDayCounts counts, DateTime date, DateTime today) {
    if (counts.appointments == 0) {
      return date.isBefore(today) ? 'No visits' : 'Nothing booked yet';
    }
    if (date.isBefore(today)) {
      final missed = counts.missed > 0 ? ' · ${counts.missed} missed' : '';
      return '${counts.seen} seen$missed';
    }
    final first = counts.firstStart == null
        ? ''
        : ' · first at ${DashFormat.time(counts.firstStart!)}';
    return '${counts.appointments} booked$first';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final today = ApptsBuilder.dateOnly(ref.watch(apptsNowProvider));
    final items = ref.watch(apptDayItemsProvider(date)).value;
    final counts = ref.watch(apptDayCountsProvider(date)).value;
    final controller = ref.read(apptsControllerProvider.notifier);
    final canBook = !date.isBefore(today);

    return CruCard(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s20,
        CruSpace.s20,
        CruSpace.s18,
      ),
      semanticLabel: DashFormat.dateLine(date),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            eyebrow(date, today),
            style: CruType.subhead.w600.tint(c.accentText),
          ),
          Text(
            DashFormat.dateLine(date),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CruType.title2.tint(c.label),
          ),
          SizedBox(
            height: CruType.subhead.fontSize! * CruType.subhead.height!,
            child: counts == null
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(width: 160, height: 12),
                  )
                : Text(
                    summary(counts, date, today),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.subhead.tabular.tint(c.label2),
                  ),
          ),
          const SizedBox(height: CruSpace.s12),
          const CruSeparator(),
          const SizedBox(height: CruSpace.s12),
          Flexible(
            child: items == null
                ? const _RowsSkeleton()
                : items.isEmpty
                    ? Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: CruSpace.s12),
                        child: Text(
                          'No appointments on this day.',
                          style: CruType.subhead.tint(c.label2),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        itemExtent: MonthMetrics.panelRow + 1,
                        itemBuilder: (context, i) => Column(
                          children: [
                            if (i > 0)
                              const CruSeparator(
                                indent: CruSpace.s4 +
                                    MonthMetrics.timeColumn +
                                    CruSpace.s12,
                              )
                            else
                              const SizedBox(height: 1),
                            MonthPanelRow(
                              item: items[i],
                              onTap: () => controller.openDay(
                                date,
                                visitId: items[i].id,
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
          const SizedBox(height: CruSpace.s16),
          // Booking is offered for today and later only; on a past day
          // "Open day" fills the row.
          canBook
              ? Row(
                  children: [
                    Expanded(
                      child: CruButton(
                        label: 'Book on this day',
                        kind: CruButtonKind.tinted,
                        expand: true,
                        onPressed: () => ApptActions.newAppointment(
                          context,
                          ref,
                          day: date,
                        ),
                      ),
                    ),
                    const SizedBox(width: CruSpace.s10),
                    CruButton(
                      label: 'Open day',
                      kind: CruButtonKind.inset,
                      onPressed: () => controller.openDay(date),
                    ),
                  ],
                )
              : CruButton(
                  label: 'Open day',
                  kind: CruButtonKind.inset,
                  expand: true,
                  onPressed: () => controller.openDay(date),
                ),
        ],
      ),
    );
  }
}

/// One appointment in the day panel: time with a small AM/PM, name,
/// reason. Clicking it opens the Day with that visit selected.
class MonthPanelRow extends StatelessWidget {
  const MonthPanelRow({super.key, required this.item, required this.onTap});

  final ApptItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final missed = item.status == ApptStatus.missed;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: '${DashFormat.time(item.start)}, ${item.name}'
          '${item.reason == null ? '' : ', ${item.reason}'}',
      builder: (context, hovered) => Container(
        height: MonthMetrics.panelRow,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : Colors.transparent,
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            SizedBox(
              width: MonthMetrics.timeColumn,
              child: ApptTimeLabel(item.start),
            ),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.callout
                        .tint(missed ? c.label3 : c.label)
                        .copyWith(
                          decoration:
                              missed ? TextDecoration.lineThrough : null,
                          decorationColor: c.label3,
                        ),
                  ),
                  if (item.reason != null)
                    Text(
                      item.reason!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.caption.tint(c.label2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 4; i++)
          const SizedBox(
            height: MonthMetrics.panelRow,
            child: Row(
              children: [
                SizedBox(
                  width: MonthMetrics.timeColumn,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(width: 56, height: 12),
                  ),
                ),
                SizedBox(width: CruSpace.s12),
                Expanded(child: SkeletonBox(height: 12)),
              ],
            ),
          ),
      ],
    );
  }
}
