import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _pulpalOptions = [
  'Normal pulp',
  'Reversible pulpitis',
  'Symptomatic irreversible pulpitis',
  'Asymptomatic irreversible pulpitis',
  'Pulp necrosis',
  'Previously treated',
  'Previously initiated',
];

const _periapicalOptions = [
  'Normal apical tissues',
  'Symptomatic apical periodontitis',
  'Asymptomatic apical periodontitis',
  'Acute apical abscess',
  'Chronic apical abscess',
  'Condensing osteitis',
];

/// Vitality tests and the results each can have.
const _tests = <String, List<String>>{
  'Cold': ['Normal', 'No response', 'Lingering', 'Exaggerated'],
  'Heat': ['Normal', 'No response', 'Lingering', 'Exaggerated'],
  'EPT': ['Responsive', 'No response'],
  'Percussion': ['Normal', 'Tender'],
  'Palpation': ['Normal', 'Tender'],
};

const _canalNames = [
  'MB',
  'MB2',
  'DB',
  'P',
  'M',
  'D',
  'ML',
  'DL',
  'B',
  'L',
  'Single',
];
const _techniques = [
  'Cold lateral condensation',
  'Warm vertical',
  'Single cone',
  'Continuous wave',
  'Carrier-based',
];
const _materials = [
  'Gutta-percha',
  'Bioceramic cones',
  'Thermoplastic GP',
  'MTA',
];

const _postOpTemplate =
    'After your root canal treatment:\n'
    '• Numbness wears off in 2–4 hours; avoid chewing on that side until then.\n'
    '• Mild soreness for a few days is normal; take the painkiller as advised.\n'
    '• Avoid hard or sticky food on the tooth until the final crown or filling is done.\n'
    '• Call us if you have swelling, severe pain, fever or the temporary filling falls out.';

String _endoSummary(DentalRecord r) {
  final canals = r.data['canals'] is List
      ? (r.data['canals'] as List).length
      : 0;
  return [
    if (r.str('pulpal').isNotEmpty) r.str('pulpal'),
    if (canals > 0) '$canals canal${canals == 1 ? '' : 's'}',
    r.str('status') == 'obturated' ? 'Obturated' : 'In progress',
  ].join(' · ');
}

/// A patient's endodontic records: one per tooth treated.
Future<void> showEndoListDialog(BuildContext context, Patient patient) =>
    showDialog<void>(
      context: context,
      builder: (_) => _EndoList(patient: patient),
    );

class _EndoList extends ConsumerWidget {
  const _EndoList({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final records =
        ref
            .watch(
              patientRecordsProvider((
                patientId: patient.id,
                kind: RecKind.endo,
              )),
            )
            .value ??
        const <DentalRecord>[];
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    return DentalPanelDialog(
      title: 'Endodontics',
      subtitle: patient.fullName,
      leading: const CruIconTile(icon: RecIcons.endo, tone: CruTileTone.accent),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: Text(
                'No endodontic records yet.',
                style: CruType.subhead.tint(c.label2),
              ),
            ),
          for (final r in records)
            DentalListRow(
              semanticLabel: 'Tooth ${toothLabel(r.str('tooth'), numbering)}',
              onTap: () => showEndoDialog(context, patient, existing: r),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      toothLabel(r.str('tooth'), numbering),
                      style: CruType.headline.tabular.tint(c.label),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DentalChart.name(r.str('tooth')),
                          style: CruType.callout.tint(c.label),
                        ),
                        Text(
                          _endoSummary(r),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.caption.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    DentalFormat.date(r.recordedAt),
                    style: CruType.caption.tabular.tint(c.label2),
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
            label: 'New endo record',
            icon: CruIcons.plus,
            onPressed: () => showEndoDialog(context, patient),
          ),
        ],
      ),
    );
  }
}

