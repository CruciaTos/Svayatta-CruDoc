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
import 'package:doctor_management_app/features/dental/specialties/anaesthesia/preop_dialog.dart';
import 'package:doctor_management_app/features/dental/specialties/ortho/ortho_photos.dart';
import 'package:doctor_management_app/features/dental/specialties/forms/form_fill.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/treatment_plan_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The dentist's clinical records on Patient details, as an icon grid.
/// Tiles stay in one fixed order. A tile with records is active (filled
/// icon, bold name, a short status); one with nothing yet is quiet.
/// Every tile opens its record.
class DentalRecordsCard extends ConsumerWidget {
  const DentalRecordsCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    // One query for every kind, so the card stays light on Patient details.
    final byKind =
        ref.watch(patientRecordsByKindProvider(patient.id)).value ??
        const <String, List<DentalRecord>>{};
    List<DentalRecord> of(String kind) => byKind[kind] ?? const [];
    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    final now = DateTime.now();
    final child = patient.age < 16;

    final om = omHistoryOf(of(RecKind.omHistory));
    final allergy = omAllergyText(om);
    final hasAllergy = allergy != null && allergy != 'None';
    final highRisk = om != null && omHighRisk(om);

    // Declined and deleted items dropped, as on the rest of Patient details.
    final planItems = DentalPlan.active(
      ref.watch(patientTreatmentPlanProvider(patient.id)).value ?? const [],
    );
    final planDone = planItems.where(DentalPlan.isDone).length;

    final perio = of(RecKind.perio);
    final srp = srpTileLine(of(RecKind.srp));

    final endo = of(RecKind.endo);
    final endoOpen = endo.where((r) => r.str('status') != 'obturated').length;
    final endoTeeth = endo
        .map((r) => r.str('tooth'))
        .where((t) => t.isNotEmpty)
        .toSet();

    final recalls =
        of(RecKind.recall).where((r) => recallStatusOf(r).isOpen).toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final nextRecall = recalls.firstOrNull;

    final consents = of(RecKind.consent);
    final referrals = of(RecKind.referral);
    final openReferrals = referrals
        .where(
          (r) =>
              r.str('status') != 'completed' && r.str('status') != 'declined',
        )
        .length;
    final labCases = of(RecKind.labCase);
    final activeLab = labCases.where((r) => r.str('stage') != 'fitted').length;
    final photoSets = of(RecKind.photoSet);
    final sedation = of(RecKind.sedationCase);
    final sedationStatus = sedation.firstOrNull?.str('status') ?? '';
    final forms = of(RecKind.formResponse);

    final pain = of(RecKind.pain);
    final tmd = of(RecKind.tmd);
    final painStatus = pain.isNotEmpty
        ? 'Pain ${(pain.first.number('score') ?? 0).toStringAsFixed(0)}'
              '${pain.first.str('scale') == 'VAS' ? ' mm' : '/10'}'
        : tmd.isNotEmpty
        ? 'TMD ${tmd.first.integer('score')}/7'
        : null;

    final frankl = of(RecKind.frankl);
    final eruptionRecord = of(RecKind.eruption).firstOrNull;
    final eruption = eruptionCardLine(eruptionRecord, patient);
    final checklists = of(RecKind.checklist);
    final openChecklists = checklists
        .where((r) => r.data['complete'] != true)
        .length;

