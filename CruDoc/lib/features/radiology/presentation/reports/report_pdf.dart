import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:doctor_management_app/core/pdf/models/pdf_document_models.dart';
import 'package:doctor_management_app/core/pdf/templates/pdf_template_theme.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_kit.dart';

/// Who the report comes from, as the letterhead prints it. Only what the
/// profile and the radiology signature actually say: a line the doctor
/// hasn't filled in is left out, never replaced with a stand-in.
class RadLetterhead {
  const RadLetterhead({
    this.clinicName = '',
    this.doctorName = '',
    this.qualification = '',
    this.regNo = '',
    this.address = '',
    this.phone = '',
    this.email = '',
  });

  factory RadLetterhead.from({
    required String? clinicName,
    required String? doctorName,
    required RadSettings settings,
    Map<String, dynamic>? profile,
  }) {
    String p(String key) {
      final v = profile?[key];
      return v is String ? v.trim() : '';
    }

    return RadLetterhead(
      clinicName: (clinicName ?? '').trim(),
      doctorName: settings.signatureName.trim().isNotEmpty
          ? settings.signatureName.trim()
          : (doctorName ?? '').trim(),
      qualification: settings.qualification.trim(),
      regNo: settings.regNo.trim(),
      address: p('clinicAddress'),
      phone: p('clinicPhone'),
      email: p('clinicEmail'),
    );
  }

  final String clinicName;
  final String doctorName;
  final String qualification;
  final String regNo;
  final String address;
  final String phone;
  final String email;
}

/// Everything the PDF prints, gathered by the share helpers.
class RadReportPdfData {
  const RadReportPdfData({
    required this.study,
    required this.report,
    required this.letterhead,
    this.referrer,
    this.measurements = const [],
    this.keyImages = const [],
    this.ceph = const [],
  });

  final RadStudy study;
  final RadReport report;
  final RadLetterhead letterhead;
  final RadReferrer? referrer;

  /// The measurements chosen for the report.
  final List<({String label, String value})> measurements;

  /// The key images chosen for the report, as PNG bytes.
  final List<({String caption, Uint8List png})> keyImages;
  final List<RadCephTable> ceph;
}

// Status colours on paper: amber for "not final yet", red for a critical
// finding (patient safety), as on screen.
const _amberText = PdfColor.fromInt(0xFF92400E);
const _amberFill = PdfColor.fromInt(0xFFFEF3C7);
const _redText = PdfColor.fromInt(0xFF991B1B);
const _redFill = PdfColor.fromInt(0xFFFEE2E2);
const _black = PdfColor.fromInt(0xFF000000);

/// The app's own font (Geist, bundled) so symbols like ±, ×, ° and ² print;
/// Helvetica if the font can't be read.
Future<pw.ThemeData> _fonts() async {
  try {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Geist/Geist-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Geist/Geist-SemiBold.ttf'));
    return pw.ThemeData.withFont(base: regular, bold: bold);
  } catch (_) {
    return pw.ThemeData.withFont(base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
  }
}

/// The report as a letterhead-style A4 PDF, in the look of CruDoc's other
/// medical documents (lib/core/pdf).
Future<Uint8List> buildRadReportPdf(RadReportPdfData d) async {
  final theme = const CleanLetterheadPdfTheme().forDocument(PdfMedicalDocumentType.report);
  final r = d.report;
  final doc = pw.Document(
    title: r.title.trim().isEmpty ? 'Radiology report' : r.title.trim(),
    author: d.letterhead.doctorName,
    creator: 'CruDoc',
    subject: 'Radiology report — ${d.study.patientName}',
  );
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 34),
      theme: await _fonts(),
    ),
    header: (ctx) => ctx.pageNumber == 1 ? _letterhead(d, theme) : _slimHeader(d, theme),
    footer: (ctx) => _footer(ctx, d, theme),
    build: (_) => _body(d, theme),
  ));
  return doc.save();
}

