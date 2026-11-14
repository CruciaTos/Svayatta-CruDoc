import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/patients/presentation/widgets/missing_details_dot.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/domain/patient_completeness.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/domain/quick_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/identity_header.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The patient's grey monogram. With [allergic] it wears a red ring (2 px,
/// 3 px gap): red is for patient safety, so the ring is the one coloured
/// thing about the avatar and stays visible when the page is scrolled.
class PatientAvatar extends StatelessWidget {
  const PatientAvatar({
    super.key,
    required this.name,
    required this.size,
    this.allergic = false,
  });

  final String name;
  final double size;
  final bool allergic;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final monogram = CruMonogram(
      name: name,
      size: size,
      background: c.track,
      foreground: c.label2,
      showRing: false,
    );
    if (!allergic) return monogram;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.redText, width: 2),
      ),
      child: monogram,
    );
  }
}

/// Phone Patient details: the poster. A centred monogram (red ring when
/// allergic), the name, "age · sex · phone", "Details pending" when the
/// record is incomplete, and the allergy pill. No card: it sits straight
/// on the page background and scrolls away under the pinned bar.
class PatientPosterHero extends StatelessWidget {
  const PatientPosterHero({
    super.key,
    required this.summary,
    required this.allergies,
    required this.onEditPending,
  });

  final PatientSummary summary;

  /// Null when nothing is recorded (no pill, no ring).
  final KnownAllergies? allergies;

  /// Opens the edit sheet from the "Details pending" capsule.
  final VoidCallback onEditPending;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final p = summary.patient;
    final a = allergies;
    final allergic = a != null && !a.none;
    final meta = [
      PatientFormat.ageSex(p),
      if (p.phone.trim().isNotEmpty) PatientFormat.phone(p.phone),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s8, bottom: CruSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PatientAvatar(name: p.fullName, size: 72, allergic: allergic),
          const SizedBox(height: CruSpace.s12),
          Semantics(
            header: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mirror of the dot's width so the centred name does not
                // move when the dot shows.
                if (missingDetails(p).isNotEmpty)
                  const SizedBox(width: CruSpace.s16),
                Flexible(
                  child: Text(
                    p.fullName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MobileType.largeTitle.tint(c.label),
                  ),
                ),
                MissingDetailsDot(patient: p),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s4),
          Text(
            meta,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MobileType.subhead.tabular.tint(c.label2),
          ),
          if (patientDetailsPending(p)) ...[
            const SizedBox(height: CruSpace.s8),
            DetailsPendingPill(onTap: onEditPending),
          ],
          if (a != null) ...[
            const SizedBox(height: CruSpace.s12),
            a.none
                ? const CruInfoPill(
                    text: 'No known allergies',
                    icon: CruIcons.check,
                    tone: CruInfoPillTone.outlined,
                  )
                : CruInfoPill(
                    text: 'Allergic to ${a.text}',
                    icon: CruIcons.warning,
                    tone: CruInfoPillTone.allergy,
                  ),
          ],
        ],
      ),
    );
  }
}
