import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/clinical_forms.dart';
import 'package:doctor_management_app/features/dental/records/consent_dialog.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/endo_dialog.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/dental/records/srp_dialog.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_dialogs.dart';
import 'package:doctor_management_app/features/dental/specialties/anaesthesia/drug_log.dart';
import 'package:doctor_management_app/features/dental/specialties/anaesthesia/preop_dialog.dart';
import 'package:doctor_management_app/features/dental/specialties/forms/form_fill.dart';
import 'package:doctor_management_app/features/dental/specialties/ortho/ortho_photos.dart';
import 'package:doctor_management_app/features/dental/specialties/pedo/eruption_chart.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_dialog.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_flow.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Charting's workspaces, in the order the switch shows them.
enum ChartingTab {
  teeth('Chart'),
  plan('Plan'),
  perio('Perio'),
  rootCanals('Endo'),
  surgery('Surgery'),
  kids('Kids & ortho'),
  records('Records'),
  wrapUp('Wrap-up');

  const ChartingTab(this.label);
  final String label;
}

/// How a record's status reads: quiet, amber (open, waiting, overdue) or
/// green (done).
enum RecordTone { plain, warn, done }

/// One clinical record type: its button on the shelf and its card in a
/// workspace. One definition, so both open the same thing and show the
/// same status.
class ChartRecord {
  const ChartRecord({
    required this.id,
    required this.label,
    required this.icon,
    required this.onOpen,
    required this.detail,
    this.status,
    this.tone = RecordTone.plain,
    this.action = false,
    this.title,
  });

  /// The full name on its workspace card, when the shelf's [label] is a
  /// short form.
  final String? title;

  /// Something to do (write a prescription), not a record: no status.
  final bool action;

  final String id;
  final String label;
  final CruIconData icon;
  final VoidCallback onOpen;

  /// What it is, for its workspace card.
  final String detail;

  /// Null when nothing is recorded yet.
  final String? status;
  final RecordTone tone;
}

/// The shelf's clusters, in order: exam, treat, after, paperwork.
typedef RecordCluster = ({String label, List<ChartRecord> records});

