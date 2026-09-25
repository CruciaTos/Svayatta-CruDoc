import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/wrap_up_builder.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/side_cards.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Evening only; replaces Needs attention and Insights.
///
/// Shows what the records support: AI Scribe drafts still to review and
/// tomorrow's bookings. "Close the day" is not shown because no end-of-day
/// workflow exists to run (GAP).
class WrapUpCard extends StatelessWidget {
  const WrapUpCard({super.key, required this.data, required this.navigate});

  final WrapUpData data;
  final ValueChanged<int> navigate;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final left = data.patientsLeft;
    return CruCard(
      semanticLabel: 'Wrap up the day',
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Wrap up the day',
                      style: CruType.headline.tint(c.label)),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  left == 0
                      ? 'Everyone on the list has been seen'
                      : '${DashFormat.plural(left, 'patient')} left',
                  style: CruType.subhead.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
          ...withSeparators([
            if (data.draftNames.isNotEmpty)
              ActionRow(
                icon: CruIcons.pen,
                tone: CruTileTone.accent,
                title: '${DashFormat.plural(data.draftNames.length, 'scribe note')}'
                    ' to review',
                subtitle: DashFormat.names(data.draftNames, max: 3),
                actionLabel: 'Review',
                onAction: () => navigate(DesktopTab.scribe),
              ),
            if (data.tomorrowCount > 0)
              ActionRow(
                icon: CruIcons.calendar,
                // Teal is reserved for lab results, so this stays neutral.
                tone: CruTileTone.neutral,
                title: 'Tomorrow · ${data.tomorrowCount} booked',
                subtitle: 'First at ${DashFormat.time(data.tomorrowFirst!)}',
                actionLabel: 'View',
                onAction: () => navigate(DesktopTab.appointments),
              ),
          ]),
        ],
      ),
    );
  }
}
