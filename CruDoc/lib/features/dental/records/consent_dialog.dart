import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/signature_pad.dart';

enum ConsentType {
  treatment('Treatment plan'),
  implant('Dental implant'),
  parental('Parent / guardian'),
  surgical('Surgery or extraction'),
  general('General');

  const ConsentType(this.label);
  final String label;

  static ConsentType fromName(String n) =>
      values.firstWhere((t) => t.name == n, orElse: () => general);
}

/// The informational content and the statements a signer ticks, for one kind
/// of consent. Treatment info and risks are shown only when present — empty
/// sections are hidden, per the UI rules.
class _ConsentContent {
  const _ConsentContent({
    required this.purpose,
    required this.statements,
    this.treatmentInfo,
    this.risks = const [],
  });

  final String purpose;
  final String? treatmentInfo;
  final List<String> risks;
  final List<String> statements;
}

/// Acknowledgements common to every consent kind. Each kind appends its own
/// closing "I am giving consent to …" statement.
const List<String> _commonStatements = [
  'I have been given enough information about the treatment I am to receive and '
      'informed about the procedure. I understand the aims and objectives of the '
      'treatment completely.',
  'I have had the opportunity to ask any remaining questions and they were '
      'answered to the best of their ability.',
  'Having considered all aspects, I have decided to have the treatment of my own '
      'accord, and I understand the possible complications explained to me.',
  'If signing for someone other than myself, I confirm that I am the parent, '
      'legal guardian or substitute decision maker.',
];

_ConsentContent _content(ConsentType t, String patient, String details) {
  final d = details.trim();
  switch (t) {
    case ConsentType.implant:
      return _ConsentContent(
        purpose:
            'This consent sets out the risks, benefits and alternatives of the '
            'treatment. It is important that the patient fully understands the '
            'treatment beforehand. Before signing, the patient should ask the '
            'dentist any questions about the treatment, the dental implant and '
            'the procedure.',
        treatmentInfo:
            'A surgical fixture — the dental implant — is placed into the jawbone '
            'and allowed to fuse with the bone over a few months. The implant acts '
            'as an artificial replacement for the missing tooth root, holding a '
            'replacement tooth or bridge.',
        risks: const [
          'Infection',
          'Gum recession',
          'Loose implant',
          'Nerve or tissue damage',
          'Sinus issues (pain or swelling around the cheeks, eyes or forehead, '
              'nasal discharge, a blocked nose, a reduced sense of smell, sinus '
              'headaches, toothache, bad breath or a high temperature)',
          'Damage from excessive force',
        ],
        statements: [
          ..._commonStatements,
          'I am giving consent to receive the dental implant treatment'
              '${d.isEmpty ? '' : ' ($d)'}.',
        ],
      );
    case ConsentType.surgical:
      return _ConsentContent(
        purpose:
            'This consent records your agreement to the surgical procedure or '
            'extraction after its benefits, risks and alternatives have been '
            'explained${d.isEmpty ? '' : ': $d'}.',
        risks: const [
          'Pain, swelling and bleeding',
          'Infection or dry socket',
          'Temporary or, rarely, permanent numbness of the lip, chin or tongue',
          'Sinus involvement for upper teeth',
          'Damage to neighbouring teeth or restorations',
        ],
        statements: [
          ..._commonStatements,
          'I have followed the pre-operative instructions and told the dentist '
              'about my medicines and allergies.',
          'I am giving consent to receive the surgical / extraction treatment.',
        ],
      );
    case ConsentType.treatment:
      return _ConsentContent(
        purpose:
            'This consent records your agreement to the proposed treatment plan '
            'after its benefits, risks, alternatives (including no treatment) and '
            'the estimated cost have been explained'
            '${d.isEmpty ? '' : ': $d'}.',
        statements: [
          ..._commonStatements,
          'I am giving consent to proceed with the proposed treatment plan.',
        ],
      );
    case ConsentType.parental:
      return _ConsentContent(
        purpose:
            'As the parent or legal guardian of $patient, this consent records '
            'your agreement to the dental examination and the treatment explained '
            'to you${d.isEmpty ? '' : ': $d'}, including local anaesthesia and '
            'child-friendly behaviour guidance where needed.',
        statements: [
          ..._commonStatements,
          'I am giving consent, as parent or legal guardian, for the dental '
              'examination and treatment described.',
        ],
      );
    case ConsentType.general:
      return _ConsentContent(
        purpose:
            'This consent records your agreement to the dental examination, '
            'X-rays and treatment explained to you'
            '${d.isEmpty ? '' : ': $d'}.',
        statements: [
          ..._commonStatements,
          'I am giving consent to the dental examination, X-rays and treatment '
              'described.',
        ],
      );
  }
}

