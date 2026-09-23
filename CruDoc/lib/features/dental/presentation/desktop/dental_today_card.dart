import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/data/models/sterilization_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The dentist's dashboard card: has today's autoclave run been logged
/// (and did it pass), and how much treatment is waiting for a yes.
class DentalTodayCard extends ConsumerWidget {
  const DentalTodayCard({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final now = DateTime.now();
    final logs = ref.watch(clinicSterilizationProvider).value;
    final plans = ref.watch(clinicTreatmentPlansProvider).value;

    // Sterilization.
    final today = logs?.where((l) => DentalFormat.sameDay(l.cycleDate, now)).toList()
      ?..sort((a, b) => b.cycleDate.compareTo(a.cycleDate));
    final last = today == null || today.isEmpty ? null : today.first;
    final lastResult = last == null ? null : SterilizationResult.fromString(last.result);
    final (String steriText, Color steriTone) = switch (logs) {
      null => ('', c.label2),
      _ when last == null => ('No cycle logged today', c.amberText),
      _ when lastResult == SterilizationResult.fail => (
          'Last cycle failed at ${DentalFormat.time(last.cycleDate)} · re-run the load',
          c.redText,
        ),
      _ => (
          '${DashFormat.plural(today!.length, 'cycle')} today · last '
              '${sterilizationWord(last.result)} at ${DentalFormat.time(last.cycleDate)}',
          c.label2,
        ),
    };

    // Plans waiting for a yes.
    final proposed = plans
            ?.where((i) =>
                !i.isDeleted &&
                TreatmentPlanItemStatus.fromString(i.status) == TreatmentPlanItemStatus.proposed)
            .toList() ??
        const <TreatmentPlanLineItemModel>[];
    final patients = proposed.map((i) => i.patientId).toSet().length;
    final sum = proposed.fold(0.0, (t, i) => t + i.estimatedPrice);
    final planText = plans == null
        ? ''
        : proposed.isEmpty
            ? 'Nothing waiting for a yes'
            : '${DashFormat.rupees(sum)} awaiting a yes · ${DashFormat.plural(patients, 'patient')}';

    return CruCard(
      semanticLabel: 'Dental clinic',
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          _Row(
            icon: DentalIcons.shield,
            title: 'Sterilization',
            detail: steriText,
            tone: steriTone,
            onTap: () => onNavigate(DesktopTab.sterilization),
          ),
          const CruSeparator(indent: 12 + 36 + 12),
          _Row(
            icon: DentalIcons.plan,
            title: 'Treatment plans',
            detail: planText,
            tone: c.label2,
            onTap: () => onNavigate(DesktopTab.treatmentPlans),
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
