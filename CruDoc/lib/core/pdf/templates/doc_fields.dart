/// A value a header/footer block can show. Values are filled in by
/// `DocContext.field` (lib/core/pdf/render/doc_context.dart).
class DocFieldDef {
  const DocFieldDef(this.key, this.label, this.group, {this.multiline = false});

  final String key;
  final String label;
  final String group;
  final bool multiline;
}

const docFields = <DocFieldDef>[
  DocFieldDef('clinic.name', 'Clinic name', 'Clinic'),
  DocFieldDef('clinic.tagline', 'Tagline', 'Clinic'),
  DocFieldDef('clinic.address', 'Address', 'Clinic', multiline: true),
  DocFieldDef('clinic.phone', 'Phone', 'Clinic'),
  DocFieldDef('clinic.email', 'Email', 'Clinic'),
  DocFieldDef('clinic.website', 'Website', 'Clinic'),
  DocFieldDef('clinic.timings', 'Timings', 'Clinic', multiline: true),
  DocFieldDef('clinic.regNo', 'Clinic registration no.', 'Clinic'),
  DocFieldDef('clinic.gstin', 'GSTIN', 'Clinic'),
  DocFieldDef(
    'clinic.contactLine',
    'Phone · email · website',
    'Clinic',
    multiline: true,
  ),
  DocFieldDef(
    'clinic.addressContact',
    'Address · phone · email',
    'Clinic',
    multiline: true,
  ),
  DocFieldDef('doctor.name', 'Doctor name', 'Doctor'),
  DocFieldDef('doctor.qualification', 'Qualifications', 'Doctor'),
  DocFieldDef('doctor.specialty', 'Specialty', 'Doctor'),
  DocFieldDef('doctor.regNo', 'Registration no.', 'Doctor'),
  DocFieldDef('doctor.nameQual', 'Name · qualifications', 'Doctor'),
  DocFieldDef('doctor.specReg', 'Specialty · registration', 'Doctor'),
  DocFieldDef('doctor.phone', 'Doctor phone', 'Doctor'),
  DocFieldDef('doctor.email', 'Doctor email', 'Doctor'),
  DocFieldDef('doc.title', 'Document title', 'Document'),
  DocFieldDef('doc.number', 'Number', 'Document'),
  DocFieldDef('doc.numberLine', 'No. …', 'Document'),
  DocFieldDef('doc.date', 'Date', 'Document'),
  DocFieldDef('doc.dateLine', 'Date: …', 'Document'),
  DocFieldDef('doc.status', 'Paid / balance due', 'Document'),
  DocFieldDef('patient.name', 'Patient name', 'Patient'),
  DocFieldDef('patient.ageSex', 'Age / sex', 'Patient'),
  DocFieldDef('patient.phone', 'Patient phone', 'Patient'),
  DocFieldDef('patient.line', 'Name · age/sex · phone', 'Patient'),
  DocFieldDef('page.number', 'Page 1 of 2', 'Page'),
  DocFieldDef('footer.text', 'Footer note', 'Page', multiline: true),
];

DocFieldDef? docFieldDef(String key) {
  for (final f in docFields) {
    if (f.key == key) return f;
  }
  return null;
}