/// Every record type for [p], with live status. Perio opens through
/// [go]; the rest open their record.
List<RecordCluster> chartRecords(
  BuildContext context,
  WidgetRef ref,
  Patient p, {
  required ValueChanged<ChartingTab> go,
  VoidCallback? onPerio,
}) {
  final byKind =
      ref.watch(patientRecordsByKindProvider(p.id)).value ??
      const <String, List<DentalRecord>>{};
  List<DentalRecord> of(String kind) => byKind[kind] ?? const [];
  String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  final now = DateTime.now();
  final child = p.age < 16;

  final perio = of(RecKind.perio);
  final srp = srpTileLine(of(RecKind.srp));
  final endo = of(RecKind.endo);
  final endoOpen = endo.where((r) => r.str('status') != 'obturated').length;

  final pain = of(RecKind.pain);
  final tmd = of(RecKind.tmd);
  final painStatus = pain.isNotEmpty
      ? 'Pain ${(pain.first.number('score') ?? 0).toStringAsFixed(0)}'
            '${pain.first.str('scale') == 'VAS' ? ' mm' : '/10'}'
      : tmd.isNotEmpty
      ? 'TMD ${tmd.first.integer('score')}/7'
      : null;

  final photoSets = of(RecKind.photoSet);
  final eruptionRecord = of(RecKind.eruption).firstOrNull;
  final eruption = eruptionCardLine(eruptionRecord, p);
  final frankl = of(RecKind.frankl);

  final checklists = of(RecKind.checklist);
  final openChecklists = checklists
      .where((r) => r.data['complete'] != true)
      .length;
  final sedation = of(RecKind.sedationCase);
  final sedationStatus = sedation.firstOrNull?.str('status') ?? '';
  final consents = of(RecKind.consent);

  final labCases = of(RecKind.labCase);
  final activeLab = labCases.where((r) => r.str('stage') != 'fitted').length;
  final referrals = of(RecKind.referral);
  final openReferrals = referrals
      .where(
        (r) => r.str('status') != 'completed' && r.str('status') != 'declined',
      )
      .length;
  final recalls =
      of(RecKind.recall).where((r) => recallStatusOf(r).isOpen).toList()
        ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  final nextRecall = recalls.firstOrNull;
  final forms = of(RecKind.formResponse);

  void dialog(Widget child) =>
      showDialog<void>(context: context, builder: (_) => child);

  return [
    (
      label: 'Exam',
      records: [
        ChartRecord(
          id: 'perio',
          label: 'Perio',
          icon: RecIcons.perio,
          detail: 'Pockets, bleeding, plaque, stage and grade.',
          status: perio.isEmpty
              ? null
              : DentalFormat.shortDate(perio.first.recordedAt),
          onOpen: onPerio ?? () => go(ChartingTab.perio),
        ),
        ChartRecord(
          id: 'endo',
          label: 'Endo',
          icon: RecIcons.endo,
          detail: 'Root canals: diagnosis, canals, filling.',
          status: endo.isEmpty
              ? null
              : endoOpen > 0
              ? '$endoOpen open'
              : '${endo.length} done',
          tone: endoOpen > 0 ? RecordTone.warn : RecordTone.plain,
          onOpen: () => showEndoDialog(context, p),
        ),
        ChartRecord(
          id: 'pain',
          label: 'Pain & TMD',
          title: 'Pain and TMD',
          icon: RecIcons.pain,
          detail: 'Pain score over time and the jaw joint screener.',
          status: painStatus,
          onOpen: () => showPainDialog(context, p),
        ),
        ChartRecord(
          id: 'ortho',
          label: 'Photos',
          title: 'Ortho photos',
          icon: RecIcons.camera,
          detail: 'Progress photo series, before and after.',
          status: photoSets.isEmpty ? null : plural(photoSets.length, 'series'),
          onOpen: () => dialog(OrthoPhotosDialog(patient: p)),
        ),
        if (child)
          ChartRecord(
            id: 'eruption',
            label: 'Eruption',
            icon: DentalIcons.tooth,
            detail: 'Which teeth are through, late or retained.',
            status: eruptionTeethOf(eruptionRecord).isEmpty
                ? null
                : eruption.warn
                ? 'Flagged'
                : 'Charted',
            tone: eruption.warn ? RecordTone.warn : RecordTone.plain,
            onOpen: () =>
                showEruptionDialog(context, p, existing: eruptionRecord),
          ),
      ],
    ),
    (
      label: 'Treat',
      records: [
        ChartRecord(
          id: 'srp',
          label: 'Root planing',
          icon: RecIcons.srp,
          detail: 'Deep cleaning by quadrant, then the re-evaluation.',
          status: srp.text,
          tone: srp.warn ? RecordTone.warn : RecordTone.plain,
          onOpen: () => showSrpDialog(context, p),
        ),
        ChartRecord(
          id: 'checklist',
          label: 'Checklist',
          title: 'Surgical checklist',
          icon: RecIcons.checklist,
          detail: 'Surgical safety checklist, one per surgery.',
          status: checklists.isEmpty
              ? null
              : openChecklists > 0
              ? '$openChecklists open'
              : '${checklists.length} done',
          tone: openChecklists > 0 ? RecordTone.warn : RecordTone.done,
          onOpen: () => showChecklistDialog(context, p),
        ),
        ChartRecord(
          id: 'sedation',
          label: 'Sedation',
          title: 'Sedation and pre-op',
          icon: CruIcons.moon,
          detail: 'Pre-op check, fitness and the sedation plan.',
          status: sedation.isEmpty
              ? null
              : sedationStatus.isEmpty
              ? plural(sedation.length, 'case')
              : '${sedationStatus[0].toUpperCase()}${sedationStatus.substring(1)}',
          onOpen: () => dialog(
            PreopDialog(
              patient: p,
              initialCase: sedation.isNotEmpty
                  ? SedationCase.fromRecord(sedation.first)
                  : null,
            ),
          ),
        ),
        ChartRecord(
          id: 'la',
          label: 'LA dose',
          title: 'Anaesthetic dose',
          icon: CruIcons.flask,
          detail: 'Log the drugs given and check the safe limit by weight.',
          action: true,
          onOpen: () => dialog(DrugLogDialog(patient: p)),
        ),
        ChartRecord(
          id: 'consent',
          label: 'Consents',
          icon: RecIcons.consent,
          detail: 'Signed consent forms for procedures.',
          status: consents.isEmpty ? null : '${consents.length} signed',
          tone: consents.isEmpty ? RecordTone.plain : RecordTone.done,
          onOpen: () => showConsentListDialog(context, p),
        ),
        if (child)
          ChartRecord(
            id: 'behaviour',
            label: 'Behaviour',
            icon: RecIcons.frankl,
            detail: 'How the child copes, on the Frankl scale.',
            status: frankl.isEmpty
                ? null
                : 'Frankl ${frankl.first.integer('rating')}',
            onOpen: () => showFranklDialog(context, p),
          ),
      ],
    ),
    (
      label: 'After',
      records: [
        ChartRecord(
          id: 'lab',
          label: 'Lab cases',
          icon: CruIcons.box,
          detail: 'Crowns and dentures at the lab, by stage.',
          status: labCases.isEmpty
              ? null
              : activeLab > 0
              ? '$activeLab active'
              : 'All fitted',
          tone: activeLab > 0 ? RecordTone.warn : RecordTone.done,
          onOpen: () => dialog(PatientLabCasesDialog(patient: p)),
        ),
        ChartRecord(
          id: 'referral',
          label: 'Referrals',
          icon: CruIcons.arrowUpRight,
          detail: 'Referrals sent to other doctors.',
          status: referrals.isEmpty
              ? null
              : openReferrals > 0
              ? '$openReferrals open'
              : 'None open',
          tone: openReferrals > 0 ? RecordTone.warn : RecordTone.plain,
          onOpen: () => dialog(PatientReferralsDialog(patient: p)),
        ),
        ChartRecord(
          id: 'recall',
          label: 'Recall',
          icon: RecIcons.recall,
          detail: 'When the patient should come back, and why.',
          status: nextRecall == null
              ? null
              : DentalFormat.shortDate(nextRecall.recordedAt),
          tone: nextRecall != null && nextRecall.recordedAt.isBefore(now)
              ? RecordTone.warn
              : RecordTone.plain,
          onOpen: () =>
              showSetRecallDialog(context, patient: p, existing: nextRecall),
        ),
      ],
    ),
    (
      label: 'Paper',
      records: [
        ChartRecord(
          id: 'forms',
          label: 'Forms',
          icon: RecIcons.form,
          detail: 'Questionnaires and intake forms you set up.',
          status: forms.isEmpty ? null : '${forms.length} filled',
          onOpen: () => dialog(PatientFormsDialog(patient: p)),
        ),
        ChartRecord(
          id: 'scan',
          label: 'Scan',
          title: 'Scan a document',
          icon: CruIcons.scan,
          detail: 'Scan a paper into notes, records or files.',
          action: true,
          onOpen: () => startScanFlow(
            context,
            patient: p,
            clinical: true,
            inventory: false,
            revenue: false,
          ),
        ),
      ],
    ),
  ];
}

