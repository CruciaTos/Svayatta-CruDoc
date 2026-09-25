import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Pending payment actions: Mark paid and WhatsApp reminders.
abstract final class PendingActions {
  /// Confirms, then settles every pending row of [group] the same way
  /// the old Revenue screen did (`markVisitationPaymentPaid`, which also
  /// flips a linked visit to paid and records the income).
  static Future<void> markPaid(
    BuildContext context,
    WidgetRef ref,
    PendingGroup group,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _MarkPaidDialog(group: group),
    );
    if (ok != true) return;

    final visits = ref.read(visitRepositoryProvider);
    var settled = 0;
    Object? error;
    for (final row in group.rows) {
      try {
        await visits.markVisitationPaymentPaid(row.id);
        settled++;
      } catch (e) {
        error = e;
      }
    }
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(
        error == null
            ? '${group.name} · ${DashFormat.rupees(group.total)} marked paid'
            : settled == 0
                ? "Couldn't mark ${group.name}'s payment as paid."
                : 'Marked $settled of ${group.rows.length} payments paid. '
                    "The rest couldn't be updated.",
      ),
    ));
  }

  /// Lists the patients who can get a WhatsApp reminder, one capsule
  /// each. Every message opens in WhatsApp for review.
  static Future<void> sendReminders(
    BuildContext context,
    List<PendingGroup> groups,
  ) {
    final targets = groups.where((g) => g.canRemind).toList();
    return showDialog<void>(
      context: context,
      builder: (_) => _RemindersDialog(groups: targets),
    );
  }

  static String reminderText(PendingGroup g, {String? clinicName}) {
    final first = g.name.trim().split(RegExp(r'\s+')).first;
    final clinic = (clinicName == null || clinicName.trim().isEmpty)
        ? 'the clinic'
        : clinicName.trim();
    return 'Hello $first, a friendly reminder from $clinic that '
        '${DashFormat.rupees(g.total)} is due. Thank you.';
  }
}

class _MarkPaidDialog extends StatelessWidget {
  const _MarkPaidDialog({required this.group});
  final PendingGroup group;

  static String _what(String description) {
    final (what, _) = RevenueBuilder.splitDescription(description);
    return what.isEmpty ? 'Payment' : RevenueBuilder.sentence(what);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final g = group;
    return PatientDialog(
      title: 'Mark paid',
      cancelLabel: 'Cancel',
      confirmLabel: 'Mark ${DashFormat.rupees(g.total)} paid',
      onConfirm: () => Navigator.of(context).pop(true),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${g.name} · ${DashFormat.rupees(g.total)} due',
            style: CruType.text.tabular.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s12),
          for (var i = 0; i < g.rows.length; i++) ...[
            if (i > 0) const CruSeparator(),
            SizedBox(
              height: CruSize.collapsedRow,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_what(g.rows[i].description)}'
                      ' · ${DateFormat('d MMM').format(g.rows[i].date)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.text.tabular.tint(c.label),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Text(
                    DashFormat.rupees(g.rows[i].amount),
                    style: CruType.callout.tabular.tint(c.label),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemindersDialog extends ConsumerWidget {
  const _RemindersDialog({required this.groups});
  final List<PendingGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final clinic = ref.watch(doctorIdentityProvider).clinicName;
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
                            'Send payment reminders',
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
              if (groups.isEmpty)
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
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const CruSeparator(
                      indent: CruSize.monogramList + CruSpace.s12,
                    ),
                    itemBuilder: (context, i) =>
                        _ReminderRow(group: groups[i], clinicName: clinic),
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
  const _ReminderRow({required this.group, required this.clinicName});

  final PendingGroup group;
  final String? clinicName;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final g = group;
    return SizedBox(
      height: CruSize.compactRow,
      child: Row(
        children: [
          CruMonogram(
            name: g.name,
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
                  g.name,
                  style: CruType.row.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${DashFormat.rupees(g.total)} due · ${RevenueBuilder.age(g.ageDays)}',
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
            onPressed: () => PatientActions.whatsApp(
              context,
              g.patient!,
              message: PendingActions.reminderText(g, clinicName: clinicName),
            ),
          ),
        ],
      ),
    );
  }
}
