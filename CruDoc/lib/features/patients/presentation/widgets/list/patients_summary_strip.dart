import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_reminders_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The amber strip above a work-through list: "₹78,400 outstanding ·
/// 12 patients" with Send reminders, or "7 patients overdue · longest
/// overdue 41 days" with Message all.
class PatientsSummaryStrip extends StatelessWidget {
  const PatientsSummaryStrip.balance({
    super.key,
    required BalanceStripData this.balance,
    required this.rows,
  }) : followUp = null;

  const PatientsSummaryStrip.followUp({
    super.key,
    required FollowUpStripData this.followUp,
    required this.rows,
  }) : balance = null;

  final BalanceStripData? balance;
  final FollowUpStripData? followUp;

  /// Everyone in the current filter (the reminders sheet lists them).
  final List<PatientSummary> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final String headline;
    final String suffix;
    final String? detail;
    final String action;
    final RemindersKind kind;
    if (balance != null) {
      headline = PatientFormat.rupees(balance!.total);
      suffix = ' outstanding';
      // "oldest due D days" is a GAP: balances carry no due date.
      detail = DashFormat.plural(balance!.patients, 'patient');
      action = 'Send reminders';
      kind = RemindersKind.payment;
    } else {
      final f = followUp!;
      headline = DashFormat.plural(f.patients, 'patient');
      suffix = ' overdue';
      detail = f.longestDays > 0
          ? 'longest overdue ${PatientFormat.days(f.longestDays)}'
          : null;
      action = 'Message all';
      kind = RemindersKind.followUp;
    }

    final strip = Container(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s14,
        CruSpace.s14,
        CruSpace.s14,
      ),
      decoration: ShapeDecoration(
        color: c.amberTint,
        shape: cruShape(CruRadius.strip),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: CruSpace.s12,
              runSpacing: CruSpace.s2,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: headline,
                        style: CruType.title2.tabular.tint(c.label),
                      ),
                      TextSpan(
                        text: suffix,
                        style: CruType.text.w500.tint(c.label2),
                      ),
                    ],
                  ),
                ),
                if (detail != null)
                  Padding(
                    // Sits on the headline's baseline.
                    padding: const EdgeInsets.only(bottom: CruSpace.s2),
                    child: Text(
                      detail,
                      style: CruType.subhead.tabular.tint(c.label2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s16),
          CruCapsuleButton(
            label: action,
            kind: CruCapsuleKind.surface,
            icon: CruIcons.whatsapp,
            height: CruSize.stripButton,
            large: true,
            onPressed: () => showPatientsRemindersSheet(
              context,
              kind: kind,
              rows: rows,
            ),
          ),
        ],
      ),
    );

    // Fades in from 4 px above; instant under reduced motion.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: CruMotion.of(context, CruMotion.strip),
      curve: CruMotion.curve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -CruSpace.s4 * (1 - t)),
          child: child,
        ),
      ),
      child: strip,
    );
  }
}
