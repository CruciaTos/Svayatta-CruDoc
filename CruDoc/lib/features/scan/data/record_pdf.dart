import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:doctor_management_app/features/scan/data/scan_capture.dart';
import 'package:doctor_management_app/features/scan/data/scan_reader.dart';

/// A digitised record as one PDF for the patient's files: the typed
/// version first (what it is, the results, the write-up), then the
/// photographed pages themselves, so the original is never lost.
abstract final class RecordPdf {
  static const _ink = PdfColor.fromInt(0xFF0F172A);
  static const _soft = PdfColor.fromInt(0xFF64748B);
  static const _rule = PdfColor.fromInt(0xFFE2E8F0);
  static const _flag = PdfColor.fromInt(0xFFB45309);

  static Future<Uint8List> build({
    required String title,
    required String kind,
    required DateTime? date,
    required String source,
    required String summary,
    required List<RecordFinding> findings,
    required String patientName,
    required List<ScannedPage> pages,
  }) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Geist/Geist-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Geist/Geist-SemiBold.ttf'),
    );
    final doc = pw.Document(
      title: title,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final day = DateFormat('d MMM yyyy');
    final meta = [
      kind,
      if (date != null) day.format(date),
      if (source.isNotEmpty) source,
    ].join('  ·  ');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(44, 44, 44, 40),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Digitised from ${pages.length} scanned '
              '${pages.length == 1 ? 'page' : 'pages'} on '
              '${day.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: _soft),
            ),
            pw.Text(
              '${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _soft),
            ),
          ],
        ),
        build: (ctx) => [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(meta, style: const pw.TextStyle(fontSize: 10, color: _soft)),
          pw.SizedBox(height: 2),
          pw.Text(
            'Patient: $patientName',
            style: const pw.TextStyle(fontSize: 10, color: _soft),
          ),
          pw.SizedBox(height: 12),
          pw.Divider(color: _rule, thickness: 1),
          if (findings.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _heading('Results'),
            pw.SizedBox(height: 6),
            _findings(findings, bold),
            pw.SizedBox(height: 14),
          ],
          ..._summary(summary),
        ],
      ),
    );

    for (final page in pages) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (_) => pw.Center(
            child: pw.Image(pw.MemoryImage(page.jpeg), fit: pw.BoxFit.contain),
          ),
        ),
      );
    }
    return doc.save();
  }

  static pw.Widget _heading(String text) => pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(
      fontSize: 9,
      letterSpacing: 0.6,
      fontWeight: pw.FontWeight.bold,
      color: _soft,
    ),
  );

  static pw.Widget _findings(List<RecordFinding> findings, pw.Font bold) {
    const cell = pw.TextStyle(fontSize: 9.5, color: _ink);
    pw.Widget pad(pw.Widget child) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: child,
    );
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(1.6),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(2),
      },
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _rule, width: 0.6),
        bottom: pw.BorderSide(color: _rule, width: 0.6),
      ),
      children: [
        pw.TableRow(
          children: [
            for (final h in ['Test', 'Result', 'Unit', 'Reference'])
              pad(
                pw.Text(
                  h,
                  style: pw.TextStyle(fontSize: 8.5, font: bold, color: _soft),
                ),
              ),
          ],
        ),
        for (final f in findings)
          pw.TableRow(
            children: [
              pad(pw.Text(f.name, style: cell)),
              pad(
                pw.Text(
                  f.flag.isEmpty
                      ? f.value
                      : '${f.value}  ${f.flag == 'high' ? 'H' : 'L'}',
                  style: f.flag.isEmpty
                      ? cell
                      : pw.TextStyle(fontSize: 9.5, font: bold, color: _flag),
                ),
              ),
              pad(pw.Text(f.unit, style: cell)),
              pad(pw.Text(f.range, style: cell)),
            ],
          ),
      ],
    );
  }

  /// The same layout as session notes: blank-line blocks, a short first
  /// line is the block's heading, "- " lines are bullets.
  static List<pw.Widget> _summary(String summary) {
    final out = <pw.Widget>[];
    final blocks = summary
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty);
    for (final block in blocks) {
      final lines = block.split('\n');
      final first = lines.first.trim();
      final isHeading =
          lines.length > 1 && first.length <= 40 && !first.startsWith('-');
      out.add(pw.SizedBox(height: 10));
      if (isHeading) {
        out
          ..add(_heading(first.replaceFirst(RegExp(r':$'), '')))
          ..add(pw.SizedBox(height: 4));
      }
      for (final raw in isHeading ? lines.skip(1) : lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        const style = pw.TextStyle(fontSize: 10.5, color: _ink, lineSpacing: 2);
        out.add(
          line.startsWith('- ')
              ? pw.Bullet(
                  text: line.substring(2),
                  style: style,
                  bulletSize: 3,
                  bulletMargin: const pw.EdgeInsets.only(
                    top: 5,
                    left: 2,
                    right: 6,
                  ),
                )
              : pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Text(line, style: style),
                ),
        );
      }
    }
    return out;
  }
}
