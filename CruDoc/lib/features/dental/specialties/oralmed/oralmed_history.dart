import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Systemic conditions asked about in the oral medicine history.
const omConditions = [
  'Diabetes',
  'Hypertension',
  'Thyroid',
  'Asthma',
  'Epilepsy',
  'Bleeding disorder',
  'Hepatitis',
  'HIV',
  'Pregnancy',
  'Cancer / radiotherapy',
  'Other',
];

const _tobacco = {
  'none': 'None',
  'smoked': 'Smoked',
  'chewed': 'Chewed',
  'both': 'Smoked and chewed',
};

const _alcohol = {
  'none': 'None',
  'occasional': 'Occasional',
  'regular': 'Regular',
};

List<Map<String, String>> _rows(Object? raw, List<String> keys) => [
      if (raw is List)
        for (final r in raw)
          if (r is Map) {for (final k in keys) k: '${r[k] ?? ''}'.trim()},
    ];

/// The patient's oral medicine history (newest record), or null.
DentalRecord? omHistoryOf(List<DentalRecord> records) =>
    records.isEmpty ? null : records.first;

/// "Penicillin (rash), Latex"; "None" when the dentist recorded no known
/// allergies; null when allergies weren't recorded.
String? omAllergyText(DentalRecord? r) {
  if (r == null) return null;
  final list = _rows(r.data['allergies'], const ['to', 'reaction'])
      .where((a) => a['to']!.isNotEmpty)
      .map((a) => a['reaction']!.isEmpty ? a['to']! : '${a['to']} (${a['reaction']})')
      .toList();
  if (list.isNotEmpty) return list.join(', ');
  return r.data['nka'] == true ? 'None' : null;
}

/// Tobacco or areca nut use: screen for potentially malignant disorders.
bool omHighRisk(DentalRecord? r) {
  final habits = r?.data['habits'];
  if (habits is! Map) return false;
  final t = '${habits['tobacco'] ?? 'none'}';
  return t != 'none' || habits['arecaNut'] == true;
}

/// "Diabetes, Hypertension · 2 medicines"; "Not recorded yet" when empty.
String omCardLine(DentalRecord? r) {
  if (r == null) return 'Not recorded yet';
  final conditions = r.data['systemic'] is List
      ? (r.data['systemic'] as List).map((e) => '$e').toList()
      : const <String>[];
  final meds = _rows(r.data['medications'], const ['name'])
      .where((m) => m['name']!.isNotEmpty)
      .length;
  final parts = [
    if (conditions.isNotEmpty) conditions.join(', ') else 'No systemic conditions',
    if (meds > 0) '$meds medicine${meds == 1 ? '' : 's'}',
    if (omHighRisk(r)) 'high-risk habits',
  ];
  return parts.join(' · ');
}

