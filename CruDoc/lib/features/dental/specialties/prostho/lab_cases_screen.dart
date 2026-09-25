import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_dialog.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_export.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_models.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_rx_pdf.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _CaseViewMode { list, board }

/// Screen for tracking prosthodontic lab cases with List and Board views.
class LabCasesScreen extends ConsumerStatefulWidget {
  const LabCasesScreen({super.key});

  @override
  ConsumerState<LabCasesScreen> createState() => _LabCasesScreenState();
}

class _LabCasesScreenState extends ConsumerState<LabCasesScreen> {
  _CaseViewMode _view = _CaseViewMode.list;
  final TextEditingController _search = TextEditingController();
  LabCaseStage? _stageFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final cases = ref.watch(allLabCasesProvider);
    final patients = ref.watch(patientsStreamProvider).value ?? const <Patient>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextWeek = today.add(const Duration(days: 7));

    // Glance metrics
    final atLab = cases.where((c) => c.stage.isAtLab).length;
    final dueThisWeek = cases.where((c) => c.stage.isOpen && !c.due.isBefore(today) && c.due.isBefore(nextWeek)).length;
    final overdue = cases.where((c) => c.isOverdue(now)).length;
    final receivedToFit = cases.where((c) => c.stage == LabCaseStage.received).length;

    final subtitle = [
      '$atLab at lab',
      if (overdue > 0) '$overdue overdue',
      '$receivedToFit to fit',
    ].join(' · ');

