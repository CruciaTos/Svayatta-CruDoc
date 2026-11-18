import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';

/// One-page prescription slip for a homeopathy dose plan. Plain values in,
/// so it does not depend on the dose plan card.
Future<Uint8List> buildHomeoPrescriptionSlip({
  required String clinicName,
  required String doctorName,
  required String patientName,
  int? patientAge,
  required DateTime date,
  required String remedy,
  required String potency,
  required String dosing,
  DateTime? reviewOn,
  String instructions = '',
  required String antidoteLine,
}) async {
  final doc = pw.Document();
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  pw.Widget field(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (clinicName.isNotEmpty)
            pw.Text(
              clinicName,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          if (doctorName.isNotEmpty) pw.Text(doctorName),
          pw.SizedBox(height: 8),
          pw.Container(height: 0.6, color: PdfColors.grey500),
          pw.SizedBox(height: 16),
          pw.Text(
            'Prescription',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '$patientName${patientAge != null ? ', $patientAge yrs' : ''}'
            '  |  ${DentalFormat.date(date)}',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 20),
          field('Remedy', remedy),
          if (potency.isNotEmpty) field('Potency', potency),
          field('How to take', dosing),
          if (instructions.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text(instructions),
            ),
          if (reviewOn != null) field('Review on', DentalFormat.date(reviewOn)),
          pw.SizedBox(height: 12),
          pw.Text(
            antidoteLine,
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          pw.Spacer(),
          if (doctorName.isNotEmpty)
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 160,
                    height: 0.6,
                    color: PdfColors.grey700,
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(doctorName, style: bold),
                ],
              ),
            ),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Share sheet on phones, save/print on PC.
Future<void> shareHomeoPrescriptionSlip(
  Uint8List bytes, {
  required String patientName,
}) async {
  final name = 'Prescription - $patientName.pdf';
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
      ),
    );
  } else {
    await Printing.sharePdf(bytes: bytes, filename: name);
  }
}