/// Records or updates the patient's oral medicine history.
Future<void> showOmHistoryDialog(
  BuildContext context,
  Patient patient, {
  DentalRecord? existing,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _OmHistoryDialog(patient: patient, existing: existing),
    );

class _Line {
  _Line(List<String> values)
      : fields = [for (final v in values) TextEditingController(text: v)];

  final List<TextEditingController> fields;

  void dispose() {
    for (final f in fields) {
      f.dispose();
    }
  }
}

class _OmHistoryDialog extends ConsumerStatefulWidget {
  const _OmHistoryDialog({required this.patient, this.existing});

  final Patient patient;
  final DentalRecord? existing;

  @override
  ConsumerState<_OmHistoryDialog> createState() => _OmHistoryDialogState();
}

class _OmHistoryDialogState extends ConsumerState<_OmHistoryDialog> {
  final Set<String> _conditions = {};
  final _conditionNotes = TextEditingController();
  final List<_Line> _meds = [];
  final List<_Line> _allergies = [];
  bool _nka = false;
  String _tobaccoUse = 'none';
  final _packYears = TextEditingController();
  bool _areca = false;
  String _alcoholUse = 'none';
  final _complaint = TextEditingController();
  final _duration = TextEditingController();
  bool _dirty = false;
  bool _saving = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final d = widget.existing?.data ?? const <String, dynamic>{};
    if (d['systemic'] is List) {
      _conditions.addAll((d['systemic'] as List).map((e) => '$e'));
    }
    _conditionNotes.text = '${d['systemicNotes'] ?? ''}';
    for (final m in _rows(d['medications'], const ['name', 'dose', 'frequency'])) {
      _meds.add(_Line([m['name']!, m['dose']!, m['frequency']!]));
    }
    for (final a in _rows(d['allergies'], const ['to', 'reaction'])) {
      _allergies.add(_Line([a['to']!, a['reaction']!]));
    }
    _nka = d['nka'] == true;
    final h = d['habits'];
    if (h is Map) {
      _tobaccoUse = _tobacco.containsKey(h['tobacco']) ? '${h['tobacco']}' : 'none';
      final py = h['packYears'];
      _packYears.text = py is num && py > 0 ? '$py' : '';
      _areca = h['arecaNut'] == true;
      _alcoholUse = _alcohol.containsKey(h['alcohol']) ? '${h['alcohol']}' : 'none';
    }
    _complaint.text = '${d['complaint'] ?? ''}';
    _duration.text = '${d['duration'] ?? ''}';
  }

  @override
  void dispose() {
    _conditionNotes.dispose();
    _packYears.dispose();
    _complaint.dispose();
    _duration.dispose();
    for (final l in [..._meds, ..._allergies]) {
      l.dispose();
    }
    super.dispose();
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Map<String, dynamic> _data() {
    List<Map<String, String>> rows(List<_Line> lines, List<String> keys) => [
          for (final l in lines)
            if (l.fields.first.text.trim().isNotEmpty)
              {
                for (var i = 0; i < keys.length; i++)
                  keys[i]: l.fields[i].text.trim(),
              },
        ];
    final allergies = rows(_allergies, const ['to', 'reaction']);
    return {
      'systemic': [for (final c in omConditions) if (_conditions.contains(c)) c],
      'systemicNotes': _conditionNotes.text.trim(),
      'medications': rows(_meds, const ['name', 'dose', 'frequency']),
      'allergies': allergies,
      'nka': allergies.isEmpty && _nka,
      'habits': {
        'tobacco': _tobaccoUse,
        'packYears': _tobaccoUse == 'smoked' || _tobaccoUse == 'both'
            ? num.tryParse(_packYears.text.trim()) ?? 0
            : 0,
        'arecaNut': _areca,
        'alcohol': _alcoholUse,
      },
      'complaint': _complaint.text.trim(),
      'duration': _duration.text.trim(),
    };
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final data = _data();
      final e = widget.existing;
      final draft = DentalRecord.create(widget.patient.id, RecKind.omHistory, data);
      final versions = [
        if (e?.data['versions'] is List) ...(e!.data['versions'] as List),
        {
          'at': DateTime.now().millisecondsSinceEpoch,
          'summary': omCardLine(draft),
        },
      ];
      final r = e == null
          ? DentalRecord.create(
              widget.patient.id,
              RecKind.omHistory,
              {...data, 'versions': versions},
            )
          : e.copyWith(data: {...data, 'versions': versions}, recordedAt: DateTime.now());
      await saveDentalRecord(ref, r);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() {
        _saving = false;
        _notice = "Couldn't save the history. Try again.";
      });
    }
  }

  Widget _lines({
    required List<_Line> lines,
    required List<String> labels,
    required List<String> hints,
    required List<int> flex,
    required String addLabel,
    required List<String> blank,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: CruSpace.s8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CruFieldRow(
                    flex: flex,
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        CruTextField(
                          label: labels[i],
                          controller: l.fields[i],
                          hint: hints[i],
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => _edited(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: CruSpace.s6),
                CruIconButton(
                  icon: CruIcons.close,
                  size: CruSize.control,
                  iconSize: 16,
                  semanticLabel: 'Remove',
                  tooltip: 'Remove',
                  onPressed: () => setState(() {
                    lines.remove(l);
                    l.dispose();
                    _dirty = true;
                  }),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: CruCapsuleButton(
            label: addLabel,
            icon: CruIcons.plus,
            onPressed: () => setState(() {
              lines.add(_Line(blank));
              _dirty = true;
            }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final smoker = _tobaccoUse == 'smoked' || _tobaccoUse == 'both';
    final highRisk = _tobaccoUse != 'none' || _areca;
    final updated = widget.existing?.updatedAt;
    return CruFormDialog(
      title: 'Oral medicine history',
      subtitle: widget.patient.fullName,
      leading: const CruIconTile(icon: RecIcons.consent, tone: CruTileTone.accent),
      submitLabel: 'Save history',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: updated == null ? null : 'Last updated ${DentalFormat.date(updated)}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFormSection(
            first: true,
            title: 'Systemic conditions',
            description: 'Tick what the patient has now or had.',
            children: [
              DentalChipWrap<String>(
                options: omConditions,
                label: (s) => s,
                isSelected: _conditions.contains,
                onTap: (s) {
                  setState(() => _conditions.contains(s)
                      ? _conditions.remove(s)
                      : _conditions.add(s));
                  _edited();
                },
              ),
              CruTextField(
                label: 'Notes',
                optional: true,
                controller: _conditionNotes,
                maxLines: 2,
                hint: 'Type 2 diabetes since 2019, HbA1c 7.1',
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _edited(),
              ),
            ],
          ),
          CruFormSection(
            title: 'Medicines',
            description: 'What the patient takes regularly.',
            children: [
              _lines(
                lines: _meds,
                labels: const ['Medicine', 'Dose', 'How often'],
                hints: const ['Metformin', '500 mg', 'Twice a day'],
                flex: const [3, 2, 2],
                addLabel: 'Add medicine',
                blank: const ['', '', ''],
              ),
              Container(
                padding: const EdgeInsets.all(CruSpace.s12),
                decoration: ShapeDecoration(
                  color: c.inset,
                  shape: cruShape(CruRadius.control),
                ),
                child: Text(
                  'Checking medicines against each other needs a drug '
                  'database: not connected yet.',
                  style: CruType.subhead.tint(c.label2),
                ),
              ),
            ],
          ),
          CruFormSection(
            title: 'Allergies',
            description: 'Shown in red on the patient record.',
            children: [
              if (_allergies.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: DentalChoiceChip(
                    label: 'No known allergies',
                    selected: _nka,
                    onTap: () {
                      setState(() => _nka = !_nka);
                      _edited();
                    },
                  ),
                ),
              _lines(
                lines: _allergies,
                labels: const ['Allergic to', 'Reaction'],
                hints: const ['Penicillin', 'Rash'],
                flex: const [3, 2],
                addLabel: 'Add allergy',
                blank: const ['', ''],
              ),
            ],
          ),
          CruFormSection(
            title: 'Habits',
            children: [
              CruFieldFrame(
                label: 'Tobacco',
                child: DentalChipWrap<String>(
                  options: _tobacco.keys.toList(),
                  label: (k) => _tobacco[k]!,
                  isSelected: (k) => k == _tobaccoUse,
                  onTap: (k) {
                    setState(() => _tobaccoUse = k);
                    _edited();
                  },
                ),
              ),
              if (smoker)
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Pack-years',
                      optional: true,
                      controller: _packYears,
                      hint: '10',
                      tabular: true,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _edited(),
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
              CruFieldFrame(
                label: 'Areca nut (supari, gutka)',
                child: DentalChipWrap<bool>(
                  options: const [false, true],
                  label: (v) => v ? 'Yes' : 'No',
                  isSelected: (v) => v == _areca,
                  onTap: (v) {
                    setState(() => _areca = v);
                    _edited();
                  },
                ),
              ),
              CruFieldFrame(
                label: 'Alcohol',
                child: DentalChipWrap<String>(
                  options: _alcohol.keys.toList(),
                  label: (k) => _alcohol[k]!,
                  isSelected: (k) => k == _alcoholUse,
                  onTap: (k) {
                    setState(() => _alcoholUse = k);
                    _edited();
                  },
                ),
              ),
              if (highRisk)
                Text(
                  'High-risk habits: screen for oral potentially malignant '
                  'disorders.',
                  style: CruType.subhead.w500.tint(c.amberText),
                ),
            ],
          ),
          CruFormSection(
            title: 'Chief complaint',
            children: [
              CruTextField(
                label: 'Complaint',
                optional: true,
                controller: _complaint,
                maxLines: 2,
                hint: 'Burning sensation on the tongue',
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _edited(),
              ),
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'For how long',
                    optional: true,
                    controller: _duration,
                    hint: '3 months',
                    onChanged: (_) => _edited(),
                  ),
                  const SizedBox.shrink(),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
