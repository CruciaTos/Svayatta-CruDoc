import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pdf_document_models.dart';
import 'doc_renderer.dart';
import 'pdf_text.dart';

class ReceiptLayout {
  ReceiptLayout(this.r);

  final DocRenderer r;

  pw.Page page() {
    final data = r.ctx.data;
    if (data is! PdfInvoiceDocumentData) {
      throw StateError('Receipt paper is for bills only');
    }

    final c = r.ctx.clinic;
    final totals = data.totals;
    final totalPaise = toPaise(totals.grandTotal);
    final subtotalPaise = toPaise(totals.subtotal);
    final discountPaise = toPaise(totals.discountAmount);
    final taxPaise = toPaise(totals.taxAmount);
    final roundOffPaise = toPaise(totals.roundOff);
    final paidPaise = toPaise(totals.paidAmount);
    final balancePaise = toPaise(totals.balanceDue);

    final divider = pw.Text('-' * 42, style: r.style(8, color: 'border'));

    return pw.Page(
      pageFormat: r.t.paper.toPdf(),
      theme: r.fonts.theme(),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (r.ctx.data case PdfInvoiceDocumentData(cancelled: true)) ...[
            pw.Text(
              'CANCELLED',
              style: r.style(12, bold: true, color: '#B91C1C'),
            ),
            pw.SizedBox(height: 4),
          ],

          // Logo
          if (r.ctx.images.logo != null) ...[
            pw.Container(
              height: 18 * PdfPageFormat.mm,
              child: pw.Image(
                pw.MemoryImage(r.ctx.images.logo!),
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 4),
          ],

          // Clinic info
          if (c.name.isNotEmpty)
            pw.Text(
              pdfSafe(c.name),
              style: r.style(11, bold: true, color: 'text'),
              textAlign: pw.TextAlign.center,
            ),
          if (c.tagline.isNotEmpty)
            pw.Text(
              pdfSafe(c.tagline),
              style: r.style(7.5, color: 'muted'),
              textAlign: pw.TextAlign.center,
            ),
          if (c.address.isNotEmpty)
            pw.Text(
              pdfSafe(c.address.replaceAll('\n', ', ')),
              style: r.style(7.5, color: 'muted'),
              textAlign: pw.TextAlign.center,
            ),
          if (c.phone.isNotEmpty)
            pw.Text(
              pdfSafe(c.phone),
              style: r.style(7.5, color: 'muted'),
              textAlign: pw.TextAlign.center,
            ),
          if (c.gstEnabled && c.gstin.isNotEmpty)
            pw.Text(
              'GSTIN: ${c.gstin}',
              style: r.style(7.5, color: 'muted'),
              textAlign: pw.TextAlign.center,
            ),

          pw.SizedBox(height: 4),
          divider,

          // Bill No & Date
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Bill No: ${data.documentNumber}',
                  style: r.style(8, bold: true, color: 'text'),
                ),
                pw.Text(
                  'Date: ${formatDocDate(data.documentDate)}',
                  style: r.style(8, color: 'text'),
                ),
              ],
            ),
          ),

          // Patient
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              children: [
                pw.Text(
                  'Patient: ${pdfSafe(data.patient.fullName)}',
                  style: r.style(8, color: 'text'),
                ),
              ],
            ),
          ),

          divider,

          // Items
          for (final item in data.items)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          pdfSafe(item.description),
                          style: r.style(8, bold: true, color: 'text'),
                        ),
                        pw.Text(
                          '${item.quantity} x ${formatPaise(toPaise(item.unitPrice))}',
                          style: r.style(7.5, color: 'muted'),
                        ),
                      ],
                    ),
                  ),
                  pw.Text(
                    formatPaise(toPaise(item.total)),
                    style: r.style(8, color: 'text'),
                  ),
                ],
              ),
            ),

          divider,

          // Totals
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Subtotal', style: r.style(8, color: 'muted')),
                pw.Text(
                  formatPaise(subtotalPaise),
                  style: r.style(8, color: 'text'),
                ),
              ],
            ),
          ),
          if (taxPaise > 0) ...[
            if (c.gstEnabled) ...[
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('CGST', style: r.style(8, color: 'muted')),
                    pw.Text(
                      formatPaise((taxPaise / 2).ceil()),
                      style: r.style(8, color: 'text'),
                    ),
                  ],
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('SGST', style: r.style(8, color: 'muted')),
                    pw.Text(
                      formatPaise((taxPaise / 2).floor()),
                      style: r.style(8, color: 'text'),
                    ),
                  ],
                ),
              ),
            ] else
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Tax', style: r.style(8, color: 'muted')),
                    pw.Text(
                      formatPaise(taxPaise),
                      style: r.style(8, color: 'text'),
                    ),
                  ],
                ),
              ),
          ],
          if (discountPaise > 0)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Discount', style: r.style(8, color: 'muted')),
                  pw.Text(
                    '- ${formatPaise(discountPaise)}',
                    style: r.style(8, color: 'text'),
                  ),
                ],
              ),
            ),
          if (roundOffPaise != 0)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Round off', style: r.style(8, color: 'muted')),
                  pw.Text(
                    '${roundOffPaise > 0 ? '+' : ''}${formatPaise(roundOffPaise)}',
                    style: r.style(8, color: 'text'),
                  ),
                ],
              ),
            ),

          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total',
                  style: r.style(10, bold: true, color: 'accent'),
                ),
                pw.Text(
                  formatPaise(totalPaise),
                  style: r.style(10, bold: true, color: 'accent'),
                ),
              ],
            ),
          ),

          divider,

          // Payment details
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Received', style: r.style(8, color: 'muted')),
                pw.Text(
                  formatPaise(paidPaise),
                  style: r.style(8, color: 'text'),
                ),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Balance',
                  style: r.style(8, bold: true, color: 'text'),
                ),
                pw.Text(
                  formatPaise(balancePaise),
                  style: r.style(
                    8,
                    bold: true,
                    color: balancePaise > 0 ? 'accent' : 'text',
                  ),
                ),
              ],
            ),
          ),
          if (totals.paymentMode.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Mode', style: r.style(8, color: 'muted')),
                  pw.Text(totals.paymentMode, style: r.style(8, color: 'text')),
                ],
              ),
            ),

          // UPI QR
          if (balancePaise > 0 && r.ctx.upiUri() != null) ...[
            pw.SizedBox(height: 6),
            pw.Container(
              width: 30 * PdfPageFormat.mm,
              height: 30 * PdfPageFormat.mm,
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: r.ctx.upiUri()!,
                drawText: false,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text('Scan to pay balance', style: r.style(7, color: 'muted')),
          ],

          if (c.footerText.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              pdfSafe(c.footerText),
              style: r.style(7, color: 'muted'),
              textAlign: pw.TextAlign.center,
            ),
          ],

          pw.SizedBox(height: 6),
          pw.Text('Thank you', style: r.style(8, bold: true, color: 'text')),
          pw.SizedBox(height: 8),
        ],
      ),
    );
  }
}
