import 'package:doctor_management_app/core/pdf/models/pdf_document_models.dart';
import 'package:doctor_management_app/core/pdf/render/pdf_text.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_bill.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';

PdfInvoiceDocumentData invoicePdfData(
  InvoiceModel inv, {
  Patient? patient,
}) {
  var bill = inv.bill;
  if (bill.items.isEmpty) {
    final paidPaise = inv.isPaid ? toPaise(inv.amount) : 0;
    bill = InvoiceBill(
      items: [
        InvoiceBillItem(
          name: inv.service.isNotEmpty ? inv.service : 'Medical Consultation',
          ratePaise: toPaise(inv.amount),
        ),
      ],
      roundOff: false,
      paidPaise: paidPaise,
      templateId: bill.templateId,
      signedByUid: bill.signedByUid,
    );
  }

  final totals = InvoiceTotals.of(bill);

  String? ageGender;
  if (patient != null) {
    final g = patient.gender.trim();
    ageGender = g.isNotEmpty ? '${patient.age} Y / $g' : '${patient.age} Y';
  }

  final patientSnapshot = PdfPatientSnapshot(
    fullName: inv.patientName.isNotEmpty ? inv.patientName : (patient?.fullName ?? 'Patient'),
    phone: patient?.phone,
    email: patient?.email,
    ageGender: ageGender,
  );

  final lineItems = bill.items.map((i) {
    return PdfInvoiceLineItem(
      description: i.name,
      quantity: i.qty,
      unitPrice: i.ratePaise / 100.0,
      taxPercent: i.taxPct,
      note: i.note,
    );
  }).toList();

  final moneyTotals = PdfMoneyTotals(
    subtotal: totals.subtotal / 100.0,
    discountAmount: totals.discount / 100.0,
    taxPercent: totals.subtotal > 0 ? (totals.tax / totals.subtotal) * 100.0 : 0.0,
    taxAmount: totals.tax / 100.0,
    grandTotal: totals.grand / 100.0,
    paidAmount: totals.paid / 100.0,
    balanceDue: totals.balance / 100.0,
    paymentMode: bill.paymentMode,
    roundOff: totals.roundOff / 100.0,
  );

  final docNum = inv.invoiceNumber.trim().isNotEmpty
      ? inv.invoiceNumber.trim()
      : inv.id;

  final issuing = inv.attendingDoctorUid.trim().isNotEmpty
      ? inv.attendingDoctorUid.trim()
      : null;

  final signedBy = bill.signedByUid.trim().isNotEmpty
      ? bill.signedByUid.trim()
      : null;

  final templateId = bill.templateId.trim().isNotEmpty
      ? bill.templateId.trim()
      : null;

  return PdfInvoiceDocumentData(
    patient: patientSnapshot,
    documentNumber: docNum,
    documentDate: inv.date,
    items: lineItems,
    totals: moneyTotals,
    notes: inv.notes,
    issuingDoctorUid: issuing,
    signedByUid: signedBy,
    templateId: templateId,
    cancelled: inv.isCancelled,
  );
}