/// Flattens the content into the plain text saved on the record and printed on
/// the PDF, exactly as the signer agreed to it.
String _composeConsentText(_ConsentContent content) {
  final b = StringBuffer()..writeln(content.purpose);
  final info = content.treatmentInfo;
  if (info != null) {
    b
      ..writeln()
      ..writeln('Treatment information')
      ..writeln(info);
  }
  if (content.risks.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Risks and side effects:');
    for (final r in content.risks) {
      b.writeln('• $r');
    }
  }
  b
    ..writeln()
    ..writeln('Agreed by the signer:');
  for (final s in content.statements) {
    b.writeln('• $s');
  }
  return b.toString().trim();
}

/// A patient's signed consents, and a way to take a new one.
Future<void> showConsentListDialog(BuildContext context, Patient patient) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ConsentList(patient: patient),
    );

class _ConsentList extends ConsumerWidget {
  const _ConsentList({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final records =
        ref
            .watch(
              patientRecordsProvider((
                patientId: patient.id,
                kind: RecKind.consent,
              )),
            )
            .value ??
        const <DentalRecord>[];
    return DentalPanelDialog(
      title: 'Consents',
      subtitle: patient.fullName,
      leading: const CruIconTile(
        icon: RecIcons.consent,
        tone: CruTileTone.accent,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: Text(
                'No signed consents yet.',
                style: CruType.subhead.tint(c.label2),
              ),
            ),
          for (final r in records)
            DentalListRow(
              semanticLabel: r.str('title'),
              onTap: () => printConsent(context, ref, patient, r),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.str('title'),
                          style: CruType.callout.tint(c.label),
                        ),
                        Text(
                          'Signed by ${r.str('signer')}'
                          '${r.str('relationship') == 'Patient' ? '' : ' (${r.str('relationship').toLowerCase()})'}'
                          ' · ${DentalFormat.date(r.recordedAt)}, ${DentalFormat.time(r.recordedAt)}',
                          style: CruType.caption.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                  CruCapsuleButton(
                    label: 'Print',
                    onPressed: () => printConsent(context, ref, patient, r),
                  ),
                ],
              ),
            ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          CruButton(
            label: 'New consent',
            icon: CruIcons.plus,
            onPressed: () => showConsentDialog(context, patient),
          ),
        ],
      ),
    );
  }
}

