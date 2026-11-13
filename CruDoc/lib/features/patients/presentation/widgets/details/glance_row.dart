import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/visits_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Phone Patient details' glance card: one card, three cells (Last, Next,
/// Due) with hairline dividers. Last is the latest visit, Next is what
/// happens next (the booked visit, else a dentist's recall, else "Book"),
/// Due is what the patient owes ("Paid up" when nothing).
class PatientGlanceCard extends ConsumerWidget {
  const PatientGlanceCard({
    super.key,
    required this.summary,
    required this.now,
    required this.due,
    required this.dueCount,
    required this.isDentist,
    required this.onOpenVisit,
    required this.onNewVisit,
    required this.onRecordPayment,
    required this.showDue,
    required this.showClinical,
  });

  final PatientSummary summary;
  final DateTime now;

  /// What the patient owes (same total as the Payments card).
  final double due;

  /// How many things make up [due].
  final int dueCount;
  final bool isDentist;
  final ValueChanged<Visit> onOpenVisit;

  /// Null when the person can't book: Next is then plain text.
  final VoidCallback? onNewVisit;

  /// Null when the person can't take payments.
  final VoidCallback? onRecordPayment;

  /// Billing roles only; without it the card is two cells.
  final bool showDue;

  /// Names the last visit's treatment (clinical roles only).
  final bool showClinical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final last = summary.lastVisit;
    final next = summary.upcoming(now).firstOrNull;
    final recall = isDentist
        ? patientRecallInfo(
            ref
                .watch(
                  patientRecordsProvider((
                    patientId: summary.id,
                    kind: RecKind.recall,
                  )),
                )
                .value,
            now: now,
          )
        : null;

    final _Cell lastCell = last == null
        ? const _Cell(
            label: 'Last',
            value: '—',
            caption: 'No visits yet',
            semantic: 'Last visit: none yet',
          )
        : _Cell(
            label: 'Last',
            value: DashFormat.shortDate(last.scheduledStart),
            caption: showClinical ? visitTitle(last) : null,
            semantic:
                'Last visit ${DashFormat.shortDate(last.scheduledStart)}'
                '${showClinical ? ', ${visitTitle(last)}' : ''}. Open it.',
            onTap: () => onOpenVisit(last),
          );

    final _Cell nextCell;
    if (next != null) {
      final time = DashFormat.time(next.scheduledStart);
      nextCell = _Cell(
        label: 'Next',
        value: PatientFormat.day(next.scheduledStart, now),
        valueColor: c.accentText,
        caption: showClinical ? '$time · ${visitTitle(next)}' : time,
        semantic:
            'Next visit ${PatientFormat.dayTimeInline(next.scheduledStart, now)}.'
            ' Open it.',
        onTap: () => onOpenVisit(next),
      );
    } else if (recall != null && recall.due != null) {
      nextCell = _Cell(
        label: 'Next',
        value: DashFormat.shortDate(recall.due!),
        valueColor: recall.overdue ? c.amberText : null,
        caption: recall.overdue ? 'Recall overdue' : 'Recall',
        semantic: '${recall.label}. Change it.',
        onTap: () => showSetRecallDialog(
          context,
          patient: summary.patient,
          existing: recall.existing,
        ),
      );
    } else if (onNewVisit != null) {
      nextCell = _Cell(
        label: 'Next',
        value: 'Book',
        valueColor: c.accentText,
        leading: CruIcon(
          CruIcons.plus,
          size: 14,
          strokeWidth: 2.2,
          color: c.accentText,
        ),
        caption: 'No visit booked',
        semantic: 'No visit booked. Book a visit.',
        onTap: onNewVisit,
      );
    } else {
      nextCell = const _Cell(
        label: 'Next',
        value: '—',
        caption: 'No visit booked',
        semantic: 'No visit booked',
      );
    }

    final _Cell dueCell = due > 0
        ? _Cell(
            label: 'Due',
            value: PatientFormat.rupees(due),
            valueColor: c.amberText,
            caption: DashFormat.plural(dueCount, 'item'),
            semantic: '${PatientFormat.rupees(due)} due. Record a payment.',
            onTap: onRecordPayment,
          )
        : _Cell(
            label: 'Due',
            value: 'Paid up',
            leading: CruIcon(
              CruIcons.check,
              size: 14,
              strokeWidth: 2.4,
              color: c.greenText,
            ),
            semantic: 'Paid up. Nothing due.',
          );

    final cells = [lastCell, nextCell, if (showDue) dueCell];
    return MobileCard(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) Container(width: 1, color: c.separator),
              Expanded(child: cells[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// One cell: label, value, caption. Pressable when it has [onTap].
class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.value,
    required this.semantic,
    this.caption,
    this.valueColor,
    this.leading,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final String semantic;
  final Color? valueColor;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: semantic,
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              style: MobileType.micro
                  .tint(c.label3)
                  .copyWith(letterSpacing: 0.4),
            ),
            const SizedBox(height: CruSpace.s4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: CruSpace.s4),
                  ],
                  Text(
                    value,
                    maxLines: 1,
                    style: MobileType.callout.w600.tabular.tint(
                      valueColor ?? c.label,
                    ),
                  ),
                ],
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: CruSpace.s2),
              Text(
                caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MobileType.caption.tint(c.label2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
