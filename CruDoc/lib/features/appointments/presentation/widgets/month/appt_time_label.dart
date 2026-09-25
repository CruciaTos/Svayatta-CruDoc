import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "9:30" with a small tertiary "AM", as in the Month day panel. Also used
/// by the Agenda rows.
class ApptTimeLabel extends StatelessWidget {
  const ApptTimeLabel(this.time, {super.key, this.color});

  final DateTime time;

  /// Colour of the "9:30" part; label by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (hm, ampm) = DashFormat.timeParts(time);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: hm,
            style: CruType.callout.tabular.tint(color ?? c.label),
          ),
          TextSpan(
            text: ' $ampm',
            style: CruType.micro.tint(c.label3),
          ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      semanticsLabel: DashFormat.time(time),
    );
  }
}
