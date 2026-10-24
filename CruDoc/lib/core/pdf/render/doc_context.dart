import 'dart:typed_data';

import '../models/pdf_document_models.dart';
import '../templates/doc_template.dart';
import 'pdf_text.dart';

class DocClinicInfo {
  const DocClinicInfo({
    this.name = '',
    this.tagline = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.timings = '',
    this.regNo = '',
    this.gstin = '',
    this.footerText = '',
    this.termsText = '',
    this.upiId = '',
    this.upiName = '',
    this.gstEnabled = false,
    this.roundOff = true,
  });

  final String name;
  final String tagline;
  final String address;
  final String phone;
  final String email;
  final String website;
  final String timings;
  final String regNo;
  final String gstin;
  final String footerText;
  final String termsText;
  final String upiId;
  final String upiName;
  final bool gstEnabled;
  final bool roundOff;
}

class DocDoctorInfo {
  const DocDoctorInfo({
    required this.uid,
    this.name = '',
    this.qualification = '',
    this.specialty = '',
    this.regNo = '',
    this.regCouncil = '',
    this.phone = '',
    this.email = '',
    this.active = true,
  });

  final String uid;
  final String name;
  final String qualification;
  final String specialty;
  final String regNo;
  final String regCouncil;
  final String phone;
  final String email;
  final bool active;
}

class DocImages {
  const DocImages({
    this.logo,
    this.signature,
    this.stamp,
    this.clinicStamp,
    this.background,
    this.custom = const {},
  });

  final Uint8List? logo;
  final Uint8List? signature;
  final Uint8List? stamp;
  final Uint8List? clinicStamp;
  final Uint8List? background;
  final Map<String, Uint8List> custom;

  Uint8List? forBlock(DocBlock b) => switch (b.imageRole) {
    DocImageRole.logo => logo,
    DocImageRole.signature => signature,
    DocImageRole.stamp => stamp,
    DocImageRole.clinicStamp => clinicStamp,
    DocImageRole.custom => custom[b.imageSha],
  };
}

enum DocFix { clinicDetails, myDetails, none }

class DocWarning {
  const DocWarning(this.message, {this.fix = DocFix.none});
  final String message;
  final DocFix fix;
}

class DocScriptImage {
  const DocScriptImage({
    required this.png,
    required this.widthPt,
    required this.heightPt,
  });

  final Uint8List png;
  final double widthPt;
  final double heightPt;
}

class DocContext {
  const DocContext({
    required this.data,
    required this.clinic,
    this.doctor,
    this.doctors = const [],
    this.images = const DocImages(),
    this.sample = false,
    this.warnings = const [],
    this.scriptImages = const {},
  });

  final PdfMedicalDocumentData data;
  final DocClinicInfo clinic;
  final DocDoctorInfo? doctor;
  final List<DocDoctorInfo> doctors;
  final DocImages images;
  final bool sample;
  final List<DocWarning> warnings;
  final Map<String, DocScriptImage> scriptImages;

  DocKind get kind => data.kind;

  String _join(List<String> parts) =>
      parts.map((s) => s.trim()).where((s) => s.isNotEmpty).join(' · ');

  String _status() {
    final docData = data;
    if (docData is! PdfInvoiceDocumentData) return '';
    final balance = docData.totals.balanceDue;
    if (balance > 0) {
      return 'Balance due ${formatPaise(toPaise(balance))}';
    }
    return 'PAID';
  }

  /// The text for a field key ('' when unknown or empty). Page values
  /// come from the PDF page being drawn.
  String field(String key, {int page = 1, int pages = 1}) {
    final c = clinic;
    final d = doctor;
    final p = data.patient;
    String reg(String no) => no.trim().isEmpty ? '' : 'Reg. No. ${no.trim()}';
    return pdfSafe(switch (key) {
      'clinic.name' => c.name,
      'clinic.tagline' => c.tagline,
      'clinic.address' => c.address,
      'clinic.phone' => c.phone,
      'clinic.email' => c.email,
      'clinic.website' => c.website,
      'clinic.timings' => c.timings,
      'clinic.regNo' => reg(c.regNo),
      'clinic.gstin' =>
        c.gstin.trim().isEmpty ? '' : 'GSTIN: ${c.gstin.trim()}',
      'clinic.contactLine' => _join([c.phone, c.email, c.website]),
      'clinic.addressContact' => _join([
        c.address.replaceAll('\n', ', '),
        c.phone,
        c.email,
      ]),
      'doctor.name' => d?.name ?? '',
      'doctor.qualification' => d?.qualification ?? '',
      'doctor.specialty' => d?.specialty ?? '',
      'doctor.regNo' => d == null ? '' : _join([reg(d.regNo), d.regCouncil]),
      'doctor.nameQual' => d == null ? '' : _join([d.name, d.qualification]),
      'doctor.specReg' => d == null ? '' : _join([d.specialty, reg(d.regNo)]),
      'doctor.phone' => d?.phone ?? '',
      'doctor.email' => d?.email ?? '',
      'doc.title' => data.titleFor(c.gstEnabled),
      'doc.number' => data.documentNumber,
      'doc.numberLine' =>
        data.documentNumber.isEmpty ? '' : 'No. ${data.documentNumber}',
      'doc.date' => formatDocDate(data.documentDate),
      'doc.dateLine' => 'Date: ${formatDocDate(data.documentDate)}',
      'doc.status' => _status(),
      'patient.name' => p.fullName,
      'patient.ageSex' => p.ageGender ?? '',
      'patient.phone' => p.phone ?? '',
      'patient.line' => _join([p.fullName, p.ageGender ?? '', p.phone ?? '']),
      'page.number' => pages > 1 ? 'Page $page of $pages' : '',
      'footer.text' => c.footerText,
      _ => '',
    });
  }

  /// Fills {{field.key}} placeholders in a text block.
  String fill(String text, {int page = 1, int pages = 1}) =>
      text.replaceAllMapped(
        RegExp(r'\{\{([a-zA-Z.]+)\}\}'),
        (m) => field(m[1]!, page: page, pages: pages),
      );

  /// upi://pay link for the invoice balance; null when there is nothing to pay or no UPI ID.
  String? upiUri() {
    final docData = data;
    if (docData is! PdfInvoiceDocumentData) return null;
    final upiId = clinic.upiId.trim();
    if (upiId.isEmpty) return null;
    final balancePaise = toPaise(docData.totals.balanceDue);
    if (balancePaise <= 0) return null;

    final pn =
        (clinic.upiName.trim().isNotEmpty
                ? clinic.upiName.trim()
                : clinic.name.trim())
            .trim();
    final amount = (balancePaise / 100).toStringAsFixed(2);
    final tn = docData.documentNumber.isNotEmpty
        ? 'Bill ${docData.documentNumber}'
        : 'Bill payment';

    return 'upi://pay?'
        'pa=${Uri.encodeComponent(upiId)}&'
        'pn=${Uri.encodeComponent(pn)}&'
        'am=${Uri.encodeComponent(amount)}&'
        'cu=INR&'
        'tn=${Uri.encodeComponent(tn)}';
  }
}
