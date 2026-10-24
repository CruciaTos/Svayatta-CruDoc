import '../models/pdf_document_models.dart';
import '../templates/doc_template.dart';
import 'doc_context.dart';

PdfMedicalDocumentData docSampleData(DocKind kind) {
  const patient = PdfPatientSnapshot(
    fullName: 'Sample Patient',
    ageGender: '34 Y / Female',
    phone: '+91 98765 43210',
    email: 'patient@example.com',
    patientId: 'PT-2026-001',
  );
  final now = DateTime(2026, 10, 24);

  return switch (kind) {
    DocKind.invoice => PdfInvoiceDocumentData(
      patient: patient,
      documentNumber: 'INV-26-27/0001',
      documentDate: now,
      items: const [
        PdfInvoiceLineItem(
          description: 'Consultation & Clinical Examination',
          quantity: 1,
          unitPrice: 500.0,
        ),
        PdfInvoiceLineItem(
          description: 'Ultrasonic Scaling & Polishing',
          quantity: 1,
          unitPrice: 1200.0,
        ),
        PdfInvoiceLineItem(
          description: 'Composite Restoration',
          quantity: 2,
          unitPrice: 1500.0,
          note: 'Tooth 36 & 37 occlusal',
        ),
      ],
      totals: const PdfMoneyTotals(
        subtotal: 4700.0,
        discountAmount: 200.0,
        taxPercent: 0.0,
        taxAmount: 0.0,
        grandTotal: 4500.0,
        paidAmount: 4500.0,
        balanceDue: 0.0,
        paymentMode: 'UPI',
      ),
      notes:
          'Thank you for your visit. Please maintain regular brushing twice daily.',
    ),
    DocKind.prescription => PdfPrescriptionDocumentData(
      patient: patient,
      documentNumber: 'RX-26-27/0001',
      documentDate: now,
      vitals: 'BP: 120/80 mmHg · Pulse: 72 bpm · Weight: 60 kg',
      complaints:
          'Mild pain and sensitivity in lower left back teeth for 3 days.',
      diagnosis: 'Localized gingivitis and moderate dental caries (Tooth 36).',
      medications: const [
        PdfPrescriptionMedication(
          drugName: 'Amoxicillin 500mg',
          dosage: '1 capsule',
          frequency: 'TDS (Three times a day)',
          duration: '5 days',
          instructions: 'After food',
        ),
        PdfPrescriptionMedication(
          drugName: 'Ibuprofen 400mg',
          dosage: '1 tablet',
          frequency: 'BD (Twice a day)',
          duration: '3 days',
          instructions: 'After food, SOS for pain',
        ),
        PdfPrescriptionMedication(
          drugName: 'Chlorhexidine 0.2% Mouthwash',
          dosage: '10 ml',
          frequency: 'BD (Twice a day)',
          duration: '7 days',
          instructions: 'Rinse for 1 minute then spit out',
        ),
      ],
      labTests: 'IOPA Radiograph (Tooth 36)',
      advice: 'Avoid hard and very cold foods. Maintain warm saline rinses.',
      followUp: 'Review after 5 days for filling check.',
      notes:
          'Take medications as prescribed. Contact clinic if swelling develops.',
    ),
    DocKind.referral => PdfReferralDocumentData(
      patient: patient,
      documentNumber: 'REF-26-27/0001',
      documentDate: now,
      recipient: 'Dr. R. Sharma (Oral & Maxillofacial Surgeon)',
      reason: 'Impacted mandibular third molar extraction',
      findings:
          'Symptomatic mesioangular impaction of tooth 48 with recurrent pericoronitis.',
      question: 'Surgical extraction of 48 under local anesthesia.',
      teeth: '48',
      urgency: 'Elective',
      notes: 'Patient is medically fit with no known drug allergies.',
    ),
    DocKind.report => PdfMedicalReportDocumentData(
      patient: patient,
      documentNumber: 'REP-26-27/0001',
      documentDate: now,
      reportTitle: 'Clinical Examination Report',
      sections: const [
        PdfReportSection(
          title: 'History & Chief Complaint',
          content:
              'Patient presented for routine annual oral health check-up with occasional bleeding gums on brushing.',
        ),
        PdfReportSection(
          title: 'Clinical & Radiographic Findings',
          content:
              'Generalized mild marginal gingivitis. Deep pits and fissures noted in mandibular molars with no frank cavitation.',
        ),
        PdfReportSection(
          title: 'Diagnosis & Treatment Rendered',
          content:
              'Generalized chronic gingivitis. Complete ultrasonic scaling and prophylaxis completed.',
        ),
        PdfReportSection(
          title: 'Recommendations & Prognosis',
          content:
              'Reinforced oral hygiene instructions. Fissure sealants recommended for preventive management. Good prognosis with regular maintenance.',
        ),
      ],
      notes: 'Annual follow-up examination advised in 6 months.',
    ),
    DocKind.certificate => PdfCertificateDocumentData(
      patient: patient,
      documentNumber: 'CERT-26-27/0001',
      documentDate: now,
      title: 'Medical Certificate',
      body:
          'This is to certify that Sample Patient, 34 years, was examined by me on 24 Oct 2026 and is advised rest from 24 Oct 2026 to 26 Oct 2026 (3 days) for dental treatment recovery.\n\nShe is advised to avoid strenuous physical activity during this period.',
      notes: 'Authorized certificate issued for leave/absence records.',
    ),
  };
}

DocContext docSampleContext(
  PdfMedicalDocumentData data, {
  DocClinicInfo? clinic,
  DocDoctorInfo? doctor,
  List<DocDoctorInfo>? doctors,
  DocImages images = const DocImages(),
}) {
  final clinicInfo =
      clinic ??
      const DocClinicInfo(
        name: 'CruDoc Polyclinic',
        tagline: 'Multi-Speciality Healthcare & Dental Care',
        address: '123 Healthcare Boulevard, Nariman Point, Mumbai - 400021',
        phone: '+91 98765 43210',
        email: 'care@crudoc.sample',
        website: 'www.crudoc.sample',
        timings: 'Mon - Sat: 9:00 AM - 8:00 PM\nSun: By Appointment',
        regNo: 'CL-2026/042',
        gstin: '27AAAAA0000A1Z5',
        footerText: 'CruDoc Practice Management System · www.crudoc.sample',
        termsText:
            'Payment due on presentation. Medicines once sold cannot be returned.',
        upiId: 'crudoc@sampleupi',
        upiName: 'CruDoc Clinic',
        gstEnabled: false,
        roundOff: true,
      );

  final doctorInfo =
      doctor ??
      const DocDoctorInfo(
        uid: 'sample-doc-1',
        name: 'Dr. Anand Verma',
        qualification: 'BDS, MDS (Periodontics)',
        specialty: 'Dental Surgeon & Periodontist',
        regNo: 'A-24680',
        regCouncil: 'Maharashtra State Dental Council',
        phone: '+91 91234 56789',
        email: 'dr.anand@crudoc.sample',
        active: true,
      );

  return DocContext(
    data: data,
    clinic: clinicInfo,
    doctor: doctorInfo,
    // A second made-up doctor only in fully sample previews; with a real
    // doctor the polyclinic header falls back to that doctor alone.
    doctors:
        doctors ??
        (doctor == null
            ? [
                doctorInfo,
                const DocDoctorInfo(
                  uid: 'sample-doc-2',
                  name: 'Dr. Meera Iyer',
                  qualification: 'MBBS, MD (Medicine)',
                  specialty: 'Consultant Physician',
                  regNo: 'B-13579',
                ),
              ]
            : const []),
    images: images,
    sample: true,
  );
}
