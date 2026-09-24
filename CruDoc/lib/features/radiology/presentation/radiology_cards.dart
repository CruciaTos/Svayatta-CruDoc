import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/rad_import_flow.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/worklist_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The radiologist's dashboard card: what's waiting to be read, what's
/// late, and the next study to open.
class RadiologyTodayCard extends ConsumerWidget {
  const RadiologyTodayCard({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final studies = ref.watch(radStudiesProvider).value;
    if (studies == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final toRead = studies
        .where((s) => s.status == RadStudyStatus.newStudy || s.status == RadStudyStatus.reading)
        .toList();
    final inReport = studies
        .where((s) => s.status == RadStudyStatus.draft || s.status == RadStudyStatus.preliminary)
        .length;
    final urgent = toRead.where((s) => s.priority != RadPriority.routine).length;
    final overdue = studies.where((s) => s.isOverdue(now)).length;
    final signedToday =
        studies.where((s) => !s.status.isOpen && DentalFormat.sameDay(s.updatedAt, now)).length;
    final next = radNextUnread(studies);

    final readText = toRead.isEmpty
        ? 'All caught up'
        : [
            '${DashFormat.plural(toRead.length, 'study', 'studies')} to read',
            if (urgent > 0) '$urgent urgent',
            if (overdue > 0) '$overdue overdue',
          ].join(' · ');
    final reportText = [
      inReport == 0 ? 'No drafts open' : '${DashFormat.plural(inReport, 'report')} in progress',
      '$signedToday signed today',
    ].join(' · ');

    return CruCard(
      semanticLabel: 'Radiology',
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          _Row(
            icon: RadIcons.worklist,
            title: 'Worklist',
            detail: readText,
            tone: overdue > 0 ? c.amberText : c.label2,
            onTap: () => onNavigate(DesktopTab.worklist),
          ),
          const CruSeparator(indent: 12 + 36 + 12),
          _Row(
            icon: RadIcons.report,
            title: 'Reports',
            detail: reportText,
            tone: c.label2,
            onTap: () => onNavigate(DesktopTab.reports),
          ),
          const CruSeparator(indent: 12 + 36 + 12),
          if (next != null)
            DentalListRow(
              semanticLabel: 'Read next: ${next.patientName}',
              onTap: () => openRadStudy(context, ref, next),
              minHeight: 60,
              child: Row(
                children: [
                  RadModalityBadge(next.modality, width: 36),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Read next · ${next.patientName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.callout.w600.tint(c.label)),
                        Text(
                          [
                            RadFormat.due(next, now).text,
                            if (next.clinicalQuestion.isNotEmpty) next.clinicalQuestion,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.subhead.tabular.tint(
                              next.isOverdue(now) ? c.amberText : c.label2),
                        ),
                      ],
                    ),
                  ),
                  CruCapsuleButton(
                    label: 'Open',
                    onPressed: () => openRadStudy(context, ref, next),
                  ),
                ],
              ),
            )
          else
            DentalListRow(
              semanticLabel: 'Import scans',
              onTap: () => runRadImport(context, ref),
              minHeight: 60,
              child: Row(
                children: [
                  const CruIconTile(icon: RadIcons.import, tone: CruTileTone.accent),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Import scans', style: CruType.callout.w600.tint(c.label)),
                        Text('From a CD, folder or ZIP',
                            style: CruType.subhead.tint(c.label2)),
                      ],
                    ),
                  ),
                  CruIcon(CruIcons.chevronRight, size: 18, color: c.label3),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.detail,
    required this.tone,
    required this.onTap,
  });

  final CruIconData icon;
  final String title;
  final String detail;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DentalListRow(
      semanticLabel: '$title. $detail',
      onTap: onTap,
      minHeight: 60,
      child: Row(
        children: [
          CruIconTile(icon: icon, tone: CruTileTone.accent),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.callout.w600.tint(c.label)),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tabular.tint(tone),
                ),
              ],
            ),
          ),
          CruIcon(CruIcons.chevronRight, size: 18, color: c.label3),
        ],
      ),
    );
  }
}

/// A patient's imaging on their record: every study, newest first, with
/// its report status. Radiologists only.
class PatientImagingCard extends ConsumerWidget {
  const PatientImagingCard({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final studies = (ref.watch(radStudiesProvider).value ?? const <RadStudy>[])
        .where((s) => s.patientId == patientId)
        .toList()
      ..sort((a, b) => b.studyDate.compareTo(a.studyDate));
    final now = DateTime.now();

    return CruCard(
      semanticLabel: 'Imaging',
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
            child: Row(
              children: [
                Expanded(child: Text('Imaging', style: CruType.headline.tint(c.label))),
                if (studies.any((s) => !s.dose.isEmpty))
                  CruLink(
                    label: 'Dose log',
                    onPressed: () => showRadDoseLogDialog(context,
                        patientId: patientId, name: studies.first.patientName),
                  )
                else
                  Text(
                    studies.isEmpty ? '' : DashFormat.plural(studies.length, 'study', 'studies'),
                    style: CruType.caption.tabular.tint(c.label3),
                  ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s8),
          if (studies.isEmpty)
            Padding(
              padding: const EdgeInsets.all(CruSpace.s12),
              child: Text(
                'No scans for this patient yet. Import from the Worklist and link them here.',
                style: CruType.subhead.tint(c.label2),
              ),
            )
          else
            for (var i = 0; i < studies.length; i++) ...[
              if (i > 0) const CruSeparator(indent: 12 + 58 + 14),
              DentalListRow(
                semanticLabel: '${studies[i].modality.label}, ${RadFormat.date(studies[i].studyDate)}',
                onTap: () => openRadStudy(context, ref, studies[i]),
                child: Row(
                  children: [
                    RadModalityBadge(studies[i].modality),
                    const SizedBox(width: CruSpace.s14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            RadFormat.date(studies[i].studyDate),
                            style: CruType.callout.tabular.tint(c.label),
                          ),
                          Text(
                            [
                              RadFormat.images(studies[i].imageCount),
                              if (studies[i].clinicalQuestion.isNotEmpty)
                                studies[i].clinicalQuestion,
                              // Older scans are the priors to compare with.
                              if (i > 0) 'Prior',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.subhead.tint(c.label2),
                          ),
                        ],
                      ),
                    ),
                    radStatusPill(c, studies[i].status),
                    const SizedBox(width: CruSpace.s8),
                    if (!studies[i].status.isOpen)
                      CruCapsuleButton(
                        label: 'Report',
                        onPressed: () => openRadReport(context, studies[i]),
                      ),
                  ],
                ),
              ),
            ],
          if (studies.isNotEmpty && studies.first.isOverdue(now))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text('The latest study is past its turnaround time.',
                  style: CruType.caption.tint(c.amberText)),
            ),
        ],
      ),
    );
  }
}