/// Takes a consent: pick the kind, check the wording, sign on screen.
Future<void> showConsentDialog(
  BuildContext context,
  Patient patient, {
  ConsentType? type,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ConsentDialog(patient: patient, initialType: type),
);

class _ConsentDialog extends ConsumerStatefulWidget {
  const _ConsentDialog({required this.patient, this.initialType});

  final Patient patient;
  final ConsentType? initialType;

  @override
  ConsumerState<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends ConsumerState<_ConsentDialog> {
  late ConsentType _type;
  final _details = TextEditingController();
  late final _signer = TextEditingController(text: widget.patient.fullName);
  final _witness = TextEditingController();
  String _relationship = 'Patient';
  final _pad = SignatureController();
  List<bool> _checked = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type =
        widget.initialType ??
        (widget.patient.age < 18
            ? ConsentType.parental
            : ConsentType.treatment);
    if (_type == ConsentType.parental) {
      _relationship = 'Parent';
      _signer.clear();
    }
    _resetChecks();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillPlan());
    _pad.addListener(() => setState(() {}));
  }

  /// One unticked box per statement for the current kind.
  void _resetChecks() {
    final n = _content(
      _type,
      widget.patient.fullName,
      _details.text,
    ).statements.length;
    _checked = List<bool>.filled(n, false);
  }

  /// The patient's open treatment plan fills the details.
  Future<void> _prefillPlan() async {
    if (_type != ConsentType.treatment) return;
    final items = await ref.read(
      patientTreatmentPlanProvider(widget.patient.id).future,
    );
    final open = items
        .where(
          (i) =>
              !i.isDeleted &&
              TreatmentPlanItemStatus.fromString(i.status) !=
                  TreatmentPlanItemStatus.declined,
        )
        .toList();
    if (open.isNotEmpty && _details.text.isEmpty) {
      final total = open.fold<double>(0, (t, i) => t + i.estimatedPrice);
      _details.text =
          '${open.map((i) => i.procedureName).join(', ')} (estimated ₹${total.toStringAsFixed(0)})';
      if (mounted) setState(() {});
    }
  }

  void _selectType(ConsentType t) {
    setState(() {
      _type = t;
      if (t == ConsentType.parental && _relationship == 'Patient') {
        _relationship = 'Parent';
        _signer.clear();
      }
      _resetChecks();
    });
    _prefillPlan();
  }

  @override
  void dispose() {
    for (final c in [_details, _signer, _witness]) {
      c.dispose();
    }
    _pad.dispose();
    super.dispose();
  }

  bool get _allAgreed => _checked.isNotEmpty && _checked.every((v) => v);
  bool get _ready =>
      _allAgreed && !_pad.isEmpty && _signer.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_ready) return;
    setState(() => _saving = true);
    final content = _content(_type, widget.patient.fullName, _details.text);
    final png = await _pad.toPng();
    await saveDentalRecord(
      ref,
      DentalRecord.create(widget.patient.id, RecKind.consent, {
        'type': _type.name,
        'title': '${_type.label} consent',
        'details': _details.text.trim(),
        'text': _composeConsentText(content),
        'statements': content.statements.join('\n'),
        'signer': _signer.text.trim(),
        'relationship': _relationship,
        'witness': _witness.text.trim(),
        'signature': png == null ? '' : base64Encode(png),
      }),
    );
    if (mounted) {
      Navigator.of(context).pop();
      recToast(context, 'Consent signed and saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final patient = widget.patient;
    final content = _content(_type, patient.fullName, _details.text);
    final gender = patient.gender.trim();
    return CruFormDialog(
      title: 'New consent',
      subtitle: patient.fullName,
      leading: const CruIconTile(
        icon: RecIcons.consent,
        tone: CruTileTone.accent,
      ),
      submitLabel: 'Sign and save',
      onSubmit: _ready
          ? _save
          : () => recToast(
              context,
              'Tick each statement, add the signer\'s name and sign.',
            ),
      busy: _saving,
      dirty: _allAgreed || !_pad.isEmpty,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFormSection(
            first: true,
            title: 'Consent for',
            children: [
              DentalChipWrap<ConsentType>(
                options: ConsentType.values,
                label: (t) => t.label,
                isSelected: (t) => t == _type,
                onTap: _selectType,
              ),
              CruTextField(
                label: switch (_type) {
                  ConsentType.surgical => 'Procedure',
                  ConsentType.treatment => 'Treatment',
                  ConsentType.implant => 'Site / tooth',
                  _ => 'Details',
                },
                optional:
                    _type != ConsentType.treatment &&
                    _type != ConsentType.surgical,
                controller: _details,
                maxLines: 2,
                hint: switch (_type) {
                  ConsentType.implant => 'Implant at 46',
                  ConsentType.surgical => 'Surgical removal of impacted 38',
                  _ => null,
                },
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          CruFormSection(
            title: 'About this treatment',
            children: [
              _ConsentPara(
                title: 'Purpose of this consent',
                body: content.purpose,
              ),
              if (content.treatmentInfo != null)
                _ConsentPara(
                  title: 'Treatment information',
                  body: content.treatmentInfo!,
                ),
              if (content.risks.isNotEmpty)
                _ConsentRisks(items: content.risks),
            ],
          ),
          CruFormSection(
            title: 'Patient',
            children: [
              CruFieldRow(
                children: [
                  _ConsentValue(label: 'Name', value: patient.fullName),
                  _ConsentValue(
                    label: 'Date of birth',
                    value: DentalFormat.date(patient.dateOfBirth),
                  ),
                ],
              ),
              if (gender.isNotEmpty)
                _ConsentValue(label: 'Gender', value: gender),
            ],
          ),
          CruFormSection(
            title: 'Agreement',
            description: 'Tick each to confirm',
            children: [
              for (var i = 0; i < content.statements.length; i++)
                _ConsentCheck(
                  label: content.statements[i],
                  checked: i < _checked.length && _checked[i],
                  onChanged: (v) => setState(() {
                    if (i < _checked.length) _checked[i] = v;
                  }),
                ),
            ],
          ),
          CruFormSection(
            title: 'Signature',
            children: [
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'Signed by',
                    controller: _signer,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                  ),
                  CruFieldFrame(
                    label: 'Relationship',
                    child: DentalChipWrap<String>(
                      options: const ['Patient', 'Parent', 'Guardian'],
                      label: (s) => s,
                      isSelected: (s) => s == _relationship,
                      onTap: (s) => setState(() => _relationship = s),
                    ),
                  ),
                ],
              ),
              CruTextField(
                label: 'Witness',
                optional: true,
                controller: _witness,
                textCapitalization: TextCapitalization.words,
              ),
              _ConsentValue(
                label: 'Date',
                value: DentalFormat.date(DateTime.now()),
              ),
              Row(
                children: [
                  Text('Sign here', style: CruType.subhead.w600.tint(c.label)),
                  const Spacer(),
                  CruLink(
                    label: 'Clear',
                    onPressed: _pad.isEmpty ? null : _pad.clear,
                  ),
                ],
              ),
              SignaturePad(controller: _pad),
            ],
          ),
        ],
      ),
    );
  }
}

