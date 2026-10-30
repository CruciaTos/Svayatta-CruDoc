import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/patients/data/providers/session_files_provider.dart';
import 'package:doctor_management_app/shared/widgets/morph_tag.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/visits_card.dart';
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

/// How many the Overview lists before "See all".
const int kPatientFilesOverviewLimit = 3;

/// Items before the Files tab offers a kind filter.
const int kPatientFilesFilterFrom = 6;

/// The patient's files, newest first. A file opens on tap. With
/// [showImaging] the patient's imaging studies are in the same list, so
/// there is one place for everything filed to the patient.
///
/// Three ways to show it: the latest four with "Show more" (default);
/// the latest three with "See all", which calls [onSeeAll] (Overview);
/// or every item grouped by the visit it belongs to, with a kind filter
/// ([full], the Files tab).
class PatientFilesCard extends ConsumerStatefulWidget {
  const PatientFilesCard({
    super.key,
    required this.patient,
    this.showImaging = false,
    this.onSeeAll,
    this.full = false,
    this.visits = const [],
  });

  final Patient patient;
  final bool showImaging;
  final VoidCallback? onSeeAll;
  final bool full;

  /// The patient's visits, to name the groups in [full].
  final List<Visit> visits;

  @override
  ConsumerState<PatientFilesCard> createState() => _PatientFilesCardState();
}

/// One row of the card: an imaging study or a file.
typedef _Item = ({DateTime at, RadStudy? study, PatientFile? file});

class _PatientFilesCardState extends ConsumerState<PatientFilesCard> {
  bool _expanded = false;

  /// The Files tab's kind filter (null: all).
  FileKind? _kind;

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

    // The Files tab groups files under the visit they were added from
    // (else the visit that day), so a file added later for an earlier
    // visit sits with it.
    final full = widget.full;
    final links = full
        ? ref.watch(sessionFilesProvider(patient.id)).links
        : const <String, String>{};
    final visitsById = {for (final v in widget.visits) v.id: v};
    Visit? linkedVisit(PatientFile? f) =>
        f == null ? null : visitsById[links[f.id]];

    // Studies by when they reached the clinic, files by when they were
    // added (or their visit, on the Files tab): one list, newest first.
    DateTime when(_Item i) =>
        (full ? linkedVisit(i.file)?.scheduledStart : null) ?? i.at;
    final all = <_Item>[
      for (final s in studies) (at: s.receivedAt, study: s, file: null),
      for (final f in files ?? const <PatientFile>[])
        (at: f.createdAt, study: null, file: f),
    ]..sort((a, b) => when(b).compareTo(when(a)));
    FileKind kindOf(_Item i) => i.study != null
        ? FileKind.scan
        : PatientFileTypes.kindOf(i.file!.contentType);
    final kinds = full ? {for (final i in all) kindOf(i)} : const <FileKind>{};
    final showFilter =
        kinds.length > 1 && all.length >= kPatientFilesFilterFrom;
    final kind = showFilter && kinds.contains(_kind) ? _kind : null;
    final items = kind == null
        ? all
        : all.where((i) => kindOf(i) == kind).toList();
    final limit = widget.onSeeAll != null
        ? kPatientFilesOverviewLimit
        : kPatientFilesCardLimit;
    final shown = full || _expanded ? items : items.take(limit).toList();
    final hidden = full ? 0 : items.length - limit;

    // "12 Oct · Root canal 46", or the date alone.
    String groupOf(_Item i) {
      final day = when(i);
      final visit =
          linkedVisit(i.file) ??
          widget.visits
              .where(
                (v) =>
                    v.status != VisitStatus.cancelled &&
                    v.status != VisitStatus.missed &&
                    DateUtils.isSameDay(v.scheduledStart, day),
              )
              .firstOrNull;
      final date = DateFormat(
        day.year == now.year ? 'd MMM' : 'd MMM y',
      ).format(day);
      return visit == null ? date : '$date · ${visitTitle(visit)}';
    }

    final groups = full
        ? [for (final i in shown) groupOf(i)]
        : const <String>[];

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
            if (full && (i == 0 || groups[i] != groups[i - 1]))
              Padding(
                padding: EdgeInsets.fromLTRB(12, i == 0 ? 4 : 16, 12, 4),
                child: DetailsSectionLabel(groups[i]),
              )
            else if (i > 0)
              const CruSeparator(
                indent: CruSize.patientTextInset,
                endIndent: CruSpace.s12,
              ),
            if (shown[i].study case final s?)
              MorphTag(
                id: 'study:${s.id}',
                child: _StudyRow(study: s, prior: s != newestStudy),
              )
            else
              MorphTag(
                id: 'file:${shown[i].file!.id}',
                child: _FileRow(
                  file: shown[i].file!,
                  patientName: name,
                  now: now,
                ),
              ),
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
                child: widget.onSeeAll != null
                    ? CruLink(
                        label: 'See all ${items.length} files',
                        onPressed: widget.onSeeAll!,
                      )
                    : CruLink(
                        label: _expanded ? 'Show less' : 'Show $hidden more',
                        onPressed: () =>
                            setState(() => _expanded = !_expanded),
                      ),
              ),
            ),
        ],
      );
    }

    final card = CruCard(
      semanticLabel: 'Files',
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: DetailsCardHeader(
              title: 'Files',
              onTap: widget.onSeeAll,
              morphId: widget.onSeeAll == null ? null : 'title',
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
    if (!showFilter) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: CruSegmentedControl<FileKind?>(
            semanticLabel: 'Show',
            segments: [
              const CruSegment(null, 'All'),
              for (final k in FileKind.values)
                if (kinds.contains(k)) CruSegment(k, k.label),
            ],
            selected: kind,
            onChanged: (k) => setState(() => _kind = k),
          ),
        ),
        const SizedBox(height: CruSpace.s12),
        card,
      ],
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
