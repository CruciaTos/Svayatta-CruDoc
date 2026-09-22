import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The profile header (not in a card): 76 px monogram, name, "age · sex ·
/// Patient since", allergy and phone chips, Call and WhatsApp.
class IdentityHeader extends StatelessWidget {
  const IdentityHeader({
    super.key,
    required this.summary,
    required this.allergies,
    required this.onCall,
    required this.onWhatsApp,
  });

  final PatientSummary summary;

  /// Null when nothing is recorded (the chip is hidden).
  final KnownAllergies? allergies;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final p = summary.patient;
    final hasPhone = p.phone.trim().isNotEmpty;
    final meta = '${PatientFormat.ageSexLong(p)} · '
        'Patient since ${PatientFormat.longDate(p.createdAt)}';
    final a = allergies;

    final identity = Row(
      children: [
        CruMonogram(name: p.fullName, size: CruSize.monogramProfile),
        const SizedBox(width: CruSpace.s20),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  p.fullName,
                  style: CruType.largeTitle.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: CruSpace.s2),
              Text(meta, style: CruType.text.tabular.tint(c.label2)),
              if (a != null || hasPhone) ...[
                const SizedBox(height: CruSpace.s12),
                Wrap(
                  spacing: CruSpace.s8,
                  runSpacing: CruSpace.s8,
                  children: [
                    if (a != null)
                      a.none
                          ? const CruInfoPill(
                              text: 'No known allergies',
                              icon: CruIcons.check,
                              tone: CruInfoPillTone.outlined,
                              tall: true,
                            )
                          : CruInfoPill(
                              text: 'Allergic to ${a.text}',
                              icon: CruIcons.warning,
                              tone: CruInfoPillTone.allergy,
                              tall: true,
                            ),
                    if (hasPhone)
                      CruInfoPill(
                        text: PatientFormat.phone(p.phone),
                        icon: CruIcons.phone,
                        tone: CruInfoPillTone.outlined,
                        tall: true,
                        tabular: true,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: identity),
        if (hasPhone) ...[
          const SizedBox(width: CruSpace.s24),
          CruCapsuleButton(
            label: 'Call',
            icon: CruIcons.phone,
            kind: CruCapsuleKind.tinted,
            height: CruSize.profileCapsule,
            large: true,
            semanticLabel: 'Call ${p.fullName}',
            onPressed: onCall,
          ),
          const SizedBox(width: CruSpace.s8),
          CruCapsuleButton(
            label: 'WhatsApp',
            icon: CruIcons.whatsapp,
            kind: CruCapsuleKind.tinted,
            height: CruSize.profileCapsule,
            large: true,
            semanticLabel: 'WhatsApp ${p.fullName}',
            onPressed: onWhatsApp,
          ),
        ],
      ],
    );
  }
}
