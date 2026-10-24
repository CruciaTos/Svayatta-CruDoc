import 'doc_template.dart';

/// Body section ids. The renderer has one builder per id.
abstract final class DocSection {
  static const meta = 'meta';
  static const patient = 'patient';
  static const items = 'items';
  static const totals = 'totals';
  static const words = 'words';
  static const payment = 'payment';
  static const upi = 'upi';
  static const notes = 'notes';
  static const terms = 'terms';
  static const vitals = 'vitals';
  static const complaints = 'complaints';
  static const diagnosis = 'diagnosis';
  static const rx = 'rx';
  static const investigations = 'investigations';
  static const advice = 'advice';
  static const followUp = 'followUp';
  static const recipient = 'recipient';
  static const reason = 'reason';
  static const findings = 'findings';
  static const question = 'question';
  static const teeth = 'teeth';
  static const sections = 'sections';
  static const certificate = 'certificate';
  static const signature = 'signature';

  static const labels = <String, String>{
    meta: 'Title, number and date',
    patient: 'Patient details',
    items: 'Items table',
    totals: 'Totals',
    words: 'Amount in words',
    payment: 'Payment received / balance',
    upi: 'UPI pay QR',
    notes: 'Notes',
    terms: 'Terms',
    vitals: 'Vitals',
    complaints: 'Complaints',
    diagnosis: 'Diagnosis',
    rx: 'Medicines (Rx)',
    investigations: 'Investigations',
    advice: 'Advice',
    followUp: 'Follow-up',
    recipient: 'Referred to',
    reason: 'Reason',
    findings: 'Findings / summary',
    question: 'Question for the specialist',
    teeth: 'Teeth',
    sections: 'Report sections',
    certificate: 'Certificate text',
    signature: 'Signature',
  };
}

/// Default body for [kind]. `meta` is hidden by default; templates whose
/// header has no title/number/date turn it on.
List<DocBodySection> defaultBodySections(DocKind kind, {bool meta = false}) {
  final ids = switch (kind) {
    DocKind.invoice => [
      DocSection.meta,
      DocSection.patient,
      DocSection.items,
      DocSection.totals,
      DocSection.words,
      DocSection.payment,
      DocSection.upi,
      DocSection.notes,
      DocSection.terms,
      DocSection.signature,
    ],
    DocKind.prescription => [
      DocSection.meta,
      DocSection.patient,
      DocSection.vitals,
      DocSection.complaints,
      DocSection.diagnosis,
      DocSection.rx,
      DocSection.investigations,
      DocSection.advice,
      DocSection.followUp,
      DocSection.notes,
      DocSection.signature,
    ],
    DocKind.referral => [
      DocSection.meta,
      DocSection.patient,
      DocSection.recipient,
      DocSection.reason,
      DocSection.findings,
      DocSection.question,
      DocSection.teeth,
      DocSection.notes,
      DocSection.signature,
    ],
    DocKind.report => [
      DocSection.meta,
      DocSection.patient,
      DocSection.sections,
      DocSection.notes,
      DocSection.signature,
    ],
    DocKind.certificate => [
      DocSection.meta,
      DocSection.patient,
      DocSection.certificate,
      DocSection.signature,
    ],
  };
  return [
    for (final id in ids)
      DocBodySection(id, visible: id != DocSection.meta || meta),
  ];
}

/// Every kind's default body, with `meta` on or off.
Map<DocKind, List<DocBodySection>> defaultBodies({required bool meta}) => {
  for (final k in DocKind.values) k: defaultBodySections(k, meta: meta),
};
