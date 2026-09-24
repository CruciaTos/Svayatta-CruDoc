import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

enum ConsentType {
  treatment('Treatment plan'),
  parental('Parent / guardian'),
  surgical('Surgery or extraction'),
  general('General');

  const ConsentType(this.label);
  final String label;

  static ConsentType fromName(String n) =>
      values.firstWhere((t) => t.name == n, orElse: () => general);
}

String _template(
  ConsentType t,
  String patient,
  String details,
  String clinic,
) => switch (t) {
  ConsentType.treatment =>
    'I, $patient, have had the proposed treatment explained to me: $details.\n\n'
        'I understand what it involves, its benefits and risks, the alternatives '
        '(including no treatment) and the estimated cost. I have been able to ask '
        'questions and they were answered. I agree to go ahead with this treatment at $clinic.',
  ConsentType.parental =>
    'I am the parent or legal guardian of $patient. I consent to the dental '
        'examination and the treatment explained to me${details.isEmpty ? '' : ': $details'}, '
        'including local anaesthesia and child-friendly behaviour guidance where needed. '
        'I understand the benefits, risks and alternatives and may withdraw consent at any time.',
  ConsentType.surgical =>
    'I, $patient, consent to: $details.\n\n'
        'The possible risks have been explained, including pain, swelling, bleeding, '
        'infection, dry socket, temporary or rarely permanent numbness of the lip, chin or '
        'tongue, sinus involvement for upper teeth, and damage to neighbouring teeth or '
        'restorations. I have followed the pre-operative instructions and told the dentist '
        'about my medicines and allergies.',
  ConsentType.general =>
    'I, $patient, consent to the dental examination, X-rays and treatment explained to me'
        '${details.isEmpty ? '' : ': $details'}. I have been able to ask questions.',
};

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
  final _text = TextEditingController();
  late final _signer = TextEditingController(text: widget.patient.fullName);
  final _witness = TextEditingController();
  String _relationship = 'Patient';
  final _pad = SignatureController();
  bool _textEdited = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillPlan());
    _pad.addListener(() => setState(() {}));
  }

  /// The patient's open treatment plan fills the details.
  Future<void> _prefillPlan() async {
    if (_type != ConsentType.treatment) {
      _refreshText();
      return;
    }
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
    }
    _refreshText();
  }

  void _refreshText() {
    if (_textEdited) return;
    final clinic = ref.read(doctorIdentityProvider).clinicName ?? 'this clinic';
    setState(
      () => _text.text = _template(
        _type,
        widget.patient.fullName,
        _details.text.trim(),
        clinic,
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_details, _text, _signer, _witness]) {
      c.dispose();
    }
    _pad.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_pad.isEmpty &&
      _signer.text.trim().isNotEmpty &&
      _text.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_ready) return;
    setState(() => _saving = true);
    final png = await _pad.toPng();
    await saveDentalRecord(
      ref,
      DentalRecord.create(widget.patient.id, RecKind.consent, {
        'type': _type.name,
        'title': '${_type.label} consent',
        'details': _details.text.trim(),
        'text': _text.text.trim(),
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
    return CruFormDialog(
      title: 'New consent',
      subtitle: widget.patient.fullName,
      leading: const CruIconTile(
        icon: RecIcons.consent,
        tone: CruTileTone.accent,
      ),
      submitLabel: 'Sign and save',
      onSubmit: _ready
          ? _save
          : () => recToast(context, 'Add the signer\'s name and a signature.'),
      busy: _saving,
      dirty: !_pad.isEmpty,
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
                onTap: (t) {
                  setState(() {
                    _type = t;
                    if (t == ConsentType.parental &&
                        _relationship == 'Patient') {
                      _relationship = 'Parent';
                      _signer.clear();
                    }
                  });
                  _prefillPlan();
                },
              ),
              CruTextField(
                label: switch (_type) {
                  ConsentType.surgical => 'Procedure',
                  ConsentType.treatment => 'Treatment',
                  _ => 'Details',
                },
                optional:
                    _type == ConsentType.parental ||
                    _type == ConsentType.general,
                controller: _details,
                maxLines: 2,
                hint: _type == ConsentType.surgical
                    ? 'Surgical removal of impacted 38'
                    : null,
                onChanged: (_) => _refreshText(),
              ),
              CruTextField(
                label: 'Wording',
                controller: _text,
                maxLines: 8,
                help: 'Change anything; it\'s saved exactly as signed.',
                onChanged: (_) => _textEdited = true,
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

// ================================================================ pad

/// Holds the strokes of a [SignaturePad].
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = const Size(560, 160);

  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  void _start(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void _add(Offset p) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(p);
    notifyListeners();
  }

  /// The signature as a transparent PNG at twice the pad's size.
  Future<Uint8List?> toPng() async {
    if (isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(2);
    _paint(canvas, const Color(0xFF111111));
    final image = await recorder.endRecording().toImage(
      (_size.width * 2).round(),
      (_size.height * 2).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  void _paint(Canvas canvas, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in _strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final pt in s.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, p);
    }
  }
}

/// Sign with a mouse, pen or finger.
class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller, this.height = 160});

  final SignatureController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return LayoutBuilder(
      builder: (context, box) {
        controller._size = Size(box.maxWidth, height);
        return Container(
          height: height,
          decoration: ShapeDecoration(
            color: c.surface,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(color: c.hairline),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CruRadius.control),
            child: GestureDetector(
              onPanStart: (d) => controller._start(d.localPosition),
              onPanUpdate: (d) => controller._add(d.localPosition),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => CustomPaint(
                  size: Size(box.maxWidth, height),
                  painter: _PadPainter(controller, c.label),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.controller, this.color) : super(repaint: controller);

  final SignatureController controller;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => controller._paint(canvas, color);

  @override
  bool shouldRepaint(_PadPainter old) => true;
}
