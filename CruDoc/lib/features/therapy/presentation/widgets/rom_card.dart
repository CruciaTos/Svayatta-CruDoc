import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_assess_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/rom_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patient Details card for physiotherapists: the latest ROM and strength
/// assessment of each region.
class RomCard extends ConsumerWidget {
  const RomCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((patientId: patient.id, kind: RecKind.physioRom)),
    );
    final latest = <String, RomAssessment>{};
    for (final a in romAssessments(recs.value ?? const <DentalRecord>[])) {
      latest.putIfAbsent(a.regionId, () => a);
    }

    return CruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.inset,
                  borderRadius: BorderRadius.circular(CruRadius.control),
                ),
                child: Icon(
                  Icons.straighten_rounded,
                  size: 18,
                  color: c.label2,
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ROM & strength',
                      style: CruType.headline.w600.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      latest.isEmpty
                          ? 'Joint range and muscle grades'
                          : '${latest.length} region${latest.length == 1 ? '' : 's'} assessed',
                      style: CruType.caption.tint(c.label2),
                    ),
                  ],
                ),
              ),
              CruCapsuleButton(
                label: latest.isEmpty ? 'Assess' : '+ Assess',
                icon: latest.isEmpty ? CruIcons.plus : null,
                onPressed: () => pickRomRegion(context, patient),
              ),
            ],
          ),
          for (final r in kRomRegions)
            if (latest[r.id] case final a?)
              InkWell(
                borderRadius: BorderRadius.circular(CruRadius.control),
                onTap: () => openRomRegion(context, patient, r),
                child: Padding(
                  padding: const EdgeInsets.only(top: CruSpace.s12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.label,
                          style: CruType.body.w600.tint(c.label),
                        ),
                      ),
                      Text(
                        '${a.rows.length} movement${a.rows.length == 1 ? '' : 's'} · ${DentalFormat.date(a.date)}',
                        style: CruType.caption.tint(c.label2),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
