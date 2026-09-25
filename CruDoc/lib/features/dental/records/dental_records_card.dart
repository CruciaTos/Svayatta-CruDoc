import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/clinical_forms.dart';
import 'package:doctor_management_app/features/dental/records/consent_dialog.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/endo_dialog.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/dental/records/srp_dialog.dart';
import 'package:doctor_management_app/features/dental/specialties/oralmed/oralmed_history.dart';
import 'package:doctor_management_app/features/dental/specialties/pedo/eruption_chart.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_dialogs.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_dialog.dart';
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
    final om = omHistoryOf(of(RecKind.omHistory));
    final allergy = omAllergyText(om);
    final eruptionRecords = of(RecKind.eruption);
    final eruption = eruptionCardLine(
      eruptionRecords.isEmpty ? null : eruptionRecords.first,
      patient,
    );
    final referrals = of(RecKind.referral);
    final openReferrals = referrals
        .where((r) => r.str('status') != 'completed' && r.str('status') != 'declined')
        .toList();
    final referralLine = referrals.isEmpty
        ? 'No referrals yet'
        : () {
            final openCount = openReferrals.length;
            final last = referrals.first;
            final lastContact = last.str('contactName');
            final countStr = openCount == 0 ? 'None open' : '$openCount open';
            return lastContact.isNotEmpty
                ? '$countStr · last ${last.str('direction') == 'in' ? 'from' : 'to'} $lastContact'
                : countStr;
          }();
    final labCases = of(RecKind.labCase);
    final openLabCases = labCases.where((r) => r.str('stage') != 'fitted').toList();
    final labCaseLine = labCases.isEmpty
        ? 'No lab cases'
        : () {
            final openCount = openLabCases.length;
            final last = labCases.first;
            final type = last.str('type').isNotEmpty ? last.str('type') : 'Case';
            final stage = last.str('stage');
            final countStr = openCount == 0 ? 'None active' : '$openCount active';
            return '$countStr · last $type (${stage.isNotEmpty ? stage : 'scanned'})';
          }();

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
      String? alert,
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
                Text.rich(
                  TextSpan(
                    children: [
                      // Allergies in red: patient safety.
                      if (alert != null)
                        TextSpan(
                          text: '$alert · ',
                          style: CruType.subhead.w600.tint(c.redText),
                        ),
                      TextSpan(text: detail),
                    ],
                  ),
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
          row(
            RecIcons.consent,
            'Oral medicine history',
            omCardLine(om),
            () => showOmHistoryDialog(context, patient, existing: om),
            warn: omHighRisk(om),
            alert: allergy == null || allergy == 'None' ? null : 'Allergic to $allergy',
          ),
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
            CruIcons.arrowUpRight,
            'Referrals',
            referralLine,
            () => showDialog<void>(
              context: context,
              builder: (_) => PatientReferralsDialog(patient: patient),
            ),
          ),
          row(
            CruIcons.box,
            'Lab cases',
            labCaseLine,
            () => showDialog<void>(
              context: context,
              builder: (_) => PatientLabCasesDialog(patient: patient),
            ),
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
          if (child)
            row(
              DentalIcons.tooth,
              'Eruption',
              eruption.text,
              () => showEruptionDialog(
                context,
                patient,
                existing: eruptionRecords.isEmpty ? null : eruptionRecords.first,
              ),
              warn: eruption.warn,
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
