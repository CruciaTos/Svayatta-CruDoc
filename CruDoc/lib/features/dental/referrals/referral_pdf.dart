import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Builds and exports referral letters and treatment summary replies.
class ReferralPdfService {
  /// Generates the PDF document for an outgoing referral letter or incoming treatment reply.
  static Future<Uint8List> buildLetter({
    required DentalReferral referral,
    required Patient patient,
    required String clinicName,
    required String doctorName,
    required ToothNumbering numbering,
    bool isReply = false,
  }) async {
    final doc = pw.Document();

    final teethFormatted = referral.teeth.isEmpty
        ? 'None specified'
        : referral.teeth.map((t) => toothLabel(t, numbering)).join(', ');

    final title = isReply ? 'REFERRAL TREATMENT SUMMARY' : 'REFERRAL LETTER';
    final recipientPrefix = isReply ? 'To Referring Doctor:' : 'To:';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        clinicName.isNotEmpty ? clinicName : 'CruDoc Dental Clinic',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                      if (doctorName.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          doctorName,
                          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                        ),
                      ],
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        title,
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: isReply ? PdfColors.blueGrey800 : PdfColors.blue800,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Date: ${DentalFormat.date(referral.recordedAt)}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 12),

              // Recipient / Contact details
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            recipientPrefix,
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            referral.contactName.isNotEmpty
                                ? referral.contactName
                                : 'Specialist / Colleague',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                          if (referral.contactSpecialty.isNotEmpty)
                            pw.Text(
                              referral.contactSpecialty,
                              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                            ),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Patient (Re):',
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            patient.fullName,
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            'Age: ${patient.age} · Sex: ${patient.gender.toUpperCase()} · Phone: ${patient.phone}',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              if (!isReply) ...[
                // Reason & Urgency
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: _itemSection('Reason for referral', referral.reason),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      flex: 1,
                      child: _itemSection('Urgency', referral.urgency.label.toUpperCase()),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),

                // Teeth involved
                _itemSection('Teeth / Region', teethFormatted),
                pw.SizedBox(height: 12),

                // Findings
                if (referral.findings.trim().isNotEmpty) ...[
                  _itemSection('Clinical Findings & Relevant History', referral.findings),
                  pw.SizedBox(height: 12),
                ],

                // Specific question / request
                if (referral.question.trim().isNotEmpty) ...[
                  _itemSection('Specific Evaluation / Treatment Requested', referral.question),
                  pw.SizedBox(height: 12),
                ],
              ] else ...[
                // Reply / Treatment Summary
                _itemSection('Reason for original referral', referral.reason),
                pw.SizedBox(height: 12),
                _itemSection('Teeth / Region', teethFormatted),
                pw.SizedBox(height: 12),
                _itemSection(
                  'Treatment Summary & Outcome',
                  referral.reply.trim().isNotEmpty
                      ? referral.reply
                      : 'Treatment completed as requested.',
                ),
                pw.SizedBox(height: 12),
              ],

              // Attachments list
              if (referral.attachments.isNotEmpty) ...[
                pw.Text(
                  'Attached Files (${referral.attachments.length}):',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                for (final a in referral.attachments)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                    child: pw.Text(
                      '• ${p.basename(a)}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                    ),
                  ),
                pw.SizedBox(height: 16),
              ],

              pw.Spacer(),

              // Sign-off line
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated via CruDoc',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        width: 140,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        doctorName.isNotEmpty ? doctorName : 'Doctor\'s Signature',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _itemSection(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value.isNotEmpty ? value : '—',
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
        ),
      ],
    );
  }

  /// Saves the letter to the referral directory and returns the absolute file path.
  static Future<String> saveLetterToFolder({
    required DentalReferral referral,
    required Patient patient,
    required WidgetRef ref,
    bool isReply = false,
  }) async {
    final identity = ref.read(doctorIdentityProvider);
    final numbering = ref.read(toothNumberingProvider).value ?? ToothNumbering.fdi;

    final bytes = await buildLetter(
      referral: referral,
      patient: patient,
      clinicName: identity.clinicName ?? '',
      doctorName: identity.fullName ?? '',
      numbering: numbering,
      isReply: isReply,
    );

    final appSupport = await getApplicationSupportDirectory();
    final folder = Directory(p.join(appSupport.path, 'dental', 'referrals', referral.id));
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }

    final filename = isReply
        ? 'Referral_Reply_${referral.id.substring(0, 6)}.pdf'
        : 'Referral_Letter_${referral.id.substring(0, 6)}.pdf';
    final file = File(p.join(folder.path, filename));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Opens the print / preview dialog directly for the referral letter.
  static Future<void> printOrPreview({
    required BuildContext context,
    required WidgetRef ref,
    required DentalReferral referral,
    required Patient patient,
    bool isReply = false,
  }) async {
    final identity = ref.read(doctorIdentityProvider);
    final numbering = ref.read(toothNumberingProvider).value ?? ToothNumbering.fdi;

    final bytes = await buildLetter(
      referral: referral,
      patient: patient,
      clinicName: identity.clinicName ?? '',
      doctorName: identity.fullName ?? '',
      numbering: numbering,
      isReply: isReply,
    );

    final title = isReply
        ? 'Referral Reply - ${patient.fullName}'
        : 'Referral Letter - ${patient.fullName}';
    await Printing.layoutPdf(name: title, onLayout: (_) async => bytes);
  }
}
