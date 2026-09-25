import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Generates laboratory work prescriptions (Rx).
class LabRxPdfService {
  static Future<Uint8List> buildRx({
    required LabCase labCase,
    required Patient patient,
    required String clinicName,
    required String doctorName,
    required ToothNumbering numbering,
  }) async {
    final doc = pw.Document();

    final teethFormatted = labCase.teeth.isEmpty
        ? 'None specified'
        : labCase.teeth.map((t) => toothLabel(t, numbering)).join(', ');

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
                        'LAB WORK PRESCRIPTION',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo800,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Order Date: ${DentalFormat.date(labCase.recordedAt)}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 12),

              // Lab Partner & Patient Info Box
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
                            'Laboratory / Technician:',
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            labCase.labName.isNotEmpty ? labCase.labName : 'Dental Laboratory',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Due Date: ${DentalFormat.date(labCase.due)}',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.amber800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Patient:',
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            patient.fullName,
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            'Age: ${patient.age} · Sex: ${patient.gender.toUpperCase()}',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Specifications Table / Grid
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _specItem('Restoration Type', labCase.type),
                        ),
                        pw.Expanded(
                          child: _specItem('Material', labCase.material),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _specItem('Teeth / Units', teethFormatted),
                        ),
                        pw.Expanded(
                          child: _specItem('Shade', '${labCase.shade} (${labCase.shadeSystem})'),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _specItem('Margin Design', labCase.margin),
                        ),
                        pw.Expanded(
                          child: _specItem('Current Status', labCase.stage.label),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Clinical instructions & notes
              if (labCase.notes.trim().isNotEmpty) ...[
                pw.Text(
                  'Instructions & Design Notes:',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey200),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    labCase.notes,
                    style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
                  ),
                ),
                pw.SizedBox(height: 16),
              ],

              // Attached Files
              if (labCase.files.isNotEmpty) ...[
                pw.Text(
                  'Attached Scan & Design Files (${labCase.files.length}):',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                for (final f in labCase.files)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                    child: pw.Text(
                      '• ${f.name} [${f.kind.toUpperCase()}]',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                    ),
                  ),
                pw.SizedBox(height: 16),
              ],

              pw.Spacer(),

              // Doctor Sign-off
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'CruDoc Prosthodontic Lab Rx',
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
                        doctorName.isNotEmpty ? doctorName : 'Prescribing Dentist',
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

  static pw.Widget _specItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value.isNotEmpty ? value : '—',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  /// Saves the Rx PDF to the case directory and returns the absolute file path.
  static Future<String> saveRxToFolder({
    required LabCase labCase,
    required Patient patient,
    required WidgetRef ref,
  }) async {
    final identity = ref.read(doctorIdentityProvider);
    final numbering = ref.read(toothNumberingProvider).value ?? ToothNumbering.fdi;

    final bytes = await buildRx(
      labCase: labCase,
      patient: patient,
      clinicName: identity.clinicName ?? '',
      doctorName: identity.fullName ?? '',
      numbering: numbering,
    );

    final appSupport = await getApplicationSupportDirectory();
    final folder = Directory(p.join(appSupport.path, 'dental', 'labcases', labCase.id));
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
    final identity = ref.read(doctorIdentityProvider);
    final numbering = ref.read(toothNumberingProvider).value ?? ToothNumbering.fdi;

    final bytes = await buildRx(
      labCase: labCase,
      patient: patient,
      clinicName: identity.clinicName ?? '',
      doctorName: identity.fullName ?? '',
      numbering: numbering,
    );

    await Printing.layoutPdf(
      name: 'Lab Rx - ${patient.fullName} - ${labCase.type}',
      onLayout: (_) async => bytes,
    );
  }
}