    final query = _search.text.trim().toLowerCase();
    final filtered = cases.where((lc) {
      if (_stageFilter != null && lc.stage != _stageFilter) return false;
      if (query.isNotEmpty) {
        final p = patients.where((pt) => pt.id == lc.patientId).firstOrNull;
        final patientName = p?.fullName.toLowerCase() ?? '';
        final labName = lc.labName.toLowerCase();
        final type = lc.type.toLowerCase();
        final teeth = lc.teeth.join(' ');
        if (!patientName.contains(query) && !labName.contains(query) && !type.contains(query) && !teeth.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    Widget cell(String label, String value, Widget caption, {bool warn = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel(label),
        GlanceMetric(value),
        GlanceCaption(caption),
      ],
    );

    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          DentalPageHeader(
            title: 'Lab cases',
            subtitle: subtitle.isNotEmpty ? subtitle : 'Track prosthodontic cases from impression to try-in and delivery',
            actions: [
              CruButton(
                label: 'New lab case',
                icon: CruIcons.plus,
                kind: CruButtonKind.primary,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const LabCaseEditDialog(),
                ),
              ),
            ],
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CruSpace.s24),
              children: [
                // Glance strip
                GlanceStrip(
                  semanticLabel: 'Lab cases at a glance',
                  cells: [
                    cell('At lab', '$atLab', const Text('Fabrication in progress')),
                    cell('Due this week', '$dueThisWeek', const Text('Next 7 days')),
                    cell(
                      'Overdue',
                      '$overdue',
                      overdue > 0
                          ? Text('Past due date', style: CruType.caption.tint(c.amberText))
                          : const Text('None'),
                      warn: overdue > 0,
                    ),
                    cell('Received to fit', '$receivedToFit', const Text('Ready for try-in / delivery')),
                  ],
                ),
                const SizedBox(height: CruSpace.s20),

                // Controls row: View toggle & Search & Filters
                Row(
                  children: [
                    CruSegmentedControl<_CaseViewMode>(
                      semanticLabel: 'View mode',
                      segments: const [
                        CruSegment(_CaseViewMode.list, 'List'),
                        CruSegment(_CaseViewMode.board, 'Board'),
                      ],
                      selected: _view,
                      onChanged: (v) => setState(() => _view = v),
                    ),
                    const SizedBox(width: CruSpace.s16),
                    if (_view == _CaseViewMode.list) ...[
                      DropdownButtonHideUnderline(
                        child: DropdownButton<LabCaseStage?>(
                          value: _stageFilter,
                          hint: Text('All stages', style: CruType.subhead.tint(c.label2)),
                          items: [
                            DropdownMenuItem<LabCaseStage?>(
                              value: null,
                              child: Text('All stages', style: CruType.body.tint(c.label)),
                            ),
                            for (final st in LabCaseStage.values)
                              DropdownMenuItem<LabCaseStage?>(
                                value: st,
                                child: Text(st.label, style: CruType.body.tint(c.label)),
                              ),
                          ],
                          onChanged: (st) => setState(() => _stageFilter = st),
                        ),
                      ),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: 280,
                      child: DentalSearchField(
                        hint: 'Search patient, lab, restoration…',
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s16),

                // Content: List or Board
                if (filtered.isEmpty)
                  DentalEmptyState(
                    icon: CruIcons.box,
                    title: query.isNotEmpty ? 'No matching lab cases' : 'No lab cases yet',
                    body: query.isNotEmpty
                        ? 'Try changing your search terms or filters.'
                        : 'Create a laboratory prescription for crowns, bridges, dentures or night guards.',
                    actions: query.isEmpty
                        ? [
                            CruButton(
                              label: 'New lab case',
                              icon: CruIcons.plus,
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => const LabCaseEditDialog(),
                              ),
                            ),
                          ]
                        : const [],
                  )
                else if (_view == _CaseViewMode.list)
                  CruCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < filtered.length; i++) ...[
                          if (i > 0) const CruSeparator(),
                          _LabCaseListRow(
                            labCase: filtered[i],
                            patient: patients.where((p) => p.id == filtered[i].patientId).firstOrNull,
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  _LabCaseBoardView(
                    cases: filtered,
                    patients: patients,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── List View Row ─────────────────────────────

class _LabCaseListRow extends ConsumerWidget {
  const _LabCaseListRow({
    required this.labCase,
    required this.patient,
  });

  final LabCase labCase;
  final Patient? patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final lc = labCase;
    final numbering = ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final isOverdue = lc.isOverdue(DateTime.now());

    final teethStr = lc.teeth.isEmpty
        ? '—'
        : lc.teeth.map((t) => toothLabel(t, numbering)).join(', ');

    return DentalListRow(
      semanticLabel: '${lc.type} - ${patient?.fullName ?? 'Patient'}',
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => LabCaseEditDialog(
          initialCase: lc,
          initialPatient: patient,
        ),
      ),
      minHeight: 56,
      child: Row(
        children: [
          const CruIconTile(icon: CruIcons.box, tone: CruTileTone.neutral),
          const SizedBox(width: CruSpace.s12),

          // Due date
          SizedBox(
            width: 84,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DentalFormat.date(lc.due),
                  style: CruType.caption.w600.tabular.tint(isOverdue ? c.amberText : c.label),
                ),
                Text(
                  'Due',
                  style: CruType.micro.tint(c.label3),
                ),
              ],
            ),
          ),

          // Patient name
          SizedBox(
            width: 140,
            child: Text(
              patient?.fullName ?? 'Patient #${lc.patientId.substring(0, 4)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.callout.w600.tint(c.label),
            ),
          ),
          const SizedBox(width: CruSpace.s12),

          // Restoration type & Material
          SizedBox(
            width: 150,
            child: Text(
              '${lc.type} · ${lc.material}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.callout.tint(c.label),
            ),
          ),
          const SizedBox(width: CruSpace.s12),

          // Teeth
          SizedBox(
            width: 90,
            child: Text(
              teethStr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.note.tabular.tint(c.label2),
            ),
          ),
          const SizedBox(width: CruSpace.s12),

          // Lab name
          Expanded(
            child: Text(
              lc.labName.isNotEmpty ? lc.labName : 'Dental Lab',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.caption.tint(c.label2),
            ),
          ),
          const SizedBox(width: CruSpace.s8),

          // Files chip (if has 3D scans)
          if (lc.files.any((f) => f.is3dScan)) ...[
            CruPill(
              text: '3D',
              background: c.accentTint,
              foreground: c.accent,
            ),
            const SizedBox(width: CruSpace.s8),
          ],

          // Stage pill
          CruPill(
            text: lc.stage.label,
            background: lc.stage == LabCaseStage.fitted
                ? c.greenTint
                : (isOverdue ? c.amberTint : c.inset),
            foreground: lc.stage == LabCaseStage.fitted
                ? c.greenText
                : (isOverdue ? c.amberText : c.label2),
          ),
          const SizedBox(width: CruSpace.s8),

          // Send to lab button
          if (patient != null)
            CruCapsuleButton(
              label: 'Send',
              icon: CruIcons.arrowUpRight,
              onPressed: () => sendLabCaseToLab(context, ref, lc, patient!),
            ),
          const SizedBox(width: CruSpace.s4),

          // Menu button
          PopupMenuButton<String>(
            tooltip: 'Actions',
            icon: CruIcon(CruIcons.more, size: 18, color: c.label2),
            itemBuilder: (ctx) => [
              for (final st in LabCaseStage.values)
                if (st != lc.stage)
                  PopupMenuItem(
                    value: 'stage_${st.name}',
                    child: Text('Move to ${st.label}'),
                  ),
              const PopupMenuItem(
                value: 'pdf',
                child: Text('Print Rx (PDF)'),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Text('Export case (ZIP)'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete case'),
              ),
            ],
            onSelected: (action) async {
              if (action.startsWith('stage_')) {
                final stageName = action.substring('stage_'.length);
                final nextStage = LabCaseStage.fromName(stageName);
                await updateLabCaseStage(context, ref, lc, nextStage, patient: patient);
              } else if (action == 'pdf') {
                if (patient != null) {
                  await LabRxPdfService.printOrPreview(
                    context: context,
                    ref: ref,
                    labCase: lc,
                    patient: patient!,
                  );
                }
              } else if (action == 'export') {
                if (patient != null) {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => ExportLabCaseDialog(
                      labCase: lc,
                      patient: patient!,
                    ),
                  );
                }
              } else if (action == 'delete') {
                final ok = await confirmDental(
                  context,
                  title: 'Delete lab case?',
                  body: 'This will remove the lab order for ${patient?.fullName ?? 'this patient'}.',
                  action: 'Delete',
                );
                if (ok) {
                  await deleteDentalRecord(ref, lc.record);
                  if (context.mounted) recToast(context, 'Lab case deleted');
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Board View with Drag & Drop ─────────────────────────────

class _LabCaseBoardView extends ConsumerWidget {
  const _LabCaseBoardView({
    required this.cases,
    required this.patients,
  });

  final List<LabCase> cases;
  final List<Patient> patients;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final stage in LabCaseStage.values)
            Container(
              width: 260,
              margin: const EdgeInsets.only(right: CruSpace.s12),
              child: DragTarget<LabCase>(
                onWillAcceptWithDetails: (details) => details.data.stage != stage,
                onAcceptWithDetails: (details) {
                  final droppedCase = details.data;
                  final p = patients.where((pt) => pt.id == droppedCase.patientId).firstOrNull;
                  updateLabCaseStage(context, ref, droppedCase, stage, patient: p);
                },
                builder: (context, candidateData, rejectedData) {
                  final stageCases = cases.where((lc) => lc.stage == stage).toList();
                  final isHovered = candidateData.isNotEmpty;

                  return Container(
                    decoration: BoxDecoration(
                      color: isHovered ? c.accentTint : c.surface,
                      borderRadius: BorderRadius.circular(CruRadius.card),
                      border: Border.all(
                        color: isHovered ? c.accent : c.hairline,
                        width: isHovered ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(CruSpace.s12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Column Header
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                stage.label,
                                style: CruType.callout.w600.tint(c.label),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: c.inset,
                                borderRadius: BorderRadius.circular(CruRadius.full),
                              ),
                              child: Text(
                                '${stageCases.length}',
                                style: CruType.caption.w600.tabular.tint(c.label2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: CruSpace.s12),

                        // Draggable Cards List
                        if (stageCases.isEmpty)
                          Container(
                            height: 80,
                            alignment: Alignment.center,
                            child: Text(
                              'Drop here',
                              style: CruType.caption.tint(c.label3),
                            ),
                          )
                        else
                          for (final lc in stageCases)
                            Padding(
                              padding: const EdgeInsets.only(bottom: CruSpace.s8),
                              child: Draggable<LabCase>(
                                data: lc,
                                feedback: Material(
                                  elevation: 6,
                                  borderRadius: BorderRadius.circular(CruRadius.control),
                                  child: Container(
                                    width: 236,
                                    padding: const EdgeInsets.all(CruSpace.s12),
                                    decoration: BoxDecoration(
                                      color: c.surface,
                                      borderRadius: BorderRadius.circular(CruRadius.control),
                                      border: Border.all(color: c.accent),
                                    ),
                                    child: Text(
                                      '${lc.type} · ${lc.teeth.join(',')}',
                                      style: CruType.callout.w600.tint(c.label),
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.3,
                                  child: _BoardCard(
                                    labCase: lc,
                                    patient: patients.where((p) => p.id == lc.patientId).firstOrNull,
                                  ),
                                ),
                                child: _BoardCard(
                                  labCase: lc,
                                  patient: patients.where((p) => p.id == lc.patientId).firstOrNull,
                                ),
                              ),
                            ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.labCase,
    required this.patient,
  });

  final LabCase labCase;
  final Patient? patient;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final lc = labCase;
    final isOverdue = lc.isOverdue(DateTime.now());

    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => LabCaseEditDialog(
          initialCase: lc,
          initialPatient: patient,
        ),
      ),
      borderRadius: BorderRadius.circular(CruRadius.control),
      child: Container(
        padding: const EdgeInsets.all(CruSpace.s10),
        decoration: BoxDecoration(
          color: c.canvas,
          borderRadius: BorderRadius.circular(CruRadius.control),
          border: Border.all(color: isOverdue ? c.amberText : c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    patient?.fullName ?? 'Patient',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.callout.w600.tint(c.label),
                  ),
                ),
                if (lc.files.any((f) => f.is3dScan))
                  CruPill(text: '3D', background: c.accentTint, foreground: c.accent),
              ],
            ),
            const SizedBox(height: CruSpace.s4),
            Text(
              '${lc.type} · ${lc.material} (${lc.teeth.join(',')})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.note.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lc.labName.isNotEmpty ? lc.labName : 'Dental Lab',
                  style: CruType.caption.tint(c.label3),
                ),
                Text(
                  DentalFormat.date(lc.due),
                  style: CruType.caption.tabular.tint(isOverdue ? c.amberText : c.label2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
