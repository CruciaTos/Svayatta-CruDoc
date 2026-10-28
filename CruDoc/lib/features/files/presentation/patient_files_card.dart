import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/domain/files_builder.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/file_thumb.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/scan/data/scan_capture.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_flow.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// How many items the card lists before "Show more".
const int kPatientFilesCardLimit = 4;

/// The patient's files on their page, newest first: the latest four, the
/// rest on "Show more". A file opens on tap; "See all" opens the Files
/// screen for this patient. With [showImaging] the patient's imaging
/// studies are in the same list, so Patient details has one card for
/// everything filed to the patient.
class PatientFilesCard extends ConsumerStatefulWidget {
  const PatientFilesCard({
    super.key,
    required this.patient,
    this.showImaging = false,
  });

  final Patient patient;
  final bool showImaging;

  @override
  ConsumerState<PatientFilesCard> createState() => _PatientFilesCardState();
}

/// One row of the card: an imaging study or a file.
typedef _Item = ({DateTime at, RadStudy? study, PatientFile? file});

class _PatientFilesCardState extends ConsumerState<PatientFilesCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final patient = widget.patient;
    final async = ref.watch(patientFilesProvider(patient.id));
    final files = async.value;
    final now = ref.watch(dashboardNowProvider);
    final name = patient.fullName.trim();
    final canEdit = ref.watch(clinicCanProvider(ClinicPermission.clinicalEdit));
    final studies = widget.showImaging
        ? ((ref.watch(radStudiesProvider).value ?? const <RadStudy>[])
              .where((s) => s.patientId == patient.id)
              .toList()
            ..sort((a, b) => b.studyDate.compareTo(a.studyDate)))
        : const <RadStudy>[];
    final hasDose = studies.any((s) => !s.dose.isEmpty);
    // Older scans are the priors to compare with the newest one.
    final newestStudy = studies.firstOrNull;

    // Studies by when they reached the clinic, files by when they were
    // added: one list, newest first.
    final items = <_Item>[
      for (final s in studies) (at: s.receivedAt, study: s, file: null),
      for (final f in files ?? const <PatientFile>[])
        (at: f.createdAt, study: null, file: f),
    ]..sort((a, b) => b.at.compareTo(a.at));
    final shown = _expanded
        ? items
        : items.take(kPatientFilesCardLimit).toList();
    final hidden = items.length - kPatientFilesCardLimit;

    final Widget body;
    if (files == null && studies.isEmpty) {
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
    } else if (items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Text(
          'No X-rays, photos or reports yet',
          style: CruType.text.tint(c.label2),
        ),
      );
    } else {
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
            if (shown[i].study case final s?)
              _StudyRow(study: s, prior: s != newestStudy)
            else
              _FileRow(file: shown[i].file!, patientName: name, now: now),
          ],
          if (newestStudy != null && newestStudy.isOverdue(DateTime.now()))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Text(
                'The latest study is past its turnaround time.',
                style: CruType.caption.tint(c.amberText),
              ),
            ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: CruLink(
                  label: _expanded ? 'Show less' : 'Show $hidden more',
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ),
            ),
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canEdit)
                    CruSquareButton(
                      icon: FileIcons.upload,
                      semanticLabel: 'Add files',
                      tooltip: 'Add files',
                      onPressed: () => FilesActions.pickAndAdd(
                        context,
                        patientId: patient.id,
                      ),
                    ),
                  if (canEdit && ScanCapture.hasCamera) ...[
                    const SizedBox(width: CruSpace.s8),
                    CruSquareButton(
                      icon: CruIcons.scan,
                      semanticLabel: 'Scan',
                      tooltip: 'Scan',
                      onPressed: () => startScanFlow(
                        context,
                        patient: patient,
                        clinical: true,
                        inventory: false,
                        revenue: false,
                      ),
                    ),
                  ],
                  if (hasDose) ...[
                    if (canEdit) const SizedBox(width: CruSpace.s8),
                    CruSquareButton(
                      icon: RadIcons.dose,
                      semanticLabel: 'Dose log',
                      tooltip: 'Dose log',
                      onPressed: () => showRadDoseLogDialog(
                        context,
                        patientId: patient.id,
                        name: studies.first.patientName,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          body,
        ],
      ),
    );
  }
}

/// One file in the card: thumbnail, name, when it was added and its type.
/// Opens the file.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.patientName,
    required this.now,
  });

  final PatientFile file;
  final String patientName;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: () => FilesActions.open(context, file, patientName: patientName),
      scaleOnPress: false,
      semanticLabel: 'Open ${file.name}',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: CruSize.compactRow,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            FileThumb(file: file),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: CruType.row.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${FilesBuilder.dateLabel(file.createdAt, now)}'
                    ' · ${FilesBuilder.typeLabel(file)}',
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
    );
  }
}

/// One imaging study in the Files card: modality, date, images and its
/// report status. Opens the study.
class _StudyRow extends ConsumerWidget {
  const _StudyRow({required this.study, required this.prior});

  final RadStudy study;

  /// Older studies are the priors to compare with.
  final bool prior;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    return CruPressable(
      onTap: () => openRadStudy(context, ref, study),
      scaleOnPress: false,
      semanticLabel:
          '${study.modality.label}, ${RadFormat.date(study.studyDate)}',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: CruSize.compactRow,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            RadModalityBadge(study.modality),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    RadFormat.date(study.studyDate),
                    style: CruType.row.tabular.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      RadFormat.images(study.imageCount),
                      if (prior) 'Prior',
                    ].join(' · '),
                    style: CruType.subhead.tabular.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            if (study.status.isOpen)
              radStatusPill(c, study.status)
            else
              CruCapsuleButton(
                label: 'Report',
                onPressed: () => openRadReport(context, study),
              ),
          ],
        ),
      ),
    );
  }
}
