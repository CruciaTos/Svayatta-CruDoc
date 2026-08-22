import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';

enum PdfMedicalDocumentType {
  invoice,
  prescription,
  report;

  String get title => switch (this) {
        PdfMedicalDocumentType.invoice => 'Medical Invoice / Receipt',
        PdfMedicalDocumentType.prescription => 'Prescription (Rx)',
        PdfMedicalDocumentType.report => 'Medical Report',
      };

  String get filePrefix => switch (this) {
        PdfMedicalDocumentType.invoice => 'crudoc-invoice',
        PdfMedicalDocumentType.prescription => 'crudoc-prescription',
        PdfMedicalDocumentType.report => 'crudoc-medical-report',
      };
}

abstract class PdfMedicalDocumentData {
  const PdfMedicalDocumentData({
    required this.type,
    required this.letterheadConfig,
    required this.patient,
    required this.documentNumber,
    required this.documentDate,
    this.notes,
  });

  final PdfMedicalDocumentType type;
  final DoctorLetterheadConfig letterheadConfig;
  final PdfPatientSnapshot patient;
  final String documentNumber;
  final DateTime documentDate;
  final String? notes;

  String get previewTitle => type.title;
  String get fileName => '${type.filePrefix}-$documentNumber.pdf'
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
}

class PdfPatientSnapshot {
  const PdfPatientSnapshot({
    required this.fullName,
    this.phone,
    this.ageGender,
    this.email,
    this.patientId,
  });

  final String fullName;
  final String? phone;
  final String? ageGender;
  final String? email;
  final String? patientId;

  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;
  bool get hasAgeGender => ageGender != null && ageGender!.trim().isNotEmpty;
  bool get hasEmail => email != null && email!.trim().isNotEmpty;
  bool get hasPatientId => patientId != null && patientId!.trim().isNotEmpty;
}

class PdfInvoiceLineItem {
  const PdfInvoiceLineItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  final String description;
  final int quantity;
  final double unitPrice;

  double get total => quantity * unitPrice;
}

class PdfMoneyTotals {
  const PdfMoneyTotals({
    required this.subtotal,
    required this.discountAmount,
    required this.taxPercent,
    required this.taxAmount,
    required this.grandTotal,
    required this.paidAmount,
    required this.balanceDue,
    required this.paymentMode,
  });

  final double subtotal;
  final double discountAmount;
  final double taxPercent;
  final double taxAmount;
  final double grandTotal;
  final double paidAmount;
  final double balanceDue;
  final String paymentMode;
}

class PdfInvoiceDocumentData extends PdfMedicalDocumentData {
  const PdfInvoiceDocumentData({
    required super.letterheadConfig,
    required super.patient,
    required super.documentNumber,
    required super.documentDate,
    required this.items,
    required this.totals,
    super.notes,
  }) : super(type: PdfMedicalDocumentType.invoice);

  final List<PdfInvoiceLineItem> items;
  final PdfMoneyTotals totals;
}

class PdfPrescriptionMedication {
  const PdfPrescriptionMedication({
    required this.drugName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.instructions,
  });

  final String drugName;
  final String dosage;
  final String frequency;
  final String duration;
  final String instructions;
}

class PdfPrescriptionDocumentData extends PdfMedicalDocumentData {
  const PdfPrescriptionDocumentData({
    required super.letterheadConfig,
    required super.patient,
    required super.documentNumber,
    required super.documentDate,
    required this.vitals,
    required this.complaints,
    required this.diagnosis,
    required this.medications,
    required this.labTests,
    required this.advice,
    required this.followUp,
    super.notes,
  }) : super(type: PdfMedicalDocumentType.prescription);

  final String vitals;
  final String complaints;
  final String diagnosis;
  final List<PdfPrescriptionMedication> medications;
  final String labTests;
  final String advice;
  final String followUp;
}

class PdfReportSection {
  const PdfReportSection({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;
}

class PdfMedicalReportDocumentData extends PdfMedicalDocumentData {
  const PdfMedicalReportDocumentData({
    required super.letterheadConfig,
    required super.patient,
    required super.documentNumber,
    required super.documentDate,
    required this.reportTitle,
    required this.sections,
    super.notes,
  }) : super(type: PdfMedicalDocumentType.report);

  final String reportTitle;
  final List<PdfReportSection> sections;
}