/// The record with [id], if the patient has it.
ChartRecord? findRecord(List<RecordCluster> clusters, String id) {
  for (final c in clusters) {
    for (final r in c.records) {
      if (r.id == id) return r;
    }
  }
  return null;
}

Color _toneColor(CruColors c, RecordTone tone) => switch (tone) {
  RecordTone.plain => c.label2,
  RecordTone.warn => c.amberText,
  RecordTone.done => c.greenText,
};

/// The quick shelf under Charting's header: every record type as a
/// one-tap button with its status, in clusters (exam, treat, after,
/// paperwork). Always the same buttons in the same place; slides
/// sideways when the window is narrow.
class RecordShelf extends StatelessWidget {
  const RecordShelf({super.key, required this.clusters});

  final List<RecordCluster> clusters;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final count = clusters.fold<int>(0, (n, c) => n + c.records.length);
    final dividers = clusters.length - 1;
    return Container(
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control + CruSpace.s4),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s6,
        vertical: CruSpace.s6,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Wider buttons fill a wide window; below 72 px they scroll.
          final room = box.maxWidth - dividers * (1 + CruSpace.s6 * 2);
          final each = count == 0
              ? _ShelfButton.minWidth
              : (room / count).clamp(_ShelfButton.minWidth, 104.0);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < clusters.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: 52,
                      margin: const EdgeInsets.symmetric(
                        horizontal: CruSpace.s6,
                        vertical: CruSpace.s4,
                      ),
                      color: c.separator,
                    ),
                  for (final r in clusters[i].records)
                    _ShelfButton(record: r, width: each),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Every record type as an icon button in a card, for Charting's right