pw.Widget _letterhead(RadReportPdfData d, PdfTemplateTheme t) {
  final l = d.letterhead;
  final contact = [l.address, l.phone, l.email].where((s) => s.isNotEmpty).join('  ·  ');
  final doctor = [
    l.doctorName,
    l.qualification,
  ].where((s) => s.isNotEmpty).join(', ');
  final r = d.report;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (l.clinicName.isNotEmpty)
                  pw.Text(
                    l.clinicName,
                    style: pw.TextStyle(
                      color: t.darkTextColor,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                if (doctor.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    doctor,
                    style: pw.TextStyle(
                      color: t.bodyTextColor,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
                pw.SizedBox(height: 2),
                pw.Text(
                  [
                    'Oral & Maxillofacial Radiology',
                    if (l.regNo.isNotEmpty) 'Reg. No. ${l.regNo}',
                  ].join('  ·  '),
                  style: t.mutedStyle,
                ),
                if (contact.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(contact, style: t.mutedStyle),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Container(
            width: 150,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: t.softBackgroundColor,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: t.borderColor),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'RADIOLOGY REPORT',
                  style: pw.TextStyle(
                    color: t.accentColor,
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                if (d.study.accession.isNotEmpty) _meta(t, 'Accession', d.study.accession),
                _meta(t, 'Date', RadFormat.date(r.signedAt ?? r.updatedAt)),
                _meta(t, 'Status', r.status.label),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Container(
        height: 2.2,
        decoration: pw.BoxDecoration(
          gradient: pw.LinearGradient(colors: [t.accentColor, t.secondaryAccentColor]),
        ),
      ),
      pw.SizedBox(height: 16),
    ],
  );
}

pw.Widget _meta(PdfTemplateTheme t, String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: [
          pw.Text(label, style: t.mutedStyle),
          pw.SizedBox(width: 5),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                color: t.darkTextColor,
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

pw.Widget _slimHeader(RadReportPdfData d, PdfTemplateTheme t) => pw.Column(
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                '${d.study.patientName} · ${d.study.modality.label} · ${RadFormat.date(d.study.studyDate)}',
                style: t.mutedStyle,
              ),
            ),
            pw.Text('Radiology report', style: t.mutedStyle),
          ],
        ),
        pw.Divider(color: t.borderColor, height: 14),
      ],
    );

pw.Widget _footer(pw.Context ctx, RadReportPdfData d, PdfTemplateTheme t) {
  final small = pw.TextStyle(color: t.mutedTextColor, fontSize: 7.5);
  return pw.Column(
    children: [
      pw.Divider(color: t.borderColor, height: 12),
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Radiological findings should be read with the clinical picture. '
              'Made with CruDoc.',
              style: small,
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: small),
        ],
      ),
    ],
  );
}

pw.Widget _heading(PdfTemplateTheme t, String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(width: 3.5, height: 12, color: t.accentColor),
          pw.SizedBox(width: 7),
          pw.Text(title, style: t.sectionTitleStyle),
        ],
      ),
    );

pw.Widget _para(PdfTemplateTheme t, String text) =>
    pw.Text(text.trim(), style: t.bodyStyle.copyWith(lineSpacing: 2.5));

pw.Widget _banner(String text, PdfColor fg, PdfColor bg) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Text(
        text,
        style: pw.TextStyle(color: fg, fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );

pw.Widget _table(
  PdfTemplateTheme t,
  List<String> header,
  List<List<String>> rows, {
  Map<int, pw.TableColumnWidth>? widths,
  Set<int> amberRows = const {},
  int amberColumn = -1,
}) {
  final head = pw.TextStyle(color: t.mutedTextColor, fontSize: 8, fontWeight: pw.FontWeight.bold);
  return pw.Table(
    columnWidths: widths,
    border: pw.TableBorder(horizontalInside: pw.BorderSide(color: t.borderColor, width: 0.6)),
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: t.softBackgroundColor),
        children: [
          for (final h in header)
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(h, style: head)),
        ],
      ),
      for (var i = 0; i < rows.length; i++)
        pw.TableRow(
          children: [
            for (var j = 0; j < rows[i].length; j++)
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(
                  rows[i][j],
                  style: amberRows.contains(i) && j == amberColumn
                      ? t.bodyStyle.copyWith(color: _amberText, fontWeight: pw.FontWeight.bold)
                      : t.bodyStyle,
                ),
              ),
          ],
        ),
    ],
  );
}