    final tiles = <_RecTile>[
      _RecTile(
        icon: RecIcons.history,
        name: 'Medical history',
        status: om == null
            ? null
            : hasAllergy
            ? 'Allergy'
            : highRisk
            ? 'High risk'
            : 'Recorded',
        tone: hasAllergy
            ? _Tone.alert
            : highRisk
            ? _Tone.warn
            : _Tone.plain,
        onTap: () => showOmHistoryDialog(context, patient, existing: om),
      ),
      _RecTile(
        icon: DentalIcons.plan,
        name: 'Treatment plan',
        status: planItems.isEmpty
            ? null
            : '$planDone of ${planItems.length} done',
        onTap: () async {
          await showTreatmentPlanDialog(context, patient: patient);
          ref.invalidate(patientTreatmentPlanProvider(patient.id));
        },
      ),
      _RecTile(
        icon: RecIcons.perio,
        name: 'Perio chart',
        status: perio.isEmpty
            ? null
            : DentalFormat.shortDate(perio.first.recordedAt),
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => Theme(
              data: Theme.of(context),
              child: PerioChartScreen(patient: patient),
            ),
          ),
        ),
      ),
      _RecTile(
        icon: RecIcons.srp,
        name: 'Root planing',
        status: srp.text,
        tone: srp.warn ? _Tone.warn : _Tone.plain,
        onTap: () => showSrpDialog(context, patient),
      ),
      _RecTile(
        icon: RecIcons.endo,
        name: 'Endodontics',
        status: endo.isEmpty
            ? null
            : endoOpen > 0
            ? '$endoOpen ongoing'
            : endoTeeth.length == 1
            ? 'Tooth ${endoTeeth.first}'
            : endoTeeth.isEmpty
            ? plural(endo.length, 'record')
            : '${endoTeeth.length} teeth',
        onTap: () => showEndoListDialog(context, patient),
      ),
      _RecTile(
        icon: RecIcons.recall,
        name: 'Recall',
        status: nextRecall == null
            ? null
            : 'Due ${DentalFormat.shortDate(nextRecall.recordedAt)}',
        tone: nextRecall != null && nextRecall.recordedAt.isBefore(now)
            ? _Tone.warn
            : _Tone.plain,
        onTap: () => showSetRecallDialog(
          context,
          patient: patient,
          existing: nextRecall,
        ),
      ),
      _RecTile(
        icon: RecIcons.consent,
        name: 'Consents',
        status: consents.isEmpty ? null : '${consents.length} signed',
        onTap: () => showConsentListDialog(context, patient),
      ),
      _RecTile(
        icon: CruIcons.arrowUpRight,
        name: 'Referrals',
        status: referrals.isEmpty
            ? null
            : openReferrals > 0
            ? '$openReferrals open'
            : 'None open',
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => PatientReferralsDialog(patient: patient),
        ),
      ),
      _RecTile(
        icon: CruIcons.flask,
        name: 'Lab cases',
        status: labCases.isEmpty
            ? null
            : activeLab > 0
            ? '$activeLab active'
            : 'All fitted',
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => PatientLabCasesDialog(patient: patient),
        ),
      ),
      _RecTile(
        icon: RecIcons.camera,
        name: 'Ortho photos',
        status: photoSets.isEmpty ? null : '${photoSets.length} series',
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => OrthoPhotosDialog(patient: patient),
        ),
      ),
      _RecTile(
        icon: CruIcons.moon,
        name: 'Sedation & pre-op',
        status: sedation.isEmpty
            ? null
            : sedationStatus.isEmpty
            ? plural(sedation.length, 'case')
            : '${sedationStatus[0].toUpperCase()}${sedationStatus.substring(1)}',
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => PreopDialog(
            patient: patient,
            initialCase: sedation.isNotEmpty
                ? SedationCase.fromRecord(sedation.first)
                : null,
          ),
        ),
      ),
      _RecTile(
        icon: RecIcons.form,
        name: 'Forms',
        status: forms.isEmpty ? null : '${forms.length} filled',
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => PatientFormsDialog(patient: patient),
        ),
      ),
      _RecTile(
        icon: RecIcons.pain,
        name: 'Pain and TMD',
        status: painStatus,
        onTap: () => showPainDialog(context, patient),
      ),
      if (child)
        _RecTile(
          icon: RecIcons.frankl,
          name: 'Behaviour',
          status: frankl.isEmpty
              ? null
              : 'Frankl ${frankl.first.integer('rating')}',
          onTap: () => showFranklDialog(context, patient),
        ),
      if (child)
        _RecTile(
          icon: DentalIcons.tooth,
          name: 'Eruption',
          status: eruptionTeethOf(eruptionRecord).isEmpty
              ? null
              : eruption.warn
              ? 'Flagged'
              : 'Charted',
          tone: eruption.warn ? _Tone.warn : _Tone.plain,
          onTap: () =>
              showEruptionDialog(context, patient, existing: eruptionRecord),
        ),
      _RecTile(
        icon: RecIcons.checklist,
        name: 'Surgical checklists',
        status: checklists.isEmpty
            ? null
            : openChecklists > 0
            ? '$openChecklists open'
            : '${checklists.length} done',
        tone: openChecklists > 0 ? _Tone.warn : _Tone.plain,
        onTap: () => showChecklistDialog(context, patient),
      ),
    ];

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
          const SizedBox(height: CruSpace.s12),
          LayoutBuilder(
            builder: (context, box) {
              // About 76 px a tile: four across on a phone, more when wide.
              final columns = (box.maxWidth / 76).floor().clamp(4, 8);
              final width = box.maxWidth / columns;
              return Wrap(
                runSpacing: CruSpace.s4,
                children: [
                  for (final t in tiles) SizedBox(width: width, child: t),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Status colour: plain, amber (waiting or overdue), red (allergy only).
enum _Tone { plain, warn, alert }

/// One record in the grid: icon, name, and a status when it has records.
class _RecTile extends StatelessWidget {
  const _RecTile({
    required this.icon,
    required this.name,
    required this.status,
    required this.onTap,
    this.tone = _Tone.plain,
  });

  final CruIconData icon;
  final String name;

  /// Null when nothing is recorded yet: the tile is quiet.
  final String? status;
  final VoidCallback onTap;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final active = status != null;
    final statusColor = switch (tone) {
      _Tone.plain => c.label2,
      _Tone.warn => c.amberText,
      _Tone.alert => c.redText,
    };
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: '$name. ${status ?? 'Nothing recorded yet'}',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s4,
          vertical: CruSpace.s8,
        ),
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Column(
          children: [
            Container(
              width: CruSize.iconTile,
              height: CruSize.iconTile,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: active ? c.inset : null,
                shape: cruShape(
                  CruRadius.iconTile,
                  side: active
                      ? BorderSide.none
                      : BorderSide(color: c.hairline),
                ),
              ),
              child: CruIcon(
                icon,
                size: 18,
                strokeWidth: 1.8,
                color: active ? c.label : c.label3,
              ),
            ),
            const SizedBox(height: CruSpace.s4),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: active
                  ? CruType.caption.w600.tint(c.label)
                  : CruType.caption.tint(c.label2),
            ),
            if (active)
              Text(
                status!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.micro.tabular.tint(statusColor),
              ),
          ],
        ),
      ),
    );
  }
}