/// panel: the shelf's buttons in a three-across grid, under the cluster
/// names.
class RecordPanel extends StatelessWidget {
  const RecordPanel({super.key, required this.clusters, this.perioKey});

  final List<RecordCluster> clusters;

  /// On the Perio button, so Charting can grow the perio chart from it.
  final GlobalKey? perioKey;

  static const _names = {
    'Exam': 'Exam',
    'Treat': 'Treatment',
    'After': 'After the visit',
    'Paper': 'Paperwork',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // Tight enough to fit Charting's right column whole.
    return CruCard(
      semanticLabel: 'Clinical records',
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: CruSpace.s8),
            child: DetailsCardHeader(title: 'Clinical records'),
          ),
          for (var i = 0; i < clusters.length; i++) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                CruSpace.s8,
                i == 0 ? CruSpace.s4 : CruSpace.s8,
                CruSpace.s8,
                CruSpace.s4,
              ),
              child: Text(
                _names[clusters[i].label] ?? clusters[i].label,
                style: CruType.groupLabel.tint(c.label3),
              ),
            ),
            LayoutBuilder(
              builder: (context, box) {
                const cols = 3;
                final each = box.maxWidth / cols;
                final all = clusters[i].records;
                return Column(
                  children: [
                    for (var at = 0; at < all.length; at += cols)
                      Builder(
                        builder: (context) {
                          final row = all.sublist(
                            at,
                            (at + cols).clamp(0, all.length),
                          );
                          // A status line only in rows that have one.
                          final status = row.any((r) => r.status != null);
                          return Row(
                            children: [
                              for (final r in row)
                                SizedBox(
                                  key: r.id == 'perio' ? perioKey : null,
                                  width: each,
                                  child: RecordPanelTile(
                                    record: r,
                                    statusLine: status,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// One button in the Clinical records card (also drawn inside Perio's growing box).
///
/// One record in the panel: icon tile, name, and its status in tone.
/// With [statusLine] the status line is kept (blank when there is none)
/// so the row lines up; rows without any status leave it out.
class RecordPanelTile extends StatelessWidget {
  const RecordPanelTile({
    super.key,
    required this.record,
    this.statusLine = true,
  });

  final ChartRecord record;
  final bool statusLine;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final active = record.status != null;
    return Tooltip(
      message: record.detail,
      waitDuration: const Duration(milliseconds: 600),
      child: CruPressable(
        onTap: record.onOpen,
        scaleOnPress: false,
        semanticLabel:
            '${record.label}. ${record.status ?? 'Nothing recorded yet'}',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          padding: const EdgeInsets.all(CruSpace.s4),
          decoration: ShapeDecoration(
            color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
            shape: cruShape(CruRadius.control),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.inset,
                  shape: cruShape(CruRadius.iconTile),
                ),
                child: CruIcon(
                  record.icon,
                  size: 18,
                  strokeWidth: 1.8,
                  color: active ? c.label : c.label2,
                ),
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                record.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: CruType.caption.w500.tint(c.label),
              ),
              if (statusLine || record.status != null)
                Text(
                  record.status ?? ' ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: CruType.micro.tabular.tint(_toneColor(c, record.tone)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfButton extends StatelessWidget {
  const _ShelfButton({required this.record, required this.width});

  static const double minWidth = 72;

  final ChartRecord record;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final active = record.status != null;
    return Tooltip(
      message: record.detail,
      waitDuration: const Duration(milliseconds: 600),
      child: CruPressable(
        onTap: record.onOpen,
        scaleOnPress: false,
        semanticLabel:
            '${record.label}. ${record.status ?? 'Nothing recorded yet'}',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          width: width,
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
          decoration: ShapeDecoration(
            color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
            shape: cruShape(CruRadius.control),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: active ? c.inset : null,
                  shape: cruShape(
                    CruRadius.iconTile,
                    side: active
                        ? BorderSide.none
                        : BorderSide(color: c.separator),
                  ),
                ),
                child: CruIcon(
                  record.icon,
                  size: 16,
                  strokeWidth: 1.8,
                  color: active ? c.label : c.label3,
                ),
              ),
              const SizedBox(height: CruSpace.s2),
              Text(
                record.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (active ? CruType.micro.w600 : CruType.micro).tint(
                  active ? c.label : c.label2,
                ),
              ),
              Text(
                record.status ?? ' ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.micro.tabular.tint(_toneColor(c, record.tone)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Records as cards in a workspace: icon, name, status, what it is, and
/// Open. Two or three across when there is room.
class RecordGrid extends StatelessWidget {
  const RecordGrid({super.key, required this.records});

  final List<ChartRecord> records;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = (box.maxWidth / 300).floor().clamp(1, 3);
        final width =
            (box.maxWidth - CruSpace.cardGap * (columns - 1)) / columns;
        return Wrap(
          spacing: CruSpace.cardGap,
          runSpacing: CruSpace.cardGap,
          children: [
            for (final r in records)
              SizedBox(
                width: width,
                child: _RecordCard(record: r),
              ),
          ],
        );
      },
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final ChartRecord record;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final r = record;
    return CruPressable(
      onTap: r.onOpen,
      scaleOnPress: false,
      semanticLabel: '${r.label}. ${r.status ?? 'Nothing recorded yet'}',
      builder: (context, hovered) => CruCard(
        semanticLabel: r.label,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: CruSize.iconTile,
                  height: CruSize.iconTile,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: c.inset,
                    shape: cruShape(CruRadius.iconTile),
                  ),
                  child: CruIcon(
                    r.icon,
                    size: 18,
                    strokeWidth: 1.8,
                    color: c.label,
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title ?? r.label,
                        style: CruType.callout.w600.tint(c.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!r.action)
                        Text(
                          r.status ?? 'Nothing recorded yet',
                          style: CruType.subhead.tabular.tint(
                            r.status == null ? c.label3 : _toneColor(c, r.tone),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
              ],
            ),
            const SizedBox(height: CruSpace.s10),
            Text(
              r.detail,
              style: CruType.subhead.tint(c.label2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// An action card for Wrap-up (prescription, bill, certificate…): icon,
/// name and one line.
class ActionTile {
  const ActionTile(this.label, this.icon, this.detail, this.onTap);
  final String label;
  final CruIconData icon;
  final String detail;
  final VoidCallback onTap;

  ChartRecord asRecord() => ChartRecord(
    id: label,
    label: label,
    icon: icon,
    detail: detail,
    onOpen: onTap,
    action: true,
  );
}