/// Add or edit one tooth's endo record: diagnosis, vitality tests,
/// canals with working lengths, obturation and post-op instructions.
Future<void> showEndoDialog(
  BuildContext context,
  Patient patient, {
  DentalRecord? existing,
  String? tooth,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _EndoDialog(patient: patient, existing: existing, tooth: tooth),
);

class _Canal {
  _Canal(
    this.name, {
    String wl = '',
    String ref = '',
    String file = '',
    String notes = '',
  }) : wl = TextEditingController(text: wl),
       ref = TextEditingController(text: ref),
       file = TextEditingController(text: file),
       notes = TextEditingController(text: notes);

  String name;
  final TextEditingController wl;
  final TextEditingController ref;
  final TextEditingController file;
  final TextEditingController notes;

  void dispose() {
    wl.dispose();
    ref.dispose();
    file.dispose();
    notes.dispose();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'wl': double.tryParse(wl.text.trim()),
    'ref': ref.text.trim(),
    'file': file.text.trim(),
    'notes': notes.text.trim(),
  };
}

class _EndoDialog extends ConsumerStatefulWidget {
  const _EndoDialog({required this.patient, this.existing, this.tooth});

  final Patient patient;
  final DentalRecord? existing;
  final String? tooth;

  @override
  ConsumerState<_EndoDialog> createState() => _EndoDialogState();
}

class _EndoDialogState extends ConsumerState<_EndoDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _tooth;
  late final TextEditingController _sealer;
  late final TextEditingController _ept;
  late final TextEditingController _postOp;
  late final TextEditingController _notes;
  String _pulpal = '';
  String _periapical = '';
  final Map<String, String> _results = {};
  final List<_Canal> _canals = [];
  String _technique = '';
  String _material = '';
  DateTime? _obturatedOn;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _tooth = TextEditingController(text: e?.str('tooth') ?? widget.tooth ?? '');
    _sealer = TextEditingController(text: e?.str('sealer') ?? '');
    _ept = TextEditingController(text: e?.str('eptReading') ?? '');
    _postOp = TextEditingController(
      text: e?.str('postOp').isNotEmpty == true
          ? e!.str('postOp')
          : _postOpTemplate,
    );
    _notes = TextEditingController(text: e?.str('notes') ?? '');
    _pulpal = e?.str('pulpal') ?? '';
    _periapical = e?.str('periapical') ?? '';
    final tests = e?.data['tests'];
    if (tests is Map) {
      for (final t in tests.entries) {
        _results['${t.key}'] = '${t.value}';
      }
    }
    final canals = e?.data['canals'];
    if (canals is List) {
      for (final c in canals) {
        if (c is! Map) continue;
        _canals.add(
          _Canal(
            '${c['name'] ?? 'Single'}',
            wl: c['wl'] == null ? '' : '${c['wl']}',
            ref: '${c['ref'] ?? ''}',
            file: '${c['file'] ?? ''}',
            notes: '${c['notes'] ?? ''}',
          ),
        );
      }
    }
    _technique = e?.str('technique') ?? '';
    _material = e?.str('material') ?? '';
    _obturatedOn = e?.date('obturatedOn');
  }

  @override
  void dispose() {
    for (final c in [_tooth, _sealer, _ept, _postOp, _notes]) {
      c.dispose();
    }
    for (final c in _canals) {
      c.dispose();
    }
    super.dispose();
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  static bool _validTooth(String t) {
    final n = int.tryParse(t);
    if (n == null || t.length != 2) return false;
    final q = n ~/ 10, i = n % 10;
    return (q >= 1 && q <= 4 && i >= 1 && i <= 8) ||
        (q >= 5 && q <= 8 && i >= 1 && i <= 5);
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final data = {
      'tooth': _tooth.text.trim(),
      'pulpal': _pulpal,
      'periapical': _periapical,
      'tests': _results,
      'eptReading': _ept.text.trim(),
      'canals': [for (final c in _canals) c.toJson()],
      'technique': _technique,
      'material': _material,
      'sealer': _sealer.text.trim(),
      'obturatedOn': _obturatedOn?.millisecondsSinceEpoch,
      'status': _obturatedOn != null ? 'obturated' : 'inProgress',
      'postOp': _postOp.text.trim(),
      'notes': _notes.text.trim(),
    };
    final e = widget.existing;
    await saveDentalRecord(
      ref,
      e == null
          ? DentalRecord.create(widget.patient.id, RecKind.endo, data)
          : e.copyWith(data: data),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await confirmDental(
      context,
      title: 'Delete this endo record?',
      body: 'Tooth ${e.str('tooth')} and its canal details will be removed.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    await deleteDentalRecord(ref, e);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruFormDialog(
      title: widget.existing == null ? 'Endo record' : 'Tooth ${_tooth.text}',
      subtitle: widget.patient.fullName,
      leading: const CruIconTile(icon: RecIcons.endo, tone: CruTileTone.accent),
      submitLabel: 'Save',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      footerHint: 'Ctrl + Enter to save',
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Diagnosis',
              description: 'AAE terms, pulpal and periapical.',
              children: [
                CruTextField(
                  label: 'Tooth (FDI)',
                  controller: _tooth,
                  tabular: true,
                  hint: '36',
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  validator: (v) => _validTooth((v ?? '').trim())
                      ? null
                      : 'Enter an FDI tooth number.',
                  onChanged: (_) {
                    _edited();
                    setState(() {});
                  },
                ),
                CruFieldFrame(
                  label: 'Pulpal',
                  child: DentalChipWrap<String>(
                    options: _pulpalOptions,
                    label: (s) => s,
                    isSelected: (s) => s == _pulpal,
                    onTap: (s) {
                      setState(() => _pulpal = _pulpal == s ? '' : s);
                      _edited();
                    },
                  ),
                ),
                CruFieldFrame(
                  label: 'Periapical',
                  child: DentalChipWrap<String>(
                    options: _periapicalOptions,
                    label: (s) => s,
                    isSelected: (s) => s == _periapical,
                    onTap: (s) {
                      setState(() => _periapical = _periapical == s ? '' : s);
                      _edited();
                    },
                  ),
                ),
              ],
            ),
            CruFormSection(
              title: 'Vitality tests',
              description: 'Tap a result for each test done.',
              children: [
                for (final t in _tests.entries)
                  Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          t.key,
                          style: CruType.subhead.w500.tint(c.label),
                        ),
                      ),
                      Expanded(
                        child: DentalChipWrap<String>(
                          options: t.value,
                          label: (s) => s,
                          isSelected: (s) => _results[t.key] == s,
                          onTap: (s) {
                            setState(
                              () => _results[t.key] == s
                                  ? _results.remove(t.key)
                                  : _results[t.key] = s,
                            );
                            _edited();
                          },
                        ),
                      ),
                    ],
                  ),
                CruTextField(
                  label: 'EPT reading',
                  optional: true,
                  controller: _ept,
                  tabular: true,
                  hint: '42 (control tooth 28)',
                  onChanged: (_) => _edited(),
                ),
              ],
            ),
            CruFormSection(
              title: 'Canals',
              description: _canals.isEmpty
                  ? 'Add each canal with its working length.'
                  : '${_canals.length} canal${_canals.length == 1 ? '' : 's'}',
              children: [
                for (final canal in _canals)
                  Container(
                    padding: const EdgeInsets.all(CruSpace.s12),
                    decoration: ShapeDecoration(
                      color: c.inset,
                      shape: cruShape(CruRadius.control),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: CruSpace.s6,
                                runSpacing: CruSpace.s6,
                                children: [
                                  for (final n in _canalNames)
                                    DentalChoiceChip(
                                      label: n,
                                      onSurface: true,
                                      selected: canal.name == n,
                                      onTap: () {
                                        setState(() => canal.name = n);
                                        _edited();
                                      },
                                    ),
                                ],
                              ),
                            ),
                            CruIconButton(
                              icon: CruIcons.close,
                              semanticLabel: 'Remove canal',
                              tooltip: 'Remove canal',
                              onPressed: () {
                                setState(() {
                                  _canals.remove(canal);
                                  canal.dispose();
                                });
                                _edited();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: CruSpace.s8),
                        CruFieldRow(
                          children: [
                            CruTextField(
                              label: 'Working length',
                              controller: canal.wl,
                              tabular: true,
                              trailing: Text(
                                'mm',
                                style: CruType.subhead.tint(c.label3),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]'),
                                ),
                              ],
                              onChanged: (_) => _edited(),
                            ),
                            CruTextField(
                              label: 'Reference',
                              optional: true,
                              controller: canal.ref,
                              hint: 'MB cusp',
                              onChanged: (_) => _edited(),
                            ),
                            CruTextField(
                              label: 'Master file',
                              optional: true,
                              controller: canal.file,
                              hint: '25/.06',
                              onChanged: (_) => _edited(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CruButton(
                    label: 'Add canal',
                    icon: CruIcons.plus,
                    kind: CruButtonKind.secondary,
                    onPressed: () {
                      final used = _canals.map((c) => c.name).toSet();
                      setState(
                        () => _canals.add(
                          _Canal(
                            _canalNames.firstWhere(
                              (n) => !used.contains(n),
                              orElse: () => 'Single',
                            ),
                          ),
                        ),
                      );
                      _edited();
                    },
                  ),
                ),
              ],
            ),
            CruFormSection(
              title: 'Obturation',
              children: [
                CruFieldFrame(
                  label: 'Technique',
                  optional: true,
                  child: DentalChipWrap<String>(
                    options: _techniques,
                    label: (s) => s,
                    isSelected: (s) => s == _technique,
                    onTap: (s) {
                      setState(() => _technique = _technique == s ? '' : s);
                      _edited();
                    },
                  ),
                ),
                CruFieldFrame(
                  label: 'Material',
                  optional: true,
                  child: DentalChipWrap<String>(
                    options: _materials,
                    label: (s) => s,
                    isSelected: (s) => s == _material,
                    onTap: (s) {
                      setState(() => _material = _material == s ? '' : s);
                      _edited();
                    },
                  ),
                ),
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Sealer',
                      optional: true,
                      controller: _sealer,
                      hint: 'AH Plus',
                      onChanged: (_) => _edited(),
                    ),
                    CruPickerField(
                      label: 'Obturated on',
                      optional: true,
                      icon: CruIcons.calendar,
                      value: _obturatedOn == null
                          ? null
                          : DentalFormat.date(_obturatedOn!),
                      placeholder: 'Not yet',
                      trailing: _obturatedOn == null
                          ? null
                          : CruIconButton(
                              icon: CruIcons.close,
                              size: CruSize.rowCapsule,
                              iconSize: 12,
                              semanticLabel: 'Clear date',
                              onPressed: () {
                                setState(() => _obturatedOn = null);
                                _edited();
                              },
                            ),
                      onTap: () async {
                        final d = await pickDentalDate(
                          context,
                          initial: _obturatedOn ?? DateTime.now(),
                          last: DateTime.now(),
                        );
                        if (d != null) {
                          setState(() => _obturatedOn = d);
                          _edited();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            CruFormSection(
              title: 'Post-op instructions',
              description: 'Edit, then send to the patient.',
              children: [
                CruTextField(
                  label: 'Instructions',
                  controller: _postOp,
                  maxLines: 6,
                  onChanged: (_) => _edited(),
                ),
                Wrap(
                  spacing: CruSpace.s8,
                  children: [
                    CruButton(
                      label: 'Send on WhatsApp',
                      icon: CruIcons.whatsapp,
                      kind: CruButtonKind.secondary,
                      onPressed: () => PatientActions.whatsApp(
                        context,
                        widget.patient,
                        message: _postOp.text.trim(),
                      ),
                    ),
                    CruButton(
                      label: 'Copy',
                      kind: CruButtonKind.secondary,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _postOp.text.trim()),
                        );
                        if (context.mounted) {
                          recToast(context, 'Instructions copied');
                        }
                      },
                    ),
                  ],
                ),
                CruTextField(
                  label: 'Notes',
                  optional: true,
                  controller: _notes,
                  maxLines: 2,
                  onChanged: (_) => _edited(),
                ),
                if (widget.existing != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruLink(
                      label: 'Delete this record',
                      onPressed: _delete,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Short line for the records card.
String endoCardLine(List<DentalRecord> records) {
  if (records.isEmpty) return 'No endo records';
  final teeth =
      records
          .map((r) => r.str('tooth'))
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  final open = records.where((r) => r.str('status') != 'obturated').length;
  return 'Teeth ${teeth.join(', ')}${open > 0 ? ' · $open in progress' : ''}';
}
