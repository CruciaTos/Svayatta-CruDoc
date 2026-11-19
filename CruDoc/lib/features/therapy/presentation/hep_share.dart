import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/data/exercise_library.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';

ExerciseDef? _find(List<ExerciseDef> catalog, HepItem i) =>
    catalog.where((e) => e.id == i.exerciseId).firstOrNull;

/// The program as plain text, for WhatsApp.
String hepText({
  required Patient patient,
  required HepProgram program,
  required List<ExerciseDef> catalog,
  String? doctorName,
}) {
  final b = StringBuffer()
    ..writeln('Hello ${patient.firstName}, here is your home exercise program.')
    ..writeln();
  var n = 1;
  for (final i in program.items) {
    b.writeln('$n. ${i.name}');
    b.writeln('   ${i.doseText}');
    final link = _find(catalog, i)?.videoLink;
    if (link != null) b.writeln('   Video: $link');
    n++;
  }
  if (program.note.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln(program.note.trim());
  }
  b
    ..writeln()
    ..writeln(
      'Stop and call us if you feel sharp pain, dizziness, numbness or tingling.',
    );
  if (doctorName != null && doctorName.trim().isNotEmpty) {
    b.writeln('- $doctorName');
  }
  return b.toString().trim();
}

/// Opens WhatsApp with the program text; falls back to the share sheet when
/// the patient has no usable phone number.
Future<void> sendHepWhatsApp(
  BuildContext context, {
  required Patient patient,
  required HepProgram program,
  required List<ExerciseDef> catalog,
  String? doctorName,
}) async {
  final text = hepText(
    patient: patient,
    program: program,
    catalog: catalog,
    doctorName: doctorName,
  );
  final url = WhatsAppTemplateService.buildDirectWhatsAppUrl(
    rawPhone: patient.phone,
    message: text,
  );
  if (url != null) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } else {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}

Future<Uint8List> buildHepPdf({
  required Patient patient,
  required HepProgram program,
  required List<ExerciseDef> catalog,
  String? doctorName,
}) async {
  final doc = pw.Document();
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  final items = <pw.Widget>[];
  var n = 1;
  for (final i in program.items) {
    final e = _find(catalog, i);
    pw.MemoryImage? img;
    final path = e?.photoPath;
    if (path != null && File(path).existsSync()) {
      try {
        img = pw.MemoryImage(File(path).readAsBytesSync());
      } catch (_) {}
    }
    items.add(
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (img != null)
              pw.Container(
                width: 110,
                height: 110,
                margin: const pw.EdgeInsets.only(right: 12),
                child: pw.Image(img, fit: pw.BoxFit.cover),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '$n. ${i.name}',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(i.doseText, style: bold),
                  if (e != null) ...[
                    pw.SizedBox(height: 6),
                    for (var s = 0; s < e.steps.length; s++)
                      pw.Text(
                        '${s + 1}. ${e.steps[s]}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      e.cautions,
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                    if (e.videoLink != null)
                      pw.Text(
                        'Video: ${e.videoLink}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    n++;
  }
  doc.addPage(
    pw.MultiPage(
      margin: const pw.EdgeInsets.all(36),
      build: (_) => [
        pw.Text(
          program.title.isEmpty ? 'Home exercise program' : program.title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${patient.fullName}  |  ${DentalFormat.date(program.date)}'
          '${doctorName != null ? '  |  $doctorName' : ''}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 14),
        if (program.note.trim().isNotEmpty) ...[
          pw.Text(program.note.trim()),
          pw.SizedBox(height: 14),
        ],
        ...items,
      ],
    ),
  );
  return doc.save();
}

/// Shares the program as a PDF (share sheet on phones, save/share on PC).
Future<void> shareHepPdf(
  BuildContext context, {
  required Patient patient,
  required HepProgram program,
  required List<ExerciseDef> catalog,
  String? doctorName,
}) async {
  final bytes = await buildHepPdf(
    patient: patient,
    program: program,
    catalog: catalog,
    doctorName: doctorName,
  );
  final name = 'Home exercises - ${patient.fullName}.pdf';
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
