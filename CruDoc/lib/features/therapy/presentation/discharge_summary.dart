import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:doctor_management_app/core/pdf/data/doc_numbering.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';
import 'package:doctor_management_app/features/therapy/data/outcome_scale_registry.dart';
import 'package:doctor_management_app/features/therapy/domain/modality_models.dart';
import 'package:doctor_management_app/features/therapy/domain/outcome_score_models.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_assess_models.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/progress_report.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Discharging a patient: the progress report, closed off, and optionally
/// addressed to the doctor who referred them.
///
/// Built from the same sections as the progress report, because a referrer is
/// owed the same facts as the patient rather than a different version of
/// them. Everything the app cannot know — whether care is finished, how it
/// finished, what to do next — is typed by the physio.

/// How a referring doctor is named on a letter.
///
/// Name and clinic only. The letter is handed to the patient, so the
/// referrer's phone number and e-mail address stay in the referral contacts
/// where they belong and never travel on a document that leaves the clinic.
String referrerLabel(ReferralContact x) {
  final parts = [
    x.name.trim(),
    if (x.clinic.trim().isNotEmpty) x.clinic.trim(),
  ];
  return parts.where((s) => s.isNotEmpty).join(', ');
}

/// Collects the discharge details, then builds and shares the summary.
///
/// Returns true once a document has been produced.
Future<bool> shareDischargeSummary(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
) async {
  final note = await showModalBottomSheet<DischargeNote>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DischargeSheet(patient: patient),
  );
  if (note == null || !context.mounted) return false;

  Future<List<DentalRecord>> load(String kind) => ref.read(
    patientRecordsProvider((patientId: patient.id, kind: kind)).future,
  );
  final progress = progressEntries(await load(RecKind.physioProgress));
  final rom = romAssessments(await load(RecKind.physioRom));
  final programs = [
    for (final r in await load(RecKind.physioHep)) HepProgram.fromRecord(r),
  ]..sort((a, b) => b.date.compareTo(a.date));
  final packages = sessionPackages(await load(RecKind.physioPackage));
  final goals = physioGoals(await load(RecKind.physioGoal));
  final modalities = modalityApplications(await load(RecKind.physioModality));
  final scaleRecs = await load(RecKind.physioScaleScore);
  final scales = await ref.read(outcomeScalesProvider.future);
  final scaleTrends = [
    for (final s in scales.scales)
      if (scaleTrend(s, scaleRecs) case final t when t.isNotEmpty) t,
  ];

  // Numbered as a medical report rather than a referral: the REF sequence
  // belongs to the dental referral letters, and sharing it would interleave
  // two unrelated runs of numbers.
  String? docNumber;
  try {
    docNumber = await DocNumbering.next(DocKind.report, note.on);
  } catch (_) {
    // A document without a number is still worth having.
  }

  final bytes = await buildProgressReportPdf(
    patient: patient,
    progress: progress,
    rom: rom,
    program: programs.firstOrNull,
    package: packages.firstOrNull,
    goals: goals,
    modalities: modalities,
    scaleTrends: scaleTrends,
    doctorName: ref.read(doctorIdentityProvider).fullName,
    discharge: note,
    documentNumber: docNumber,
  );

  final who = note.isLetter ? 'letter' : 'summary';
  final name = 'Discharge $who - ${patient.fullName}.pdf';
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
      ),
    );
  } else {
    await Printing.sharePdf(bytes: bytes, filename: name);
  }
  return true;
}

class _DischargeSheet extends ConsumerStatefulWidget {
  const _DischargeSheet({required this.patient});

  final Patient patient;

  @override
  ConsumerState<_DischargeSheet> createState() => _DischargeSheetState();
}

class _DischargeSheetState extends ConsumerState<_DischargeSheet> {
  final _outcome = TextEditingController();
  final _advice = TextEditingController();
  DateTime _on = DateTime.now();

  /// Null means the patient's own copy, with no addressee.
  ReferralContact? _to;

  @override
  void dispose() {
    _outcome.dispose();
    _advice.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDentalDate(
      context,
      initial: _on,
      last: DateTime.now(),
    );
    if (picked != null) setState(() => _on = picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final contacts = ref.watch(referralContactsProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          0,
          CruSpace.s16,
          CruSpace.s16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Discharge summary', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s4),
              Text(
                'The progress, range of motion and sessions already recorded '
                'are included. Only what CruDoc cannot know goes here.',
                style: CruType.caption.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s16),
              CruCapsuleButton(
                label: 'Care ended ${DentalFormat.date(_on)}',
                icon: CruIcons.calendar,
                onPressed: _pickDate,
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Outcome',
                controller: _outcome,
                hint: 'How the episode of care finished',
                maxLines: 2,
              ),
              const SizedBox(height: CruSpace.s12),
              CruTextField(
                label: 'Advice on discharge',
                controller: _advice,
                hint: 'What the patient should carry on doing',
                maxLines: 2,
              ),
              const SizedBox(height: CruSpace.s16),
              CruDropdownField<String>(
                label: 'Address it to',
                value: _to?.id ?? '',
                items: ['', for (final x in contacts) x.id],
                itemLabel: (id) => id.isEmpty
                    ? "The patient's own copy"
                    : referrerLabel(contacts.firstWhere((x) => x.id == id)),
                help: _to == null
                    ? null
                    : 'A copy for the referring doctor, handed to the patient.',
                onChanged: (id) => setState(() {
                  _to = id.isEmpty
                      ? null
                      : contacts.firstWhere((x) => x.id == id);
                }),
              ),
              const SizedBox(height: CruSpace.s20),
              CruButton(
                label: 'Create summary',
                expand: true,
                onPressed: () => Navigator.of(context).pop(
                  DischargeNote(
                    on: _on,
                    outcome: _outcome.text,
                    advice: _advice.text,
                    addressedTo: _to == null ? '' : referrerLabel(_to!),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
