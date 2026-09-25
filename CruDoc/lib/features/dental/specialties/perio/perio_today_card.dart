import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/specialties/perio/perio_patients_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The periodontist's dashboard card: who is due for maintenance, who
/// has active disease, and how many exams this month.
class PerioTodayCard extends ConsumerWidget {
  const PerioTodayCard({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final o = ref.watch(perioOverviewProvider);
    final month = DateFormat('MMMM').format(DateTime.now());

    final maintenance = o?.maintenanceDue.length;
    final active = o?.activeDisease;
    final exams = o?.examsThisMonth;

    return CruCard(
      semanticLabel: 'Perio clinic',
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          _Row(
            icon: RecIcons.recall,
            title: 'Maintenance due',
            detail: switch (maintenance) {
              null => '',
              0 => 'None in the next 14 days',
              final n => '${DashFormat.plural(n, 'recall')} due in 14 days or overdue',
            },
            tone: (maintenance ?? 0) > 0 ? c.amberText : c.label2,
            onTap: () => onNavigate(DesktopTab.recalls),
          ),
          const CruSeparator(indent: 12 + 36 + 12),
          _Row(
            icon: RecIcons.perio,
            title: 'Active disease',
            detail: switch (active) {
              null => '',
              0 => 'No stage III/IV or 6 mm pockets',
              final n => '${DashFormat.plural(n, 'patient')} · stage III/IV or pockets ≥ 6 mm',
            },
            tone: c.label2,
            onTap: () => onNavigate(DesktopTab.perioPatients),
          ),
          const CruSeparator(indent: 12 + 36 + 12),
          _Row(
            icon: CruIcons.calendar,
            title: 'Exams this month',
            detail: exams == null
                ? ''
                : '${DashFormat.plural(exams, 'perio exam')} in $month',
            tone: c.label2,
            onTap: () => onNavigate(DesktopTab.perioPatients),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.detail,
    required this.tone,
    required this.onTap,
  });

  final CruIconData icon;
  final String title;
  final String detail;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DentalListRow(
      semanticLabel: '$title. $detail',
      onTap: onTap,
      minHeight: 60,
      child: Row(
        children: [
          CruIconTile(icon: icon, tone: CruTileTone.accent),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.callout.w600.tint(c.label)),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tabular.tint(tone),
                ),
              ],
            ),
          ),
          CruIcon(CruIcons.chevronRight, size: 18, color: c.label3),
        ],
      ),
    );
  }
}
