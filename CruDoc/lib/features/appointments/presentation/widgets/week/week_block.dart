import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/appt_status_style.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'week_metrics.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_context_region.dart';

/// One visit in the Week grid: 22 px tall, "First L." in the status
/// colours; home visits add a house after the name. Clicking it opens the Day
/// view with the visit selected.
class WeekBlock extends StatelessWidget {
  const WeekBlock({super.key, required this.item, required this.onTap});

  final ApptItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final style = ApptStatusStyle.of(item.status, c);
    final time = DashFormat.time(item.start);
    final reason = item.reason == null ? '' : ' · ${item.reason}';
    return ApptContextRegion(
      item: item,
      child: CruPressable(
        onTap: onTap,
        scaleOnPress: false,
        semanticLabel:
            '${item.name}, $time${item.isHomeVisit ? ', home visit' : ''}',
        tooltip: ['${item.name} · $time$reason', ?item.homeAddress].join('\n'),
        builder: (context, hovered) => Container(
          height: WeekMetrics.blockHeight,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s6),
          alignment: Alignment.centerLeft,
          decoration: ShapeDecoration(
            color: hovered ? cruHoverShade(style.fill, c) : style.fill,
            shape: cruShape(
              CruRadius.bar,
              side: style.border == null
                  ? BorderSide.none
                  : BorderSide(color: style.border!),
            ),
          ),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  item.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: CruType.micro.w600
                      .tint(style.text)
                      .copyWith(
                        decoration: style.strike
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: style.text,
                      ),
                ),
              ),
              if (item.isHomeVisit) ...[
                const SizedBox(width: CruSpace.s4),
                CruIcon(
                  CruIcons.home,
                  size: 11,
                  strokeWidth: 2.4,
                  color: style.check || style.strike ? style.text : c.homeVisit,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
