import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/appt_status_pill.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The selected appointment in the Day right column: status and time,
/// who, why, allergy, and Reschedule / Cancel / Open patient.
class SelectedAppointmentCard extends ConsumerWidget {
  const SelectedAppointmentCard({super.key, required this.item});

  final ApptItem item;

  /// The 44 px monogram (no shared token; NEEDS.md).
  static const double _monogram = 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final now = ref.watch(apptsNowProvider);
    final patient = item.patient;
    final allergies = patient == null
        ? null
        : KnownAllergies.parse(
            ref
                .watch(homeopathyCaseSheetProvider(patient.id))
                .value
                ?.medicalHistory
                .allergies,
          );
    final canChange = item.status == ApptStatus.booked ||
        item.status == ApptStatus.waiting ||
        item.status == ApptStatus.missed;
    final canCancel = item.status == ApptStatus.booked ||
        item.status == ApptStatus.waiting;

    return CruCard(
      semanticLabel: 'Selected appointment',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s22,
        CruSpace.s20,
        CruSpace.s22,
        CruSpace.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ApptStatusPill(item: item),
              const Spacer(),
              Text(
                ApptFormat.range(item.start, item.end),
                style: CruType.subhead.tabular.tint(c.label2),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s14),
          Row(
            children: [
              CruMonogram(name: item.name, size: _monogram),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: CruType.headline.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      ApptFormat.identityLine(item, now),
                      style: CruType.subhead.tabular.tint(c.label2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.reason != null) ...[
            const SizedBox(height: CruSpace.s14),
            Text(item.reason!, style: CruType.text.tint(c.label)),
          ],
          if (allergies != null && !allergies.none) ...[
            const SizedBox(height: CruSpace.s14),
            CruInfoPill(
              text: 'Allergic to ${allergies.text}',
              icon: CruIcons.warning,
              tone: CruInfoPillTone.allergy,
            ),
          ],
          const SizedBox(height: CruSpace.s14),
          Row(
            children: [
              if (canChange) ...[
                CruButton(
                  label: 'Reschedule',
                  kind: CruButtonKind.inset,
                  onPressed: () => ApptActions.reschedule(context, ref, item),
                ),
                const SizedBox(width: CruSpace.s8),
              ],
              if (canCancel)
                CruButton(
                  label: 'Cancel',
                  kind: CruButtonKind.inset,
                  onPressed: () => _cancel(context, ref),
                ),
              const Spacer(),
              if (patient != null)
                CruLink(
                  label: 'Open patient',
                  trailing: CruIcon(
                    CruIcons.chevronRight,
                    size: 15,
                    strokeWidth: 2,
                    color: c.accentText,
                  ),
                  onPressed: () => DashboardActions.openPatient(context, patient),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Read before awaiting: this card may be gone when the dialog closes.
    final repo = ref.read(visitRepositoryProvider);
    final controller = ref.read(apptsControllerProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PatientDialog(
        title: 'Cancel this appointment?',
        cancelLabel: 'Keep it',
        confirmLabel: 'Cancel appointment',
        onConfirm: () => Navigator.of(ctx).pop(true),
        body: Text(
          '${item.name} · ${ApptFormat.range(item.start, item.end)}, '
          '${ApptFormat.dateLine(item.start)}',
          style: CruType.text.tabular.tint(ctx.cru.label2),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await repo.cancelVisit(item.id);
      controller.select(null);
      messenger?.showSnackBar(
        SnackBar(
          content: Text("Cancelled ${item.name}'s appointment"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text("Couldn't cancel the appointment. Try again."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
