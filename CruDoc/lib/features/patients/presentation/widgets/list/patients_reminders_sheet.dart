import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum RemindersKind { payment, followUp }

/// Lists everyone in a work-through filter with a WhatsApp capsule each.
/// Every message opens in WhatsApp for review: nothing is sent in bulk.
Future<void> showPatientsRemindersSheet(
  BuildContext context, {
  required RemindersKind kind,
  required List<PatientSummary> rows,
}) {
  final targets = rows
      .where(
        (s) => kind == RemindersKind.payment ? s.hasBalance : s.followUpOverdue,
      )
      .toList();
  return showDialog<void>(
    context: context,
    builder: (_) => _RemindersDialog(kind: kind, rows: targets),
  );
}

class _RemindersDialog extends ConsumerWidget {
  const _RemindersDialog({required this.kind, required this.rows});

  final RemindersKind kind;
  final List<PatientSummary> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final now = ref.watch(dashboardNowProvider);
    final clinic = ref.watch(doctorIdentityProvider).clinicName;
    final title = kind == RemindersKind.payment
        ? 'Send payment reminders'
        : 'Message overdue patients';

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: c.surface.withValues(alpha: 0),
      shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: CruSize.remindersDialog,
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: CruType.title2.tint(c.label),
                          ),
                        ),
                        const SizedBox(height: CruSpace.s4),
                        Text(
                          'Each message opens in WhatsApp so you can check '
                          'it before sending.',
                          style: CruType.subhead.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CruSpace.s14),
                  CruSquareButton(
                    icon: CruIcons.close,
                    iconSize: 16,
                    strokeWidth: 2.2,
                    semanticLabel: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: CruSpace.s16),
                  child: Text(
                    'No one to remind right now.',
                    style: CruType.text.tint(c.label2),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    primary: false,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const CruSeparator(
                      indent: CruSize.monogramList + CruSpace.s12,
                    ),
                    itemBuilder: (context, i) => _ReminderRow(
                      summary: rows[i],
                      kind: kind,
                      now: now,
                      clinicName: clinic,
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

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.summary,
    required this.kind,
    required this.now,
    required this.clinicName,
  });

  final PatientSummary summary;
  final RemindersKind kind;
  final DateTime now;
  final String? clinicName;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = summary;
    final hasPhone = s.patient.phone.trim().isNotEmpty;
    final String info;
    if (kind == RemindersKind.payment) {
      info = '${PatientFormat.rupees(s.balance)} due';
    } else {
      final since = s.overdueSince!;
      info = 'Overdue ${PatientFormat.days(PatientsBuilder.daysSince(since, now))}'
          ' · since ${PatientFormat.weekdayDate(since)}';
    }
    return SizedBox(
      height: CruSize.compactRow,
      child: Row(
        children: [
          CruMonogram(
            name: s.name,
            size: CruSize.monogramList,
            background: c.inset,
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  style: CruType.row.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  hasPhone ? info : '$info · no phone number',
                  style: CruType.subhead.w500.tabular.tint(c.amberText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruCapsuleButton(
            label: 'WhatsApp',
            icon: CruIcons.whatsapp,
            onPressed: !hasPhone
                ? null
                : () => PatientActions.whatsApp(
                      context,
                      s.patient,
                      message: kind == RemindersKind.payment
                          ? PatientActions.paymentReminderText(
                              s,
                              clinicName: clinicName,
                            )
                          : PatientActions.followUpReminderText(
                              s,
                              clinicName: clinicName,
                            ),
                    ),
          ),
        ],
      ),
    );
  }
}