/// A sub-headed paragraph in the "About this treatment" section.
class _ConsentPara extends StatelessWidget {
  const _ConsentPara({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: CruType.callout.tint(c.label)),
        const SizedBox(height: CruSpace.s6),
        Text(body, style: CruType.subhead.tint(c.label2)),
      ],
    );
  }
}

/// The bulleted "Risks and side effects" list.
class _ConsentRisks extends StatelessWidget {
  const _ConsentRisks({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Risks and side effects', style: CruType.callout.tint(c.label)),
        const SizedBox(height: CruSpace.s8),
        for (final r in items)
          Padding(
            padding: const EdgeInsets.only(bottom: CruSpace.s6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: CruType.subhead.tint(c.label2)),
                Expanded(
                  child: Text(r, style: CruType.subhead.tint(c.label2)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A read-only labelled value (patient identity, date) in a filled field.
class _ConsentValue extends StatelessWidget {
  const _ConsentValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruFieldFrame(
      label: label,
      child: Container(
        height: CruSize.control,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        decoration: ShapeDecoration(
          color: c.inset,
          shape: cruShape(CruRadius.control),
        ),
        child: Text(value, style: CruType.body.tabular.tint(c.label)),
      ),
    );
  }
}

/// One tappable agreement statement with a check box. Uses the near-black
/// selected fill (never Ink Blue, which the rules reserve for the primary
/// action).
class _ConsentCheck extends StatelessWidget {
  const _ConsentCheck({
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: () => onChanged(!checked),
      semanticLabel: label,
      builder: (context, hovered) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: checked ? c.label : c.surface,
              shape: cruShape(
                CruRadius.keycap,
                side: checked
                    ? BorderSide.none
                    : BorderSide(color: hovered ? c.label3 : c.hairline),
              ),
            ),
            child: checked
                ? CruIcon(
                    CruIcons.check,
                    size: 14,
                    strokeWidth: 2.2,
                    color: c.surface,
                  )
                : null,
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: CruSpace.s2),
              child: Text(label, style: CruType.subhead.tint(c.label2)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prints a signed consent (wording, signer and the signature).
Future<void> printConsent(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
  DentalRecord r,
) async {
  final identity = ref.read(doctorIdentityProvider);
  Uint8List? sig;
  try {
    final s = r.str('signature');
    if (s.isNotEmpty) sig = base64Decode(s);
  } catch (_) {}
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            identity.clinicName ?? identity.fullName ?? '',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          if (identity.fullName != null) pw.Text(identity.fullName!),
          pw.SizedBox(height: 20),
          pw.Text(
            r.str('title'),
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Patient: ${patient.fullName}'),
          pw.SizedBox(height: 14),
          pw.Text(
            r.str('text').replaceAll('₹', 'Rs '),
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
          ),
          pw.SizedBox(height: 28),
          if (sig != null) pw.Image(pw.MemoryImage(sig), height: 70),
          pw.Container(width: 220, height: 0.6, color: PdfColors.grey700),
          pw.Text('${r.str('signer')} (${r.str('relationship')})'),
          pw.Text(
            'Signed ${DentalFormat.date(r.recordedAt)}, ${DentalFormat.time(r.recordedAt)}',
          ),
          if (r.str('witness').isNotEmpty)
            pw.Text('Witness: ${r.str('witness')}'),
        ],
      ),
    ),
  );
  await Printing.layoutPdf(name: r.str('title'), onLayout: (_) => doc.save());
}
