import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_photos_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/physio_comparison_dialog.dart';
import 'package:doctor_management_app/features/therapy/presentation/physio_photos_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Card displayed on Patient Details for Physiotherapists to manage per-session
/// posture, movement, and joint photos.
class PhysioPhotosCard extends ConsumerWidget {
  const PhysioPhotosCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recordsAsync = ref.watch(
      patientRecordsProvider(
        (patientId: patient.id, kind: RecKind.physioPhotoSet),
      ),
    );

    return recordsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (records) {
        final sets = records.map(PhysioPhotoSet.fromRecord).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        final latest = sets.isEmpty ? null : sets.first;

        return CruCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card Header
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(CruRadius.control),
                    ),
                    child: Icon(
                      Icons.accessibility_new_rounded,
                      size: 18,
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Posture & Movement Photos',
                          style: CruType.headline.w600.tint(c.label),
                        ),
                        const SizedBox(height: CruSpace.s2),
                        Text(
                          sets.isEmpty
                              ? 'Record photo series per treatment session'
                              : '${sets.length} session${sets.length == 1 ? '' : 's'} recorded · Last ${DentalFormat.date(latest!.date)}',
                          style: CruType.caption.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                  if (sets.length >= 2) ...[
                    CruCapsuleButton(
                      label: 'Compare',
                      icon: CruIcons.search,
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => PhysioBeforeAfterDialog(
                            patient: patient,
                            initialBeforeSet: sets.last,
                            initialAfterSet: sets.first,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: CruSpace.s8),
                  ],
                  CruCapsuleButton(
                    label: sets.isEmpty ? '+ Session' : 'Manage',
                    icon: sets.isEmpty ? CruIcons.plus : CruIcons.search,
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => PhysioPhotosDialog(patient: patient),
                      );
                    },
                  ),
                ],
              ),

              if (latest != null && latest.filledCount > 0) ...[
                const SizedBox(height: CruSpace.s14),
                // Recent photos thumbnail strip
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final slot in PhysioPhotoSlot.values) ...[
                        if (latest.photoFor(slot) != null) ...[
                          GestureDetector(
                            onTap: () {
                              showDialog<void>(
                                context: context,
                                builder: (_) => PhysioPhotosDialog(
                                  patient: patient,
                                ),
                              );
                            },
                            child: Container(
                              width: 80,
                              height: 100,
                              margin: const EdgeInsets.only(right: CruSpace.s8),
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(CruRadius.control),
                                border: Border.all(color: c.hairline),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(latest.photoFor(slot)!),
                                    fit: BoxFit.cover,
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: CruSpace.s4,
                                        vertical: CruSpace.s2,
                                      ),
                                      color: Colors.black.withValues(alpha: 0.65),
                                      child: Text(
                                        slot.title.split(' ').first,
                                        style: CruType.micro.w600.tint(Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
