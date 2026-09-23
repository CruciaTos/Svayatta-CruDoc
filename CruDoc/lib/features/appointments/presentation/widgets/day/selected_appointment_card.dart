import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/appt_status_pill.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/visits/home_visit_panel.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The selected appointment in the Day right column: status and time,
/// who, why, allergy, and Reschedule / Cancel / Open patient. An
/// appointment for several patients (seen together) lists each of them,
/// with their own reason and allergies, and can be billed together.
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
    final canChange = ApptActions.canReschedule(item);
    final canCancel = ApptActions.canCancel(item);
    final canAdd = canChange && item.patientCount < kMaxGroupPatients;

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
              if (item.isHomeVisit) ...[
                const SizedBox(width: CruSpace.s8),
                CruPill(
                  text: 'Visit',
                  icon: CruIcons.home,
                  background: c.accentWash,
                  foreground: c.homeVisit,
                ),
              ],
              if (item.isGroup) ...[
                const SizedBox(width: CruSpace.s8),
                CruPill(
                  text: '${item.patientCount} together',
                  icon: CruIcons.patients,
                  background: c.inset,
                  foreground: c.label2,
                ),
              ],
              const SizedBox(width: CruSpace.s8),
              Expanded(
                child: Text(
                  ApptFormat.range(item.start, item.end),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tabular.tint(c.label2),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s14),
          if (item.isGroup)
            for (var i = 0; i < item.members.length; i++) ...[
              if (i > 0) ...[
                const SizedBox(height: CruSpace.s12),
                const CruSeparator(),
                const SizedBox(height: CruSpace.s12),
              ],
              _Person(
                member: item.members[i],
                now: now,
                monogram: CruSize.monogramList,
                onRemove: canCancel
                    ? () => ApptActions.removeFromAppointment(
                          context,
                          ref,
                          item,
                          item.members[i],
                        )
                    : null,
                showOpen: true,
              ),
            ]
          else
            _Person(member: item, now: now, monogram: _monogram),
          if (item.isHomeVisit) ...[
            const SizedBox(height: CruSpace.s14),
            HomeVisitPanel(item: item),
          ],
          if (canAdd) ...[
            const SizedBox(height: CruSpace.s12),
            CruLink(
              label: '+ Add a patient to this appointment',
              onPressed: () => ApptActions.addPatient(context, ref, item),
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
                  onPressed: () => ApptActions.cancel(context, ref, item),
                ),
              const Spacer(),
              if (item.isGroup)
                CruLink(
                  label: 'Bill together',
                  onPressed: () => ApptActions.billTogether(context, item),
                )
              else if (patient != null)
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
}

/// One patient in the card: monogram, name, age · sex · returning, their
/// reason and any allergy. In a group, each can be opened or taken off
/// the appointment.
class _Person extends ConsumerWidget {
  const _Person({
    required this.member,
    required this.now,
    required this.monogram,
    this.onRemove,
    this.showOpen = false,
  });

  final ApptItem member;
  final DateTime now;
  final double monogram;
  final VoidCallback? onRemove;
  final bool showOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final patient = member.patient;
    final allergies = patient == null
        ? null
        : KnownAllergies.parse(
            ref
                .watch(homeopathyCaseSheetProvider(patient.id))
                .value
                ?.medicalHistory
                .allergies,
          );
    final grouped = showOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            CruMonogram(name: member.name, size: monogram),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: (grouped ? CruType.callout : CruType.headline)
                        .tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    ApptFormat.identityLine(member, now),
                    style: CruType.subhead.tabular.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onRemove != null)
              CruIconButton(
                icon: CruIcons.close,
                size: CruSize.squareButton,
                iconSize: 16,
                semanticLabel: 'Take ${member.firstName} off this appointment',
                tooltip: 'Take ${member.firstName} off this appointment',
                onPressed: onRemove,
              ),
            if (showOpen && patient != null)
              CruIconButton(
                icon: CruIcons.chevronRight,
                size: CruSize.squareButton,
                iconSize: 18,
                semanticLabel: 'Open ${member.name}',
                tooltip: 'Open ${member.firstName}',
                onPressed: () => DashboardActions.openPatient(context, patient),
              ),
          ],
        ),
        if (member.reason != null) ...[
          SizedBox(height: grouped ? CruSpace.s8 : CruSpace.s14),
          Text(member.reason!, style: CruType.text.tint(c.label)),
        ],
        if (allergies != null && !allergies.none) ...[
          SizedBox(height: grouped ? CruSpace.s8 : CruSpace.s14),
          CruInfoPill(
            text: 'Allergic to ${allergies.text}',
            icon: CruIcons.warning,
            tone: CruInfoPillTone.allergy,
          ),
        ],
      ],
    );
  }
}
