import 'dart:typed_data';

import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pdf_document_models.dart';
import 'pdf_template_theme.dart';

class LetterheadPdfTemplate {
  const LetterheadPdfTemplate({
    required this.config,
    required this.theme,
    this.logoBytes,
  });

  final DoctorLetterheadConfig config;
  final PdfTemplateTheme theme;
  final Uint8List? logoBytes;

  pw.MultiPage page({
    required PdfMedicalDocumentData data,
    required pw.BuildListCallback build,
  }) {
    return pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 34),
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          italic: pw.Font.helveticaOblique(),
          boldItalic: pw.Font.helveticaBoldOblique(),
        ),
      ),
      header: (context) => buildHeader(data),
      footer: buildFooter,
      build: build,
    );
  }

  pw.Widget buildHeader(PdfMedicalDocumentData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _logo(),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    config.clinicName,
                    style: pw.TextStyle(
                      color: theme.darkTextColor,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    config.tagline,
                    style: pw.TextStyle(
                      color: theme.accentColor,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    '${config.doctorName} • ${config.qualifications}',
                    style: pw.TextStyle(
                      color: theme.bodyTextColor,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '${config.specialty} | Reg. No: ${config.registrationNumber}',
                    style: theme.mutedStyle,
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Container(
              width: 140,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: theme.softBackgroundColor,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: theme.borderColor),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    data.type.title.toUpperCase(),
                    style: pw.TextStyle(
                      color: theme.accentColor,
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  _metaLine('No.', data.documentNumber),
                  _metaLine('Date', _formatDate(data.documentDate)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 10),
          decoration: pw.BoxDecoration(
            color: theme.softBackgroundColor,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: theme.borderColor),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Text(
                  'Address: ${config.clinicAddress}',
                  style: theme.mutedStyle,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  'Phone: ${config.clinicPhone}\nEmail: ${config.clinicEmail}',
                  style: theme.mutedStyle,
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          height: 2.2,
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [theme.accentColor, theme.secondaryAccentColor],
            ),
          ),
        ),
        pw.SizedBox(height: 18),
      ],
    );
  }

  pw.Widget buildFooter(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(color: theme.borderColor, height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Text(
                config.footerDisclaimer,
                style: pw.TextStyle(color: theme.mutedTextColor, fontSize: 7.5),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(color: theme.mutedTextColor, fontSize: 7.5),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget signatureBlock() {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 190,
        margin: const pw.EdgeInsets.only(top: 22),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(height: 42),
            pw.Divider(color: theme.borderColor, thickness: 1),
            pw.Text(
              config.doctorName,
              style: pw.TextStyle(
                color: theme.darkTextColor,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${config.qualifications} | Reg: ${config.registrationNumber}',
              style: pw.TextStyle(color: theme.mutedTextColor, fontSize: 7.5),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget patientSummary(PdfPatientSnapshot patient) {
    final details = <String>[
      if (patient.hasAgeGender) patient.ageGender!,
      if (patient.hasPhone) 'Phone: ${patient.phone}',
      if (patient.hasEmail) 'Email: ${patient.email}',
      if (patient.hasPatientId) 'ID: ${patient.patientId}',
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: theme.borderColor),
        color: theme.softBackgroundColor,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 4,
            height: 34,
            decoration: pw.BoxDecoration(
              color: theme.accentColor,
              borderRadius: pw.BorderRadius.circular(3),
            ),
          ),
          pw.SizedBox(width: 9),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Patient', style: theme.mutedStyle),
                pw.SizedBox(height: 3),
                pw.Text(
                  patient.fullName.trim().isEmpty ? 'Patient' : patient.fullName.trim(),
                  style: pw.TextStyle(
                    color: theme.darkTextColor,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(details.join(' • '), style: theme.mutedStyle),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget sectionTitle(String title, {String? subtitle}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Container(width: 4, height: 14, color: theme.accentColor),
          pw.SizedBox(width: 7),
          pw.Text(title, style: theme.sectionTitleStyle),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            pw.SizedBox(width: 6),
            pw.Expanded(child: pw.Text(subtitle, style: theme.mutedStyle)),
          ],
        ],
      ),
    );
  }

  pw.Widget keyValueGrid(List<MapEntry<String, String>> entries) {
    final filtered = entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList(growable: false);
    if (filtered.isEmpty) return pw.SizedBox();

    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filtered
          .map(
            (entry) => pw.Container(
              width: 238,
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: theme.borderColor),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(entry.key, style: theme.mutedStyle),
                  pw.SizedBox(height: 3),
                  pw.Text(entry.value, style: theme.bodyStyle),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  pw.Widget _logo() {
    if (logoBytes != null && logoBytes!.isNotEmpty) {
      return pw.Container(
        width: 58,
        height: 58,
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(12),
          border: pw.Border.all(color: theme.borderColor),
        ),
        child: pw.ClipRRect(
          horizontalRadius: 12,
          verticalRadius: 12,
          child: pw.Image(
            pw.MemoryImage(logoBytes!),
            fit: pw.BoxFit.cover,
          ),
        ),
      );
    }

    return pw.Container(
      width: 58,
      height: 58,
      decoration: pw.BoxDecoration(
        color: theme.softBackgroundColor,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: theme.borderColor),
      ),
      child: pw.Center(
        child: pw.Text(
          '+',
          style: pw.TextStyle(
            color: theme.accentColor,
            fontSize: 28,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  pw.Widget _metaLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: theme.mutedStyle),
          pw.SizedBox(width: 5),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                color: theme.darkTextColor,
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }
}