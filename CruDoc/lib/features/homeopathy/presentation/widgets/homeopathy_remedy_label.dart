import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';

// The label that goes on the bottle or the pill envelope.
//
// This is the only thing the clinic prints that ends up in the patient's
// cupboard next to everything else they take, read weeks later, possibly by
// somebody else in the house. So the remedy and potency are the largest
// thing on it and everything else gets out of the way. A label that makes
// the clinic name the biggest text is a label that has forgotten what it is
// for.
//
// Deliberately not a prescription. The slip carries the case, the dosing
// reasoning and the antidote advice; this carries what is in the bottle and
// how to take it. Repeating the whole prescription on a 70 mm label is how
// both end up unreadable.

/// 70 × 38 mm, the common self-adhesive pharmacy label, laid out three
/// across on an A4 sheet.
const double _labelWidth = 70 * PdfPageFormat.mm;
const double _labelHeight = 38 * PdfPageFormat.mm;

/// What goes on one label.
class RemedyLabelData {
  const RemedyLabelData({
    required this.remedy,
    required this.potency,
    required this.dosing,
    required this.patientName,
    required this.date,
    this.localName = '',
    this.quantity = '',
  });

  final String remedy;
  final String potency;

  /// How to take it, in one short line. Long dosing belongs on the slip.
  final String dosing;

  final String patientName;
  final DateTime date;

  /// The remedy's name in the patient's own language, printed under the
  /// Latin name when the clinic has supplied one and a font that can draw
  /// it.
  ///
  /// Empty by default, and left empty rather than transliterated
  /// automatically: a remedy name is the one string on this label that must
  /// not be guessed at, and a wrong one in a script the prescriber cannot
  /// read would never be caught.
  final String localName;

  /// What was dispensed, e.g. `30 ml` or `1 phial`.
  final String quantity;
}

/// Builds a sheet of labels, three to a row.
///
/// [script] is a font that can draw [RemedyLabelData.localName]. Without
/// one, local names are left off entirely rather than printed as empty
/// boxes, which is what a PDF does with Devanagari in a Latin-only font.
Future<Uint8List> buildHomeoRemedyLabels({
  required List<RemedyLabelData> labels,
  required String clinicName,
  pw.Font? script,
}) async {
  final doc = pw.Document();
  final canDrawLocal = script != null;

  pw.Widget label(RemedyLabelData d) => pw.Container(
    width: _labelWidth,
    height: _labelHeight,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.max,
      children: [
        // What is in the bottle, as large as it will go.
        pw.Text(
          d.remedy,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        if (d.localName.trim().isNotEmpty && canDrawLocal)
          pw.Text(
            d.localName.trim(),
            maxLines: 1,
            style: pw.TextStyle(font: script, fontSize: 11),
          ),
        pw.Text(
          [
            d.potency.trim(),
            if (d.quantity.trim().isNotEmpty) d.quantity.trim(),
          ].where((s) => s.isNotEmpty).join('  ·  '),
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Expanded(
          child: pw.Text(
            d.dosing.trim(),
            maxLines: 3,
            overflow: pw.TextOverflow.clip,
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ),
        // Who it is for and when, small: needed to tell two bottles apart,
        // not needed before the remedy.
        pw.Text(
          '${d.patientName}  ·  ${DentalFormat.date(d.date)}',
          maxLines: 1,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
        ),
        if (clinicName.trim().isNotEmpty)
          pw.Text(
            clinicName.trim(),
            maxLines: 1,
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
          ),
      ],
    ),
  );

  // Three across, as many rows as fit, then a new page.
  const perRow = 3;
  final rows = <pw.Widget>[];
  for (var i = 0; i < labels.length; i += perRow) {
    final slice = labels.skip(i).take(perRow).toList();
    rows.add(
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final d in slice) ...[
            label(d),
            if (d != slice.last) pw.SizedBox(width: 6),
          ],
        ],
      ),
    );
    rows.add(pw.SizedBox(height: 6));
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
      build: (_) => rows,
    ),
  );

  return doc.save();
}

/// How many labels fit on one A4 sheet, for telling the clinic what it is
/// about to print.
int remedyLabelsPerSheet() {
  final usableHeight = PdfPageFormat.a4.height - 20 * PdfPageFormat.mm;
  final rowsPerPage = (usableHeight / (_labelHeight + 6)).floor();
  return rowsPerPage * 3;
}
