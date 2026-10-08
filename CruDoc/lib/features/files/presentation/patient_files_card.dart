import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/domain/files_builder.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/file_thumb.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// How many files the card lists before "See all".
const int kPatientFilesCardLimit = 4;

/// The patient's latest files on their page. A file opens on tap; "See
/// all" opens the Files screen for this patient.
class PatientFilesCard extends ConsumerWidget {
  const PatientFilesCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final async = ref.watch(patientFilesProvider(patient.id));
    final files = async.value;
    final now = ref.watch(dashboardNowProvider);
    final name = patient.fullName.trim();
    final canEdit = ref.watch(clinicCanProvider(ClinicPermission.clinicalEdit));

    final Widget body;
    if (files == null) {
      body = async.hasError
          ? Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Text(
                "Couldn't load files.",
                style: CruType.text.tint(c.label2),
              ),
            )
          : const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: SkeletonBox(width: 200, height: 12),
            );
    } else if (files.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Text(
          'No X-rays, photos or reports yet',
          style: CruType.text.tint(c.label2),
        ),
      );
    } else {
      final shown = files.take(kPatientFilesCardLimit).toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: CruSpace.s8),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              const CruSeparator(
                indent: CruSize.patientTextInset,
                endIndent: CruSpace.s12,
              ),
            CruPressable(
              onTap: () =>
                  FilesActions.open(context, shown[i], patientName: name),
              scaleOnPress: false,
              semanticLabel: 'Open ${shown[i].name}',
              builder: (context, hovered) => AnimatedContainer(
                duration: CruMotion.of(context, CruMotion.fast),
                curve: CruMotion.curve,
                height: CruSize.compactRow,
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
                decoration: ShapeDecoration(
                  color: hovered
                      ? c.hoverFill
                      : c.hoverFill.withValues(alpha: 0),
                  shape: cruShape(CruRadius.control),
                ),
                child: Row(
                  children: [
                    FileThumb(file: shown[i]),
                    const SizedBox(width: CruSpace.s12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shown[i].name,
                            style: CruType.row.tint(c.label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${FilesBuilder.dateLabel(shown[i].createdAt, now)}'
                            ' · ${FilesBuilder.typeLabel(shown[i])}',
                            style: CruType.subhead.tabular.tint(c.label2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }

    return CruCard(
      semanticLabel: 'Files',
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: DetailsCardHeader(
              title: 'Files',
              trailing: files != null && files.isNotEmpty
                  ? CruLink(
                      label: files.length > kPatientFilesCardLimit
                          ? 'See all ${files.length}'
                          : 'See all',
                      onPressed: () =>
                          FilesActions.showForPatient(context, ref, patient.id),
                    )
                  : null,
            ),
          ),
          body,
          if (canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: CruCapsuleButton(
                  label: 'Add files',
                  icon: FileIcons.upload,
                  onPressed: () =>
                      FilesActions.pickAndAdd(context, patientId: patient.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
