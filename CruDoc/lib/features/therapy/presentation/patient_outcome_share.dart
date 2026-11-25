import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/data/outcome_scale_registry.dart';
import 'package:doctor_management_app/features/therapy/domain/outcome_score_models.dart';
import 'package:doctor_management_app/features/therapy/domain/patient_outcome_summary.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_assess_models.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';

// The patient's own copy of their progress: one page, their numbers, plain
// words.
//
// Shared as a file through the share sheet rather than published at a link.
// A link would be the better keepsake and a worse idea: a URL carrying a
// named patient's clinical scores is their medical information on the open
// internet, and tokens and expiry dates only narrow that, they do not close
// it. A file goes to the person the physio sends it to, through whatever
// they already use, and the clinic keeps no public surface.
//
// There is no document number on it. The numbered sequences belong to
// reports, invoices and referrals — things the clinic has to be able to
// produce again on request. This is a copy of figures that already live in
// the progress report, written for the patient, and numbering it would
// imply it is the record rather than a view of it.

/// Builds the one-page summary.
Future<Uint8List> buildPatientOutcomePdf({
  required Patient patient,
  required PatientOutcomeSummary summary,
  String? clinicName,
  String? doctorName,
}) async {
  final doc = pw.Document();

  final headline = outcomeHeadline(summary);
  final closing = outcomeClosingLine(summary);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if ((clinicName ?? '').trim().isNotEmpty)
            pw.Text(
              clinicName!.trim(),
              style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Your progress',
            style: pw.TextStyle(fontSize: 13, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          // The one line the patient reads. Worded by the summary, which
          // refuses to call it progress when it is not.
          pw.Text(
            headline,
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            patient.fullName,
            style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 24),

          // Every measure, in the same type size, so the flattering one does
          // not get a bigger box than the other.
          for (final line in summary.lines) ...[
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    line.heading,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(line.detail, style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
          ],

          if (summary.goalsTotal > 0) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              summary.goalsReached == summary.goalsTotal
                  ? 'You reached all ${summary.goalsTotal} of the goals you '
                        'set.'
                  : 'You reached ${summary.goalsReached} of the '
                        '${summary.goalsTotal} goals you set.',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ],
          if (summary.sessions > 0)
            pw.Text(
              'Sessions attended: ${summary.sessions}.',
              style: const pw.TextStyle(fontSize: 11),
            ),

          pw.Spacer(),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 6),
          pw.Text(closing, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          // Said plainly, because a sheet of numbers handed to a patient
          // invites them to read it as a verdict.
          pw.Text(
            'These are the scores you gave at your visits, and the measures '
            'taken in the clinic. They describe how you have been, not what '
            'will happen next. Your physiotherapist'
            '${(doctorName ?? '').trim().isEmpty ? '' : ', ${doctorName!.trim()},'} '
            'can explain any of it.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

/// Builds the patient's copy and hands it to the share sheet.
///
/// Returns false, having said why, when there is nothing that can honestly
/// be put on it.
Future<bool> sharePatientOutcomeSummary(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
) async {
  Future<List<DentalRecord>> load(String kind) => ref.read(
    patientRecordsProvider((patientId: patient.id, kind: kind)).future,
  );

  final progress = progressEntries(await load(RecKind.physioProgress));
  final goals = physioGoals(await load(RecKind.physioGoal));
  final scaleRecs = await load(RecKind.physioScaleScore);
  final scales = await ref.read(outcomeScalesProvider.future);
  final scaleTrends = [
    for (final s in scales.scales)
      if (scaleTrend(s, scaleRecs) case final t when t.isNotEmpty) t,
  ];
  final packages = sessionPackages(await load(RecKind.physioPackage));

  final summary = patientOutcomeSummary(
    progress: progress,
    goals: goals,
    scaleTrends: scaleTrends,
    sessions: packages.firstOrNull?.used.length ?? 0,
  );

  if (summary == null) {
    if (context.mounted) {
      // Naming the reason, because "nothing happened" would read as a bug.
      recToast(
        context,
        'Not enough recorded yet for a patient summary — two visits with '
        'scores are needed.',
      );
    }
    return false;
  }

  final identity = ref.read(doctorIdentityProvider);
  final bytes = await buildPatientOutcomePdf(
    patient: patient,
    summary: summary,
    clinicName: identity.clinicName,
    doctorName: identity.fullName,
  );

  final name = 'Your progress - ${patient.fullName}.pdf';
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
