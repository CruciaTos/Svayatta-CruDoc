import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/appt_status_style.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/month/appt_time_label.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/month/month_metrics.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_context_region.dart';

/// Agenda row height.
const double kAgendaRowHeight = CruSize.scheduleRow;

/// Agenda date header height.
const double kAgendaHeaderHeight = CruSize.tableHeader;

/// Date header: "Wednesday, 23 September", with "Today"/"Tomorrow" and the
/// day's count on the right.
class AgendaDateHeader extends StatelessWidget {
  const AgendaDateHeader({
    super.key,
    required this.date,
    required this.today,
    required this.count,
  });

  final DateTime date;
  final DateTime today;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final tag = date == today
        ? 'Today'
        : date == tomorrow
        ? 'Tomorrow'
        : null;
    return SizedBox(
      height: kAgendaHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: CruSpace.s8),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: DashFormat.dateLine(date),
                        style: CruType.callout.tint(c.label),
                      ),
                      if (tag != null)
                        TextSpan(
                          text: '  $tag',
                          style: CruType.subhead.w600.tint(c.accentText),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: CruSpace.s8),
              child: Text(
                DashFormat.plural(count, 'appointment'),
                style: CruType.subhead.tabular.tint(c.label2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One visit: time, name, reason and a status tag in the shared status
/// colours. Booked visits carry no tag.
class AgendaRow extends StatelessWidget {
  const AgendaRow({super.key, required this.item, required this.onTap});

  final ApptItem item;
  final VoidCallback onTap;

  static String? statusText(ApptItem item) => switch (item.status) {
    ApptStatus.done => 'Seen',
    ApptStatus.missed => 'Missed',
    ApptStatus.inConsultation => 'In consultation',
    ApptStatus.waiting =>
      item.waitMinutes == null
          ? 'Waiting'
          : 'Waiting · ${DashFormat.minutes(item.waitMinutes!)}',
    ApptStatus.booked => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final style = ApptStatusStyle.of(item.status, c);
    final tag = statusText(item);
    final missed = item.status == ApptStatus.missed;
    // Seen or missed: the home-visit marks go grey.
    final quiet = item.status == ApptStatus.done || missed;
    final nameColor = switch (item.status) {
      ApptStatus.done || ApptStatus.missed => style.text,
      _ => c.label,
    };
    return ApptContextRegion(
      item: item,
      child: CruPressable(
        onTap: onTap,
        scaleOnPress: false,
        semanticLabel:
            '${DashFormat.time(item.start)}, ${item.name}'
            '${item.reason == null ? '' : ', ${item.reason}'}'
            '${tag == null ? '' : ', $tag'}',
        builder: (context, hovered) => Container(
          height: kAgendaRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.callout
                                .tint(nameColor)
                                .copyWith(
                                  decoration: missed
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: nameColor,
                                ),
                          ),
                        ),
                        if (item.isHomeVisit) ...[
                          const SizedBox(width: CruSpace.s6),
                          CruIcon(
                            CruIcons.home,
                            size: 14,
                            strokeWidth: 2.2,
                            color: quiet ? c.label3 : c.homeVisit,
                          ),
                        ],
                      ],
                    ),
                    if (item.detailLine != null)
                      Text(
                        item.detailLine!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.caption.tint(c.label2),
                      ),
                  ],
                ),
              ),
              if (item.isHomeVisit) ...[
                const SizedBox(width: CruSpace.s12),
                CruPill(
                  text: 'Visit',
                  icon: CruIcons.home,
                  background: quiet ? c.inset : c.accentTint,
                  foreground: quiet ? c.label3 : c.homeVisit,
                ),
              ],
              if (tag != null) ...[
                SizedBox(width: item.isHomeVisit ? CruSpace.s8 : CruSpace.s12),
                CruPill(
                  text: tag,
                  background: style.fill,
                  foreground: style.text,
                  icon: style.check ? CruIcons.check : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
