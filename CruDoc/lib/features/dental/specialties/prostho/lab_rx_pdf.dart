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
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Generates laboratory work prescriptions (Rx) using the unified PDF engine.
class LabRxPdfService {
  static Future<PdfMedicalReportDocumentData> createLabRxDocData({
    required LabCase labCase,
    required Patient patient,
    required ToothNumbering numbering,
  }) async {
    final teethFormatted = labCase.teeth.isEmpty
        ? 'None specified'
        : labCase.teeth.map((t) => toothLabel(t, numbering)).join(', ');

    final sections = <PdfReportSection>[
      PdfReportSection(title: 'Lab Partner', content: labCase.labName),
      PdfReportSection(title: 'Work Type', content: labCase.type),
      PdfReportSection(title: 'Teeth', content: teethFormatted),
      if (labCase.shade.isNotEmpty)
        PdfReportSection(title: 'Shade', content: labCase.shade),
      if (labCase.material.isNotEmpty)
        PdfReportSection(title: 'Material', content: labCase.material),
      if (labCase.notes.isNotEmpty)
        PdfReportSection(
          title: 'Clinical Instructions',
          content: labCase.notes,
        ),
      PdfReportSection(
        title: 'Target Delivery Date',
        content: DentalFormat.date(labCase.due),
      ),
    ];

    final docNum = await DocNumbering.next(DocKind.report, labCase.recordedAt);
    final issuing = defaultIssuingDoctorUid();
    final signer = docSignerFor(issuing);

    return PdfMedicalReportDocumentData(
      reportTitle: 'Laboratory prescription',
      patient: PdfPatientSnapshot(
        fullName: patient.fullName,
        phone: patient.phone.isNotEmpty ? patient.phone : null,
        email: patient.email.isNotEmpty ? patient.email : null,
        ageGender: patient.gender.isNotEmpty
            ? '${patient.age} Y / ${patient.gender}'
            : '${patient.age} Y',
      ),
      documentNumber: docNum,
      documentDate: labCase.recordedAt,
      issuingDoctorUid: issuing,
      signedByUid: signer,
      sections: sections,
    );
  }

  static Future<Uint8List> buildRx({
    required LabCase labCase,
    required Patient patient,
    required String clinicName,
    required String doctorName,
    required ToothNumbering numbering,
  }) async {
    final data = await createLabRxDocData(
      labCase: labCase,
      patient: patient,
      numbering: numbering,
    );
    final rendered = await const MedicalPdfService().render(data);
    return rendered.bytes;
  }

  /// Saves the Rx to the lab cases directory and returns the absolute file path.
  static Future<String> saveRxToFolder({
    required LabCase labCase,
    required Patient patient,
    required WidgetRef ref,
  }) async {
    final numbering =
        ref.read(toothNumberingProvider).value ?? ToothNumbering.fdi;

    final bytes = await buildRx(
      labCase: labCase,
      patient: patient,
      clinicName: '',
      doctorName: '',
      numbering: numbering,
    );

    final appSupport = await getApplicationSupportDirectory();
    final folder = Directory(
      p.join(appSupport.path, 'dental', 'labcases', labCase.id),
    );
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }

    final file = File(p.join(folder.path, 'order.pdf'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Opens the print / preview dialog directly for the Rx.
  static Future<void> printOrPreview({
    required BuildContext context,
    required WidgetRef ref,
    required LabCase labCase,
    required Patient patient,
  }) async {
    final numbering =
        ref.read(toothNumberingProvider).value ?? ToothNumbering.fdi;

    final data = await createLabRxDocData(
      labCase: labCase,
      patient: patient,
      numbering: numbering,
    );

    if (!context.mounted) return;
    await MedicalPdfPreviewScreen.open(context, documentData: data);
  }
}
