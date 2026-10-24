import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';

import '../templates/doc_template.dart';

enum PdfMedicalDocumentType {
  invoice,
  prescription,
  referral,
  report,
  certificate;

  String get title => switch (this) {
    PdfMedicalDocumentType.invoice => 'Medical Invoice / Receipt',
    PdfMedicalDocumentType.prescription => 'Prescription',
    PdfMedicalDocumentType.referral => 'Referral letter',
    PdfMedicalDocumentType.report => 'Medical Report',
    PdfMedicalDocumentType.certificate => 'Medical certificate',
  };

  String get filePrefix => switch (this) {
    PdfMedicalDocumentType.invoice => 'crudoc-invoice',
    PdfMedicalDocumentType.prescription => 'crudoc-prescription',
    PdfMedicalDocumentType.referral => 'crudoc-referral',
    PdfMedicalDocumentType.report => 'crudoc-medical-report',
    PdfMedicalDocumentType.certificate => 'crudoc-certificate',
  };

  DocKind get kind => switch (this) {
    PdfMedicalDocumentType.invoice => DocKind.invoice,
    PdfMedicalDocumentType.prescription => DocKind.prescription,
    PdfMedicalDocumentType.referral => DocKind.referral,
    PdfMedicalDocumentType.report => DocKind.report,
    PdfMedicalDocumentType.certificate => DocKind.certificate,
  };
}

abstract class PdfMedicalDocumentData {
  const PdfMedicalDocumentData({
    required this.type,
    this.letterheadConfig = DoctorLetterheadConfig.empty,
    required this.patient,
    required this.documentNumber,
    required this.documentDate,
    this.notes,
    this.issuingDoctorUid,
    this.signedByUid,
    this.templateId,
  });

  final PdfMedicalDocumentType type;
  final DoctorLetterheadConfig letterheadConfig;
  final PdfPatientSnapshot patient;
  final String documentNumber;
  final DateTime documentDate;
  final String? notes;
  final String? issuingDoctorUid;
  final String? signedByUid;
  final String? templateId;

  DocKind get kind => type.kind;

  String get previewTitle => type.title;

  String titleFor(bool gst) => type.title.toUpperCase();

  String get fileName => '${type.filePrefix}-$documentNumber.pdf'.replaceAll(
    RegExp(r'[^A-Za-z0-9._-]+'),
    '-',
  );
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
    this.taxPercent = 0,
    this.note = '',
  });

  final String description;
  final int quantity;
  final double unitPrice;
  final double taxPercent;
  final String note;

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
    this.roundOff = 0,
  });

  final double subtotal;
  final double discountAmount;
  final double taxPercent;
  final double taxAmount;
  final double grandTotal;
  final double paidAmount;
  final double balanceDue;
  final String paymentMode;
  final double roundOff;
}

class PdfInvoiceDocumentData extends PdfMedicalDocumentData {
  const PdfInvoiceDocumentData({
    super.letterheadConfig = DoctorLetterheadConfig.empty,
    required super.patient,
    required super.documentNumber,
    required super.documentDate,
    required this.items,
    required this.totals,
    super.notes,
    super.issuingDoctorUid,
    super.signedByUid,
    super.templateId,
    this.cancelled = false,
  }) : super(type: PdfMedicalDocumentType.invoice);

  final List<PdfInvoiceLineItem> items;
  final PdfMoneyTotals totals;
  final bool cancelled;

  @override
  String titleFor(bool gst) => gst ? 'TAX INVOICE' : 'INVOICE';
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
    super.letterheadConfig = DoctorLetterheadConfig.empty,
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
    super.issuingDoctorUid,
    super.signedByUid,
    super.templateId,
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
  const PdfReportSection({required this.title, required this.content});

  final String title;
  final String content;
}

class PdfMedicalReportDocumentData extends PdfMedicalDocumentData {
  const PdfMedicalReportDocumentData({
    super.letterheadConfig = DoctorLetterheadConfig.empty,
    required super.patient,
    required super.documentNumber,
    required super.documentDate,
    required this.reportTitle,
    required this.sections,
    super.notes,
    super.issuingDoctorUid,
    super.signedByUid,
    super.templateId,
  }) : super(type: PdfMedicalDocumentType.report);

  final String reportTitle;
  final List<PdfReportSection> sections;

  @override
  String titleFor(bool gst) => reportTitle.trim().isNotEmpty
      ? reportTitle.trim().toUpperCase()
      : 'MEDICAL REPORT';
}

class PdfReferralDocumentData extends PdfMedicalDocumentData {
  const PdfReferralDocumentData({
    super.letterheadConfig = DoctorLetterheadConfig.empty,
    required super.patient,
    required super.documentNumber,
    required super.documentDate,
    required this.recipient,
    this.reason = '',
    this.findings = '',
    this.question = '',
    this.teeth = '',
    this.urgency = '',
    this.isReply = false,
    this.reply = '',
    super.notes,
    super.issuingDoctorUid,
    super.signedByUid,
    super.templateId,
  }) : super(type: PdfMedicalDocumentType.referral);

  final String recipient;
  final String reason;
  final String findings;
  final String question;
  final String teeth;
  final String urgency;
  final bool isReply;
  final String reply;

  @override
  String titleFor(bool gst) => isReply ? 'REFERRAL REPLY' : 'REFERRAL LETTER';
}

class PdfCertificateDocumentData extends PdfMedicalDocumentData {
  const PdfCertificateDocumentData({
    super.letterheadConfig = DoctorLetterheadConfig.empty,
    required super.patient,
    required super.documentNumber,
    required super.documentDate,
    required this.title,
    required this.body,
    super.notes,
    super.issuingDoctorUid,
    super.signedByUid,
    super.templateId,
  }) : super(type: PdfMedicalDocumentType.certificate);

  final String title;
  final String body;

  @override
  String titleFor(bool gst) => title.trim().isNotEmpty
      ? title.trim().toUpperCase()
      : 'MEDICAL CERTIFICATE';
}
