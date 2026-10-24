import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/core/pdf/data/doc_numbering.dart';
import 'package:doctor_management_app/core/pdf/models/pdf_document_models.dart';
import 'package:doctor_management_app/core/pdf/presentation/medical_pdf_preview_screen.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context_builder.dart';
import 'package:doctor_management_app/core/pdf/services/medical_pdf_service.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Builds and exports referral letters and treatment summary replies via the unified PDF engine.
class ReferralPdfService {
  static Future<PdfReferralDocumentData> createReferralDocData({
    required DentalReferral referral,
    required Patient patient,
    required ToothNumbering numbering,
    bool isReply = false,
  }) async {
    final teethFormatted = referral.teeth.isEmpty
        ? ''
        : referral.teeth.map((t) => toothLabel(t, numbering)).join(', ');

    final recipientParts = [
      referral.contactName.trim(),
      if (referral.contactSpecialty.trim().isNotEmpty)
        referral.contactSpecialty.trim(),
    ];
    final recipient = recipientParts.where((s) => s.isNotEmpty).join(' · ');

    final docNum = await DocNumbering.next(
      DocKind.referral,
      referral.recordedAt,
    );
    final issuing = defaultIssuingDoctorUid();
    final signer = docSignerFor(issuing);

    return PdfReferralDocumentData(
      recipient: recipient.isNotEmpty ? recipient : 'Specialist',
      reason: referral.reason,
      findings: referral.findings,
      question: referral.question,
      teeth: teethFormatted,
      urgency: referral.urgency.label,
      isReply: isReply,
      reply: referral.reply,
      documentNumber: docNum,
      documentDate: referral.recordedAt,
      issuingDoctorUid: issuing,
      signedByUid: signer,
      patient: PdfPatientSnapshot(
        fullName: patient.fullName,
        phone: patient.phone.isNotEmpty ? patient.phone : null,
        email: patient.email.isNotEmpty ? patient.email : null,
        ageGender: patient.gender.isNotEmpty
            ? '${patient.age} Y / ${patient.gender}'
            : '${patient.age} Y',
      ),
    );
  }

  /// Generates the PDF document for an outgoing referral letter or incoming treatment reply.
  static Future<Uint8List> buildLetter({
    required DentalReferral referral,
    required Patient patient,
    required String clinicName,
    required String doctorName,
    required ToothNumbering numbering,
    bool isReply = false,
  }) async {
    final data = await createReferralDocData(
      referral: referral,
      patient: patient,
      numbering: numbering,
      isReply: isReply,
    );
    final rendered = await const MedicalPdfService().render(data);
    return rendered.bytes;
  }

  /// Saves the letter to the referral directory and returns the absolute file path.
  static Future<String> saveLetterToFolder({
    required DentalReferral referral,
    required Patient patient,
    required WidgetRef ref,
    bool isReply = false,
  }) async {
    final numbering =
        ref.read(toothNumberingProvider).value ?? ToothNumbering.fdi;

    final bytes = await buildLetter(
      referral: referral,
      patient: patient,
      clinicName: '',
      doctorName: '',
      numbering: numbering,
      isReply: isReply,
    );

    final appSupport = await getApplicationSupportDirectory();
    final folder = Directory(
      p.join(appSupport.path, 'dental', 'referrals', referral.id),
    );
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }

    final filename = isReply
        ? 'Referral_Reply_${referral.id.substring(0, referral.id.length.clamp(0, 6))}.pdf'
        : 'Referral_Letter_${referral.id.substring(0, referral.id.length.clamp(0, 6))}.pdf';
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
    final numbering =
        ref.read(toothNumberingProvider).value ?? ToothNumbering.fdi;

    final data = await createReferralDocData(
      referral: referral,
      patient: patient,
      numbering: numbering,
      isReply: isReply,
    );

    if (!context.mounted) return;
    await MedicalPdfPreviewScreen.open(context, documentData: data);
  }
}
