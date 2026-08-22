import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pdf_document_models.dart';
import 'letterhead_pdf_template.dart';

class MedicalDocumentPdfBuilder {
  const MedicalDocumentPdfBuilder({required this.template});

  final LetterheadPdfTemplate template;

  List<pw.Widget> build(PdfMedicalDocumentData data) {
    return switch (data) {
      PdfInvoiceDocumentData invoice => _buildInvoice(invoice),
      PdfPrescriptionDocumentData prescription => _buildPrescription(prescription),
      PdfMedicalReportDocumentData report => _buildReport(report),
      _ => [pw.Text('Unsupported document type')],
    };
  }

  List<pw.Widget> _buildInvoice(PdfInvoiceDocumentData data) {
    return [
      template.patientSummary(data.patient),
      template.sectionTitle('Bill Items & Services'),
      _invoiceItemsTable(data),
      pw.SizedBox(height: 14),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _notesBox(
              title: 'Notes',
              content: data.notes ?? 'Thank you for choosing our clinic.',
            ),
          ),
          pw.SizedBox(width: 18),
          _invoiceTotalsBox(data),
        ],
      ),
      template.signatureBlock(),
    ];
  }

  List<pw.Widget> _buildPrescription(PdfPrescriptionDocumentData data) {
    return [
      template.patientSummary(data.patient),
      template.sectionTitle('Clinical Summary'),
      template.keyValueGrid([
        MapEntry('Vitals', data.vitals),
        MapEntry('Chief Complaints / History', data.complaints),
        MapEntry('Diagnosis / Impression', data.diagnosis),
      ]),
      template.sectionTitle('Rx - Prescribed Medications'),
      _medicationTable(data),
      template.sectionTitle('Advice & Investigations'),
      template.keyValueGrid([
        MapEntry('Lab Tests / Investigations', data.labTests),
        MapEntry('Diet & Lifestyle Advice', data.advice),
        MapEntry('Follow-up', data.followUp),
      ]),
      if (data.notes != null && data.notes!.trim().isNotEmpty)
        _notesBox(title: 'Additional Notes', content: data.notes!),
      template.signatureBlock(),
    ];
  }

  List<pw.Widget> _buildReport(PdfMedicalReportDocumentData data) {
    return [
      template.patientSummary(data.patient),
      template.sectionTitle(data.reportTitle),
      ...data.sections.where((section) => section.content.trim().isNotEmpty).map(
            (section) => pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              padding: const pw.EdgeInsets.all(11),
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(9),
                border: pw.Border.all(color: template.theme.borderColor),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(section.title, style: template.theme.sectionTitleStyle),
                  pw.SizedBox(height: 6),
                  pw.Text(section.content, style: template.theme.bodyStyle),
                ],
              ),
            ),
          ),
      if (data.notes != null && data.notes!.trim().isNotEmpty)
        _notesBox(title: 'Notes', content: data.notes!),
      template.signatureBlock(),
    ];
  }

  pw.Widget _invoiceItemsTable(PdfInvoiceDocumentData data) {
    final rows = data.items
        .where((item) => item.description.trim().isNotEmpty)
        .map(
          (item) => [
            item.description,
            item.quantity.toString(),
            _money(item.unitPrice),
            _money(item.total),
          ],
        )
        .toList();

    return pw.TableHelper.fromTextArray(
      headers: const ['Description', 'Qty', 'Rate', 'Amount'],
      data: rows.isEmpty ? const [[]] : rows,
      headerDecoration: pw.BoxDecoration(color: template.theme.accentColor),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: template.theme.bodyStyle,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      border: pw.TableBorder.all(color: template.theme.borderColor, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(1.7),
      },
      cellAlignments: const {
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
    );
  }

  pw.Widget _medicationTable(PdfPrescriptionDocumentData data) {
    final rows = data.medications
        .where((med) => med.drugName.trim().isNotEmpty)
        .map(
          (med) => [
            med.drugName,
            med.dosage,
            med.frequency,
            med.duration,
            med.instructions,
          ],
        )
        .toList();

    return pw.TableHelper.fromTextArray(
      headers: const ['Medicine', 'Dosage', 'Frequency', 'Duration', 'Instructions'],
      data: rows.isEmpty ? const [[]] : rows,
      headerDecoration: pw.BoxDecoration(color: template.theme.accentColor),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 8.5,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: template.theme.bodyStyle,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      border: pw.TableBorder.all(color: template.theme.borderColor, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.8),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(1.6),
      },
    );
  }

  pw.Widget _invoiceTotalsBox(PdfInvoiceDocumentData data) {
    final totals = data.totals;
    return pw.Container(
      width: 210,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: template.theme.softBackgroundColor,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: template.theme.borderColor),
      ),
      child: pw.Column(
        children: [
          _totalRow('Subtotal', _money(totals.subtotal)),
          _totalRow('Discount', '- ${_money(totals.discountAmount)}'),
          _totalRow('Tax / GST (${totals.taxPercent.toStringAsFixed(2)}%)', _money(totals.taxAmount)),
          pw.Divider(color: template.theme.borderColor, height: 16),
          _totalRow('Grand Total', _money(totals.grandTotal), isStrong: true),
          _totalRow('Paid (${totals.paymentMode})', _money(totals.paidAmount)),
          _totalRow('Balance Due', _money(totals.balanceDue), isStrong: totals.balanceDue > 0),
        ],
      ),
    );
  }

  pw.Widget _totalRow(String label, String value, {bool isStrong = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: isStrong ? template.theme.sectionTitleStyle : template.theme.bodyStyle,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: isStrong ? template.theme.accentColor : template.theme.darkTextColor,
              fontSize: isStrong ? 11 : 9.5,
              fontWeight: isStrong ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _notesBox({required String title, required String content}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: template.theme.borderColor),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: template.theme.sectionTitleStyle),
          pw.SizedBox(height: 6),
          pw.Text(content, style: template.theme.bodyStyle),
        ],
      ),
    );
  }

  String _money(double value) => 'INR ${value.toStringAsFixed(2)}';
}