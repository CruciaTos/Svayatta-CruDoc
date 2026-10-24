import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pdf_document_models.dart';
import '../templates/doc_body_sections.dart';
import '../templates/doc_template.dart';
import 'doc_renderer.dart';
import 'pdf_text.dart';

class DocBody {
  DocBody(this.r);

  final DocRenderer r;

  double pt(double v) => v * r.t.style.fontScale;

  List<pw.Widget> heading(String title) {
    if (title.trim().isEmpty) return const [];
    return [
      pw.SizedBox(height: pt(12)),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 3,
            height: pt(12),
            color: r.color('accent'),
            margin: const pw.EdgeInsets.only(right: 6),
          ),
          pw.Text(
            pdfSafe(title),
            style: r.style(pt(10.5), bold: true, color: 'text'),
          ),
        ],
      ),
      pw.SizedBox(height: pt(6)),
    ];
  }

  /// Splits long text so MultiPage can break it across pages.
  List<pw.Widget> paragraphs(String text, pw.TextStyle st) {
    final out = <pw.Widget>[];
    for (final para in pdfSafe(text).split('\n')) {
      var rest = para;
      while (rest.length > 1200) {
        var cut = rest.lastIndexOf(' ', 1200);
        if (cut < 600) cut = 1200;
        out.add(pw.Text(rest.substring(0, cut), style: st));
        rest = rest.substring(cut).trimLeft();
      }
      out.add(rest.isEmpty ? pw.SizedBox(height: 4) : pw.Text(rest, style: st));
    }
    return out;
  }

  /// heading + paragraphs, or nothing when [text] is blank.
  List<pw.Widget> textSection(String title, String? text) {
    final s = pdfSafe(text);
    if (s.isEmpty) return const [];
    return [...heading(title), ...paragraphs(s, r.style(pt(9), color: 'text'))];
  }

  List<pw.Widget> build() {
    final sections = r.t.bodyFor(r.ctx.kind);
    final out = <pw.Widget>[];

    for (final sec in sections) {
      if (!sec.visible) continue;
      final widgets = switch (sec.id) {
        DocSection.meta => _meta(),
        DocSection.patient => _patient(),
        DocSection.items => _items(),
        DocSection.totals => _totals(),
        DocSection.words => _words(),
        DocSection.payment => _payment(),
        DocSection.upi => _upi(),
        DocSection.notes => _notes(),
        DocSection.terms => _terms(),
        DocSection.vitals => _vitals(),
        DocSection.complaints => _complaints(),
        DocSection.diagnosis => _diagnosis(),
        DocSection.rx => _rx(),
        DocSection.investigations => _investigations(),
        DocSection.advice => _advice(),
        DocSection.followUp => _followUp(),
        DocSection.recipient => _recipient(),
        DocSection.reason => _reason(),
        DocSection.findings => _findings(),
        DocSection.question => _question(),
        DocSection.teeth => _teeth(),
        DocSection.sections => _sections(),
        DocSection.certificate => _certificate(),
        DocSection.signature => signature(),
        _ => const <pw.Widget>[],
      };
      out.addAll(widgets);
    }

    return out;
  }

  List<pw.Widget> _meta() {
    final title = r.ctx.field('doc.title');
    final no = r.ctx.field('doc.numberLine');
    final date = r.ctx.field('doc.dateLine');

    return [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              title,
              style: r.style(pt(13), bold: true, color: 'accent'),
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (no.isNotEmpty)
                pw.Text(no, style: r.style(pt(9), color: 'text')),
              if (date.isNotEmpty)
                pw.Text(date, style: r.style(pt(9), color: 'text')),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: pt(8)),
    ];
  }

  List<pw.Widget> _patient() {
    final p = r.ctx.data.patient;
    final name = p.fullName.trim().isNotEmpty ? p.fullName.trim() : 'Patient';
    final details = [
      if (p.hasAgeGender) p.ageGender!.trim(),
      if (p.hasPhone) p.phone!.trim(),
    ].where((s) => s.isNotEmpty).join(' · ');

    return [
      pw.Container(
        decoration: pw.BoxDecoration(
          color: r.color('soft'),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: r.color('border'), width: 0.6),
        ),
        padding: const pw.EdgeInsets.all(8),
        margin: pw.EdgeInsets.only(bottom: pt(8)),
        child: pw.Row(
          children: [
            pw.Container(
              width: 3,
              height: pt(24),
              color: r.color('accent'),
              margin: const pw.EdgeInsets.only(right: 8),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    pdfSafe(name),
                    style: r.style(pt(11), bold: true, color: 'text'),
                  ),
                  if (details.isNotEmpty)
                    pw.Text(
                      pdfSafe(details),
                      style: r.style(pt(8.5), color: 'muted'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _items() {
    final data = r.ctx.data;
    if (data is! PdfInvoiceDocumentData) return const [];
    final validItems = data.items
        .where((i) => i.description.trim().isNotEmpty)
        .toList();
    if (validItems.isEmpty) return const [];

    final hasTax = validItems.any((i) => i.taxPercent > 0);

    final headers = [
      '#',
      'Description',
      'Qty',
      'Rate',
      if (hasTax) 'Tax %',
      if (hasTax) 'Tax',
      'Amount',
    ];

    final tableData = <List<String>>[
      headers,
      for (var idx = 0; idx < validItems.length; idx++) ...[
        () {
          final item = validItems[idx];
          final desc = item.note.isNotEmpty
              ? '${item.description}\n${item.note}'
              : item.description;
          final taxAmount = (item.total * item.taxPercent / 100);
          return [
            '${idx + 1}',
            pdfSafe(desc),
            '${item.quantity}',
            formatPaise(toPaise(item.unitPrice)),
            if (hasTax) item.taxPercent > 0 ? '${item.taxPercent}%' : '-',
            if (hasTax)
              item.taxPercent > 0 ? formatPaise(toPaise(taxAmount)) : '-',
            formatPaise(toPaise(item.total)),
          ];
        }(),
      ],
    ];

    final colAlignments = <int, pw.Alignment>{
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.centerLeft,
      2: pw.Alignment.centerRight,
      3: pw.Alignment.centerRight,
      if (hasTax) 4: pw.Alignment.centerRight,
      if (hasTax) 5: pw.Alignment.centerRight,
      hasTax ? 6 : 4: pw.Alignment.centerRight,
    };

    return [
      pw.TableHelper.fromTextArray(
        headers: tableData.first,
        data: tableData.skip(1).toList(),
        headerCount: 1,
        headerStyle: r.style(pt(8.5), bold: true, color: 'white'),
        headerDecoration: pw.BoxDecoration(color: r.color('accent')),
        cellStyle: r.style(pt(8.5), color: 'text'),
        cellAlignments: colAlignments,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        border: pw.TableBorder(
          bottom: pw.BorderSide(color: r.color('border'), width: 0.5),
          horizontalInside: pw.BorderSide(color: r.color('border'), width: 0.5),
        ),
      ),
      pw.SizedBox(height: pt(8)),
    ];
  }

  List<pw.Widget> _totals() {
    final data = r.ctx.data;
    if (data is! PdfInvoiceDocumentData) return const [];
    final totals = data.totals;

    final subtotalPaise = toPaise(totals.subtotal);
    final taxPaise = toPaise(totals.taxAmount);
    final discountPaise = toPaise(totals.discountAmount);
    final roundOffPaise = toPaise(totals.roundOff);
    final grandPaise = toPaise(totals.grandTotal);

    pw.Widget row(
      String label,
      String value, {
      bool bold = false,
      String color = 'text',
    }) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: r.style(pt(8.5), color: 'muted')),
          pw.Text(
            value,
            style: r.style(pt(8.5), bold: bold, color: color),
          ),
        ],
      ),
    );

    return [
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Container(
          width: 75 * PdfPageFormat.mm,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: r.color('soft'),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: r.color('border'), width: 0.6),
          ),
          child: pw.Column(
            children: [
              row('Subtotal', formatPaise(subtotalPaise)),
              if (taxPaise > 0) ...[
                if (r.ctx.clinic.gstEnabled) ...[
                  row('CGST', formatPaise((taxPaise / 2).ceil())),
                  row('SGST', formatPaise((taxPaise / 2).floor())),
                ] else
                  row('Tax', formatPaise(taxPaise)),
              ],
              if (discountPaise > 0)
                row('Discount', '- ${formatPaise(discountPaise)}'),
              if (roundOffPaise != 0)
                row(
                  'Round off',
                  '${roundOffPaise > 0 ? '+' : ''}${formatPaise(roundOffPaise)}',
                ),
              pw.Divider(color: r.color('border'), thickness: 0.6),
              row(
                'Total',
                formatPaise(grandPaise),
                bold: true,
                color: 'accent',
              ),
            ],
          ),
        ),
      ),
      pw.SizedBox(height: pt(6)),
    ];
  }

  List<pw.Widget> _words() {
    if (!r.t.options.amountInWords) return const [];
    final data = r.ctx.data;
    if (data is! PdfInvoiceDocumentData) return const [];
    final grandPaise = toPaise(data.totals.grandTotal);
    return [
      pw.Text(
        'Amount in words: ${rupeesInWords(grandPaise)}',
        style: r.style(pt(8.5), color: 'muted'),
      ),
      pw.SizedBox(height: pt(6)),
    ];
  }

  List<pw.Widget> _payment() {
    final data = r.ctx.data;
    if (data is! PdfInvoiceDocumentData) return const [];
    final totals = data.totals;
    final paidPaise = toPaise(totals.paidAmount);
    final balancePaise = toPaise(totals.balanceDue);
    final mode = totals.paymentMode.trim();

    final parts = <String>[];
    if (paidPaise > 0) {
      parts.add(
        'Received ${formatPaise(paidPaise)}${mode.isNotEmpty ? ' by $mode' : ''}',
      );
    }

    return [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          if (parts.isNotEmpty)
            pw.Text(parts.join(' · '), style: r.style(pt(8.5), color: 'text')),
          if (balancePaise > 0)
            pw.Text(
              'Balance due ${formatPaise(balancePaise)}',
              style: r.style(pt(8.5), bold: true, color: 'accent'),
            )
          else
            pw.Text(
              'Paid in full',
              style: r.style(pt(8.5), bold: true, color: 'text'),
            ),
        ],
      ),
      pw.SizedBox(height: pt(6)),
    ];
  }

  List<pw.Widget> _upi() {
    if (!r.t.options.upiQr) return const [];
    final uri = r.ctx.upiUri();
    if (uri == null) return const [];
    final data = r.ctx.data as PdfInvoiceDocumentData;
    final balancePaise = toPaise(data.totals.balanceDue);

    return [
      pw.Container(
        margin: pw.EdgeInsets.symmetric(vertical: pt(6)),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: r.color('border'), width: 0.6),
        ),
        child: pw.Row(
          children: [
            pw.Container(
              width: 26 * PdfPageFormat.mm,
              height: 26 * PdfPageFormat.mm,
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: uri,
                drawText: false,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Scan to pay ${formatPaise(balancePaise)} with any UPI app',
                    style: r.style(pt(8.5), bold: true, color: 'text'),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'UPI ID: ${r.ctx.clinic.upiId}',
                    style: r.style(pt(7.5), color: 'muted'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _notes() => textSection('Notes', r.ctx.data.notes);

  List<pw.Widget> _terms() {
    if (r.ctx.kind != DocKind.invoice) return const [];
    return textSection('Terms', r.ctx.clinic.termsText);
  }

  // Prescription sections
  List<pw.Widget> _vitals() {
    final data = r.ctx.data;
    if (data is! PdfPrescriptionDocumentData) return const [];
    return textSection('Vitals', data.vitals);
  }

  List<pw.Widget> _complaints() {
    final data = r.ctx.data;
    if (data is! PdfPrescriptionDocumentData) return const [];
    return textSection('Complaints', data.complaints);
  }

  List<pw.Widget> _diagnosis() {
    final data = r.ctx.data;
    if (data is! PdfPrescriptionDocumentData) return const [];
    return textSection('Diagnosis', data.diagnosis);
  }

  List<pw.Widget> _rx() {
    final data = r.ctx.data;
    if (data is! PdfPrescriptionDocumentData) return const [];
    final meds = data.medications;
    if (meds.isEmpty) return const [];

    final headers = [
      '#',
      'Medicine',
      'Dose',
      'When',
      'Duration',
      'Instructions',
    ];
    final rows = <List<String>>[
      headers,
      for (var i = 0; i < meds.length; i++) ...[
        () {
          final m = meds[i];
          final name = r.t.options.medicinesInCapitals
              ? m.drugName.toUpperCase()
              : m.drugName;
          return [
            '${i + 1}',
            pdfSafe(name),
            pdfSafe(m.dosage),
            pdfSafe(m.frequency),
            pdfSafe(m.duration),
            pdfSafe(m.instructions),
          ];
        }(),
      ],
    ];

    return [
      ...heading('Rx'),
      pw.TableHelper.fromTextArray(
        headers: rows.first,
        data: rows.skip(1).toList(),
        headerCount: 1,
        headerAlignment: pw.Alignment.centerLeft,
        cellAlignment: pw.Alignment.centerLeft,
        headerStyle: r.style(pt(8.5), bold: true, color: 'white'),
        headerDecoration: pw.BoxDecoration(color: r.color('accent')),
        cellStyle: r.style(pt(8.5), color: 'text'),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        border: pw.TableBorder(
          bottom: pw.BorderSide(color: r.color('border'), width: 0.5),
          horizontalInside: pw.BorderSide(color: r.color('border'), width: 0.5),
        ),
      ),
      pw.SizedBox(height: pt(8)),
    ];
  }

  List<pw.Widget> _investigations() {
    final data = r.ctx.data;
    if (data is! PdfPrescriptionDocumentData) return const [];
    return textSection('Investigations', data.labTests);
  }

  List<pw.Widget> _advice() {
    final data = r.ctx.data;
    if (data is! PdfPrescriptionDocumentData) return const [];
    return textSection('Advice', data.advice);
  }

  List<pw.Widget> _followUp() {
    final data = r.ctx.data;
    if (data is! PdfPrescriptionDocumentData) return const [];
    return textSection('Follow-up', data.followUp);
  }

  // Referral sections
  List<pw.Widget> _recipient() {
    final data = r.ctx.data;
    if (data is! PdfReferralDocumentData) return const [];
    return textSection('To', data.recipient);
  }

  List<pw.Widget> _reason() {
    final data = r.ctx.data;
    if (data is! PdfReferralDocumentData) return const [];
    return textSection('Reason for referral', data.reason);
  }

  List<pw.Widget> _findings() {
    final data = r.ctx.data;
    if (data is! PdfReferralDocumentData) return const [];
    final title = data.isReply ? 'Treatment summary' : 'Clinical findings';
    final content = data.isReply ? data.reply : data.findings;
    return textSection(title, content);
  }

  List<pw.Widget> _question() {
    final data = r.ctx.data;
    if (data is! PdfReferralDocumentData) return const [];
    return textSection('Requested', data.question);
  }

  List<pw.Widget> _teeth() {
    final data = r.ctx.data;
    if (data is! PdfReferralDocumentData) return const [];
    return textSection('Teeth', data.teeth);
  }

  // Report sections
  List<pw.Widget> _sections() {
    final data = r.ctx.data;
    if (data is! PdfMedicalReportDocumentData) return const [];
    final out = <pw.Widget>[];
    for (final s in data.sections) {
      if (s.content.trim().isNotEmpty) {
        out.addAll(textSection(s.title, s.content));
      }
    }
    return out;
  }

  // Certificate
  List<pw.Widget> _certificate() {
    final data = r.ctx.data;
    if (data is! PdfCertificateDocumentData) return const [];
    return [
      pw.SizedBox(height: pt(16)),
      ...paragraphs(
        data.body,
        r.style(pt(11), color: 'text').copyWith(lineSpacing: 3),
      ),
      pw.SizedBox(height: pt(16)),
    ];
  }

  // Signature section (exact behavior)
  List<pw.Widget> signature() {
    final ctx = r.ctx;
    final d = ctx.doctor;
    final mode = ctx.kind == DocKind.invoice
        ? r.t.options.invoiceSignature
        : InvoiceSignature.doctor;
    if (mode == InvoiceSignature.none) return const [];

    Uint8List? image;
    Uint8List? stamp;
    var line1 = '';
    var line2 = '';

    switch (mode) {
      case InvoiceSignature.clinicStamp:
        image = ctx.images.clinicStamp;
        line1 = 'Authorised signatory';
        line2 = ctx.clinic.name;
      case InvoiceSignature.line:
        line1 = 'Authorised signatory';
      case InvoiceSignature.doctor:
      case InvoiceSignature.none:
        image = ctx.images.signature;
        stamp = ctx.images.stamp;
        line1 = d?.name ?? '';
        line2 = d == null
            ? ''
            : [
                d.qualification,
                d.regNo.isEmpty ? '' : 'Reg. No. ${d.regNo}',
              ].where((s) => s.trim().isNotEmpty).join(' · ');
        if (line1.isEmpty) line1 = 'Authorised signatory';
    }

    return [
      pw.SizedBox(height: 14),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Container(
          width: 64 * PdfPageFormat.mm,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                height: 18 * PdfPageFormat.mm,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (stamp != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 6),
                        child: pw.Image(
                          pw.MemoryImage(stamp),
                          fit: pw.BoxFit.contain,
                          alignment: pw.Alignment.bottomRight,
                        ),
                      ),
                    if (image != null)
                      pw.Image(
                        pw.MemoryImage(image),
                        fit: pw.BoxFit.contain,
                        alignment: pw.Alignment.bottomRight,
                      ),
                  ],
                ),
              ),
              pw.Container(
                height: 0.6,
                color: r.color('border'),
                margin: const pw.EdgeInsets.symmetric(vertical: 3),
              ),
              if (line1.isNotEmpty)
                pw.Text(
                  pdfSafe(line1),
                  style: r.style(pt(9.5), bold: true, color: 'text'),
                  textAlign: pw.TextAlign.center,
                ),
              if (line2.isNotEmpty)
                pw.Text(
                  pdfSafe(line2),
                  style: r.style(pt(7.5), color: 'muted'),
                  textAlign: pw.TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    ];
  }
}
