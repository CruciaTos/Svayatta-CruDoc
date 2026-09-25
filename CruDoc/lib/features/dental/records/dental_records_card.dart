import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/clinical_forms.dart';
import 'package:doctor_management_app/features/dental/records/consent_dialog.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/endo_dialog.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/dental/records/srp_dialog.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The dentist's clinical records on Patient details: perio chart, endo,
/// consents, recall, pain and TMD, behaviour (children) and surgical
/// checklists. Each row says what's there and opens it.
class DentalRecordsCard extends ConsumerWidget {
  const DentalRecordsCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    List<DentalRecord> of(String kind) =>
        ref
            .watch(patientRecordsProvider((patientId: patient.id, kind: kind)))
            .value ??
        const <DentalRecord>[];
    final perio = of(RecKind.perio);
    final srp = srpCardLine(of(RecKind.srp));
    final endo = of(RecKind.endo);
    final consents = of(RecKind.consent);
    final recalls =
        of(RecKind.recall).where((r) => recallStatusOf(r).isOpen).toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final pain = of(RecKind.pain);
    final tmd = of(RecKind.tmd);
    final frankl = of(RecKind.frankl);
    final checklists = of(RecKind.checklist);
    final child = patient.age < 16;

    final perioLine = perio.isEmpty
        ? 'No exam yet'
        : () {
            final s = perioSummaryOf(perio.first);
            return s.sites == 0
                ? 'Last ${DentalFormat.date(perio.first.recordedAt)} · empty'
                : 'Last ${DentalFormat.date(perio.first.recordedAt)} · PD ${s.meanPd!.toStringAsFixed(1)} mm · '
                      'bleeding ${s.bopPct!.toStringAsFixed(0)}%';
          }();
    final painLine = [
      if (pain.isNotEmpty)
        'Pain ${(pain.first.number('score') ?? 0).toStringAsFixed(0)}${pain.first.str('scale') == 'VAS' ? ' mm' : '/10'}',
      if (tmd.isNotEmpty) 'TMD screen ${tmd.first.integer('score')}/7',
    ].join(' · ');

    Widget row(
      CruIconData icon,
      String title,
      String detail,
      VoidCallback onTap, {
      bool warn = false,
    }) => DentalListRow(
      semanticLabel: '$title. $detail',
      onTap: onTap,
      minHeight: 52,
      child: Row(
        children: [
          CruIconTile(icon: icon, tone: CruTileTone.neutral),
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
                  style: CruType.subhead.tabular.tint(
                    warn ? c.amberText : c.label2,
                  ),
                ),
              ],
            ),
          ),
          CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
        ],
      ),
    );

    final now = DateTime.now();
    final nextRecall = recalls.firstOrNull;
    return CruCard(
      semanticLabel: 'Clinical records',
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
            child: Text(
              'Clinical records',
              style: CruType.headline.tint(c.label),
            ),
          ),
          const SizedBox(height: CruSpace.s8),
          row(RecIcons.perio, 'Perio chart', perioLine, () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                builder: (_) => Theme(
                  data: Theme.of(context),
                  child: PerioChartScreen(patient: patient),
                ),
              ),
            );
          }),
          row(
            RecIcons.checklist,
            'Root planing',
            srp.text,
            () => showSrpDialog(context, patient),
            warn: srp.warn,
          ),
          row(
            RecIcons.endo,
            'Endodontics',
            endoCardLine(endo),
            () => showEndoListDialog(context, patient),
          ),
          row(
            RecIcons.recall,
            'Recall',
            nextRecall == null
                ? 'None set'
                : '${nextRecall.str('reason')} · due ${DentalFormat.date(nextRecall.recordedAt)}',
            () => showSetRecallDialog(
              context,
              patient: patient,
              existing: nextRecall,
            ),
            warn: nextRecall != null && nextRecall.recordedAt.isBefore(now),
          ),
          row(
            RecIcons.consent,
            'Consents',
            consents.isEmpty
                ? 'None signed'
                : '${consents.length} signed · last ${consents.first.str('title').toLowerCase()}',
            () => showConsentListDialog(context, patient),
          ),
          row(
            RecIcons.pain,
            'Pain and TMD',
            painLine.isEmpty ? 'No scores yet' : painLine,
            () => showPainDialog(context, patient),
          ),
          if (child)
            row(
              RecIcons.frankl,
              'Behaviour',
              frankl.isEmpty
                  ? 'Not rated yet (Frankl scale)'
                  : '${franklLabel(frankl.first.integer('rating'))} · ${DentalFormat.date(frankl.first.recordedAt)}',
              () => showFranklDialog(context, patient),
            ),
          row(
            RecIcons.checklist,
            'Surgical checklists',
            checklists.isEmpty
                ? 'None yet'
                : '${checklists.length} · last ${DentalFormat.date(checklists.first.recordedAt)}'
                      '${checklists.first.data['complete'] == true ? '' : ' (open)'}',
            () => showChecklistDialog(context, patient),
          ),
        ],
      ),
    );
  }
}