List<pw.Widget> _body(RadReportPdfData d, PdfTemplateTheme t) {
  final s = d.study;
  final r = d.report;
  final now = DateTime.now();
  final out = <pw.Widget>[];

  out.add(pw.Text(
    r.title.trim().isEmpty ? '${s.modality.label} report' : r.title.trim(),
    style: t.titleStyle,
  ));
  switch (r.status) {
    case RadReportStatus.draft:
      out.add(_banner('DRAFT: not signed, not for clinical decisions.', _amberText, _amberFill));
    case RadReportStatus.preliminary:
      out.add(_banner(
        'PRELIMINARY REPORT: to be confirmed by the final signed report.',
        _amberText,
        _amberFill,
      ));
    case RadReportStatus.finalised:
      break;
  }
  if (s.critical) {
    final told = s.criticalLog.isEmpty ? null : s.criticalLog.last;
    out.add(_banner(
      told == null
          ? 'CRITICAL FINDING: the referring clinician must be told.'
          : 'CRITICAL FINDING: referring clinician informed ${RadFormat.dateTime(told.at)}'
              '${told.contacted.isEmpty ? '' : ' (${told.contacted})'}.',
      _redText,
      _redFill,
    ));
  }

  // Patient and study.
  final facts = <(String, String)>[
    ('Patient', s.patientName),
    ('Age / sex', RadFormat.patientLine(s, now)),
    ('Patient ID', s.patientExternalId),
    ('Study', [s.modality.label, s.description.trim()].where((e) => e.isNotEmpty).join(' · ')),
    ('Study date', RadFormat.date(s.studyDate)),
    ('Referred by', d.referrer?.display ?? ''),
    ('Clinical question', s.clinicalQuestion.trim()),
  ].where((f) => f.$2.trim().isNotEmpty).toList();
  out.add(pw.SizedBox(height: 12));
  out.add(pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: t.softBackgroundColor,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: t.borderColor),
    ),
    child: pw.Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final (label, value) in facts)
          pw.SizedBox(
            width: label == 'Clinical question' || label == 'Study' ? 490 : 150,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label, style: t.mutedStyle),
                pw.SizedBox(height: 2),
                pw.Text(value, style: t.bodyStyle.copyWith(color: t.darkTextColor)),
              ],
            ),
          ),
      ],
    ),
  ));

  if (r.technique.trim().isNotEmpty) {
    out
      ..add(_heading(t, 'Technique'))
      ..add(_para(t, r.technique));
  }
  for (final sec in r.sections) {
    if (sec.body.trim().isEmpty) continue;
    out
      ..add(_heading(t, sec.title.trim().isEmpty ? 'Findings' : sec.title.trim()))
      ..add(_para(t, sec.body));
  }

  if (r.toothFindings.isNotEmpty) {
    final teeth = r.toothFindings.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 999).compareTo(int.tryParse(b) ?? 999));
    out
      ..add(_heading(t, 'Teeth'))
      ..add(_table(
        t,
        const ['Tooth (FDI)', 'Finding'],
        [for (final n in teeth) [n, r.toothFindings[n]!]],
        widths: const {0: pw.FixedColumnWidth(70), 1: pw.FlexColumnWidth()},
      ));
  }

  for (var i = 0; i < r.lesions.length; i++) {
    final l = r.lesions[i];
    final lines = <(String, String)>[
      ('Location', l.location),
      ('Size (mm)', l.sizeMm),
      ('Shape', l.shape),
      ('Borders', l.borders),
      ('Internal structure', l.internal),
      ('Effects on surrounding structures', l.effects),
      ('Notes', l.notes),
    ].where((e) => e.$2.trim().isNotEmpty).toList();
    if (lines.isEmpty) continue;
    out.add(_heading(t, r.lesions.length == 1 ? 'Lesion' : 'Lesion ${i + 1}'));
    out.add(_table(
      t,
      const ['Descriptor', 'Finding'],
      [for (final (k, v) in lines) [k, v.trim()]],
      widths: const {0: pw.FixedColumnWidth(150), 1: pw.FlexColumnWidth()},
    ));
  }

  if (d.measurements.isNotEmpty) {
    out
      ..add(_heading(t, 'Measurements'))
      ..add(_table(
        t,
        const ['Measurement', 'Value'],
        [for (final m in d.measurements) [m.label, m.value]],
        widths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
      ));
  }

  for (final table in d.ceph) {
    out
      ..add(_heading(
        t,
        table.analysis.isEmpty ? 'Cephalometric analysis' : 'Cephalometric analysis — ${table.analysis}',
      ))
      ..add(_table(
        t,
        const ['Measure', 'Value', 'Norm'],
        [for (final row in table.rows) [row.name, row.value, row.norm]],
        widths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FlexColumnWidth(1.4),
          2: pw.FlexColumnWidth(1.4),
        },
        amberRows: {
          for (var i = 0; i < table.rows.length; i++)
            if (table.rows[i].deviates) i,
        },
        amberColumn: 1,
      ));
  }

  if (d.keyImages.isNotEmpty) {
    out.add(_heading(t, 'Key images'));
    const gap = 12.0;
    final w = (PdfPageFormat.a4.width - 72 - gap) / 2;
    for (var i = 0; i < d.keyImages.length; i += 2) {
      final pair = d.keyImages.sublist(i, i + 2 > d.keyImages.length ? d.keyImages.length : i + 2);
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < pair.length; j++) ...[
              if (j > 0) pw.SizedBox(width: gap),
              pw.SizedBox(
                width: w,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      height: w * 0.72,
                      color: _black,
                      alignment: pw.Alignment.center,
                      child: pw.Image(pw.MemoryImage(pair[j].png), fit: pw.BoxFit.contain),
                    ),
                    if (pair[j].caption.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(pair[j].caption.trim(), style: t.mutedStyle),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ));
    }
  }

  if (r.impression.trim().isNotEmpty) {
    out
      ..add(_heading(t, 'Impression'))
      ..add(pw.Text(
        r.impression.trim(),
        style: t.bodyStyle.copyWith(
          color: t.darkTextColor,
          fontWeight: pw.FontWeight.bold,
          lineSpacing: 2.5,
        ),
      ));
  }
  if (r.recommendations.trim().isNotEmpty) {
    out
      ..add(_heading(t, 'Recommendations'))
      ..add(_para(t, r.recommendations));
  }

  // Signature.
  out.add(pw.SizedBox(height: 18));
  if (r.isSigned) {
    final l = d.letterhead;
    out.add(pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 220,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Divider(color: t.borderColor, thickness: 1),
            pw.Text(
              r.signedBy.isNotEmpty ? r.signedBy : l.doctorName,
              style: pw.TextStyle(
                color: t.darkTextColor,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (l.qualification.isNotEmpty) pw.Text(l.qualification, style: t.mutedStyle),
            if (l.regNo.isNotEmpty) pw.Text('Reg. No. ${l.regNo}', style: t.mutedStyle),
            if (r.signedAt != null)
              pw.Text('Signed electronically ${RadFormat.dateTime(r.signedAt!)}', style: t.mutedStyle),
          ],
        ),
      ),
    ));
  } else {
    out.add(pw.Text('Not signed yet.', style: t.mutedStyle));
  }

  for (final a in r.addenda) {
    out
      ..add(_heading(t, 'Addendum · ${RadFormat.dateTime(a.at)}${a.by.isEmpty ? '' : ' · ${a.by}'}'))
      ..add(_para(t, a.text));
  }
  return out;
}
