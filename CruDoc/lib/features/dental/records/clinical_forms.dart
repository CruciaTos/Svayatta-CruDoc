import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// ================================================================ pain

const _painSites = [
  'Right TMJ',
  'Left TMJ',
  'Jaw muscles',
  'Tooth',
  'Temple / head',
  'Face',
  'Neck',
];

/// Pain scores over time (NRS 0–10 or VAS 0–100 mm) with the TMD pain
/// screener.
Future<void> showPainDialog(BuildContext context, Patient patient) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PainDialog(patient: patient),
    );

class _PainDialog extends ConsumerStatefulWidget {
  const _PainDialog({required this.patient});

  final Patient patient;

  @override
  ConsumerState<_PainDialog> createState() => _PainDialogState();
}

class _PainDialogState extends ConsumerState<_PainDialog> {
  String _scale = 'NRS';
  double _score = 0;
  final Set<String> _sites = {};
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Score out of 10 whatever the scale.
  static double _of10(DentalRecord r) => r.str('scale') == 'VAS'
      ? (r.number('score') ?? 0) / 10
      : (r.number('score') ?? 0);

  Future<void> _save() async {
    await saveDentalRecord(
      ref,
      DentalRecord.create(widget.patient.id, RecKind.pain, {
        'scale': _scale,
        'score': _score,
        'sites': _sites.toList(),
        'note': _note.text.trim(),
      }),
    );
    setState(() {
      _score = 0;
      _sites.clear();
      _note.clear();
    });
    if (mounted) recToast(context, 'Pain score saved');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final scores =
        ref
            .watch(
              patientRecordsProvider((
                patientId: widget.patient.id,
                kind: RecKind.pain,
              )),
            )
            .value ??
        const <DentalRecord>[];
    final tmd =
        ref
            .watch(
              patientRecordsProvider((
                patientId: widget.patient.id,
                kind: RecKind.tmd,
              )),
            )
            .value ??
        const <DentalRecord>[];
    final chrono = [...scores]
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final max = _scale == 'VAS' ? 100.0 : 10.0;

    return DentalPanelDialog(
      title: 'Pain and TMD',
      subtitle: widget.patient.fullName,
      leading: const CruIconTile(icon: RecIcons.pain, tone: CruTileTone.accent),
      width: CruSize.formDialog,
      body: Padding(
        padding: const EdgeInsets.all(CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Trend (out of 10)',
              style: CruType.subhead.w600.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s8),
            SizedBox(
              height: 90,
              child: chrono.length < 2
                  ? Center(
                      child: Text(
                        chrono.isEmpty
                            ? 'No scores yet.'
                            : 'Two scores make a trend.',
                        style: CruType.caption.tint(c.label3),
                      ),
                    )
                  : CustomPaint(
                      painter: _ScorePainter([
                        for (final r in chrono) _of10(r),
                      ], c),
                      size: Size.infinite,
                    ),
            ),
            const SizedBox(height: CruSpace.s16),
            Row(
              children: [
                Text('New score', style: CruType.subhead.w600.tint(c.label)),
                const Spacer(),
                CruSegmentedControl<String>(
                  semanticLabel: 'Scale',
                  segments: const [
                    CruSegment('NRS', 'NRS 0–10'),
                    CruSegment('VAS', 'VAS 0–100 mm'),
                  ],
                  selected: _scale,
                  onChanged: (s) => setState(() {
                    _score = s == 'VAS' ? _score * 10 : _score / 10;
                    _scale = s;
                  }),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _score.clamp(0, max),
                    max: max,
                    divisions: max.toInt(),
                    activeColor: c.accent,
                    label: _score.toStringAsFixed(0),
                    onChanged: (v) => setState(() => _score = v),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${_score.toStringAsFixed(0)}${_scale == 'VAS' ? ' mm' : ''}',
                    textAlign: TextAlign.right,
                    style: CruType.headline.tabular.tint(c.label),
                  ),
                ),
              ],
            ),
            DentalChipWrap<String>(
              options: _painSites,
              label: (s) => s,
              isSelected: _sites.contains,
              onTap: (s) => setState(
                () => _sites.contains(s) ? _sites.remove(s) : _sites.add(s),
              ),
            ),
            const SizedBox(height: CruSpace.s8),
            CruTextField(label: 'Note', optional: true, controller: _note),
            const SizedBox(height: CruSpace.s8),
            Align(
              alignment: Alignment.centerRight,
              child: CruButton(label: 'Save score', onPressed: _save),
            ),
            const SizedBox(height: CruSpace.s16),
            if (scores.isNotEmpty) ...[
              const DentalGroupLabel('Scores'),
              for (final r in scores.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s12,
                    vertical: CruSpace.s4,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          DentalFormat.date(r.recordedAt),
                          style: CruType.subhead.tabular.tint(c.label2),
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text(
                          '${(r.number('score') ?? 0).toStringAsFixed(0)}${r.str('scale') == 'VAS' ? ' mm VAS' : '/10'}',
                          style: CruType.subhead.w600.tabular.tint(c.label),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          [
                            if (r.data['sites'] is List)
                              (r.data['sites'] as List).join(', '),
                            if (r.str('note').isNotEmpty) r.str('note'),
                          ].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.caption.tint(c.label2),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: CruSpace.s8),
            const DentalGroupLabel('TMD pain screener'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tmd.isEmpty
                          ? 'Six quick questions (DC/TMD). 3 or more points means a full TMD exam is worth doing.'
                          : 'Last: ${tmd.first.integer('score')}/7 on ${DentalFormat.date(tmd.first.recordedAt)} · '
                                '${(tmd.first.integer('score') ?? 0) >= 3 ? 'positive' : 'negative'}',
                      style: CruType.subhead.tint(c.label2),
                    ),
                  ),
                  CruButton(
                    label: 'Take screener',
                    kind: CruButtonKind.secondary,
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _TmdScreener(patient: widget.patient),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScorePainter extends CustomPainter {
  _ScorePainter(this.values, this.c);

  final List<double> values;
  final CruColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = c.hairline;
    for (final v in [0, 5, 10]) {
      final y = size.height * (1 - v / 10);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final n = values.length;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? size.width / 2 : i * size.width / (n - 1);
      final y = size.height * (1 - math.min(values[i], 10) / 10);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = c.label);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = c.label
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ScorePainter old) => old.values != values;
}

/// The six-item TMD pain screener (DC/TMD), scored 0–7.
class _TmdScreener extends ConsumerStatefulWidget {
  const _TmdScreener({required this.patient});

  final Patient patient;

  @override
  ConsumerState<_TmdScreener> createState() => _TmdScreenerState();
}

class _TmdScreenerState extends ConsumerState<_TmdScreener> {
  int? _duration;
  final List<bool?> _yes = List.filled(5, null);

  static const _questions = [
    'Pain or stiffness in the jaw on waking, in the last 30 days',
    'Chewing hard or tough food changed the jaw or temple pain',
    'Opening the mouth or moving the jaw forward or sideways changed it',
    'Jaw habits (clenching, grinding, gum chewing) changed it',
    'Talking, kissing or yawning changed it',
  ];

  int get _score => (_duration ?? 0) + _yes.where((y) => y == true).length;
  bool get _complete => _duration != null && !_yes.contains(null);

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DentalPanelDialog(
      title: 'TMD pain screener',
      subtitle: '${widget.patient.fullName} · last 30 days',
      width: CruSize.formDialog,
      body: Padding(
        padding: const EdgeInsets.all(CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'How long did any jaw or temple pain last?',
              style: CruType.subhead.w600.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s6),
            DentalChipWrap<int>(
              options: const [0, 1, 2],
              label: (v) =>
                  const ['No pain', 'Comes and goes', 'Always there'][v],
              isSelected: (v) => v == _duration,
              onTap: (v) => setState(() => _duration = v),
            ),
            for (var i = 0; i < _questions.length; i++) ...[
              const SizedBox(height: CruSpace.s14),
              Text(_questions[i], style: CruType.subhead.w600.tint(c.label)),
              const SizedBox(height: CruSpace.s6),
              DentalChipWrap<bool>(
                options: const [false, true],
                label: (v) => v ? 'Yes' : 'No',
                isSelected: (v) => _yes[i] == v,
                onTap: (v) => setState(() => _yes[i] = v),
              ),
            ],
            const SizedBox(height: CruSpace.s16),
            Text(
              _complete
                  ? 'Score $_score/7 · ${_score >= 3 ? 'positive: examine with the DC/TMD protocol' : 'negative'}'
                  : 'Answer every question to score.',
              style: CruType.subhead.w600.tabular.tint(
                _complete && _score >= 3 ? c.amberText : c.label2,
              ),
            ),
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          CruButton(
            label: 'Save',
            onPressed: !_complete
                ? null
                : () async {
                    await saveDentalRecord(
                      ref,
                      DentalRecord.create(widget.patient.id, RecKind.tmd, {
                        'score': _score,
                        'duration': _duration,
                        'answers': _yes,
                      }),
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
          ),
        ],
      ),
    );
  }
}

// ================================================================ Frankl

const _frankl = [
  (
    '1',
    'Definitely negative (– –)',
    'Refuses treatment, cries forcefully, fearful',
  ),
  ('2', 'Negative (–)', 'Reluctant, uncooperative, some negative attitude'),
  (
    '3',
    'Positive (+)',
    'Accepts treatment, cautious at times, follows directions',
  ),
  (
    '4',
    'Definitely positive (+ +)',
    'Good rapport, interested, enjoys the visit',
  ),
];

String franklLabel(int? rating) =>
    rating == null || rating < 1 || rating > 4 ? '' : _frankl[rating - 1].$2;

/// A child's behaviour at each visit on the Frankl scale.
Future<void> showFranklDialog(BuildContext context, Patient patient) =>
    showDialog<void>(
      context: context,
      builder: (_) => _FranklDialog(patient: patient),
    );

class _FranklDialog extends ConsumerStatefulWidget {
  const _FranklDialog({required this.patient});

  final Patient patient;

  @override
  ConsumerState<_FranklDialog> createState() => _FranklDialogState();
}

class _FranklDialogState extends ConsumerState<_FranklDialog> {
  int? _rating;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final history =
        ref
            .watch(
              patientRecordsProvider((
                patientId: widget.patient.id,
                kind: RecKind.frankl,
              )),
            )
            .value ??
        const <DentalRecord>[];
    return DentalPanelDialog(
      title: 'Behaviour (Frankl scale)',
      subtitle: widget.patient.fullName,
      leading: const CruIconTile(
        icon: RecIcons.frankl,
        tone: CruTileTone.accent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (v, label, detail) in _frankl)
              DentalListRow(
                semanticLabel: label,
                minHeight: 48,
                onTap: () => setState(() => _rating = int.parse(v)),
                child: Row(
                  children: [
                    Icon(
                      _rating == int.parse(v)
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: _rating == int.parse(v) ? c.label : c.label3,
                    ),
                    const SizedBox(width: CruSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: CruType.callout.tint(c.label)),
                          Text(detail, style: CruType.caption.tint(c.label2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: CruSpace.s8),
            CruTextField(
              label: 'Note',
              optional: true,
              controller: _note,
              hint: 'Tell-show-do worked well',
            ),
            if (history.isNotEmpty) ...[
              const DentalGroupLabel('Earlier visits'),
              for (final r in history.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s12,
                    vertical: CruSpace.s4,
                  ),
                  child: Text(
                    '${DentalFormat.date(r.recordedAt)} · ${franklLabel(r.integer('rating'))}'
                    '${r.str('note').isEmpty ? '' : ' · ${r.str('note')}'}',
                    style: CruType.subhead.tabular.tint(c.label2),
                  ),
                ),
            ],
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          CruButton(
            label: 'Save for today',
            onPressed: _rating == null
                ? null
                : () async {
                    await saveDentalRecord(
                      ref,
                      DentalRecord.create(widget.patient.id, RecKind.frankl, {
                        'rating': _rating,
                        'note': _note.text.trim(),
                      }),
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
          ),
        ],
      ),
    );
  }
}

// ================================================================ checklist

/// WHO surgical safety checklist, adapted for dental surgery.
const surgicalChecklist = <(String, List<String>)>[
  (
    'Sign in · before anaesthesia',
    [
      'Identity, procedure and site confirmed with the patient',
      'Consent signed',
      'Site marked or confirmed on the chart and X-ray',
      'Allergies checked',
      'Medical history and medicines reviewed (blood thinners, bisphosphonates)',
      'Emergency kit and oxygen checked',
    ],
  ),
  (
    'Time out · before the first incision',
    [
      'Team introduced by name and role',
      'Patient, tooth or site and procedure confirmed aloud',
      'Imaging displayed',
      'Expected critical steps, duration and blood loss discussed',
      'Antibiotic prophylaxis given if indicated',
      'Instruments sterile (indicator checked)',
    ],
  ),
  (
    'Sign out · before the patient leaves',
    [
      'Procedure recorded',
      'Swab, needle and instrument counts correct',
      'Specimen labelled (if any)',
      'Post-op instructions given',
      'Follow-up booked',
    ],
  ),
];

/// Surgical safety checklists for a patient.
Future<void> showChecklistDialog(BuildContext context, Patient patient) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ChecklistDialog(patient: patient),
    );

class _ChecklistDialog extends ConsumerStatefulWidget {
  const _ChecklistDialog({required this.patient});

  final Patient patient;

  @override
  ConsumerState<_ChecklistDialog> createState() => _ChecklistDialogState();
}

class _ChecklistDialogState extends ConsumerState<_ChecklistDialog> {
  final _procedure = TextEditingController();
  final Set<String> _checked = {};
  DentalRecord? _editing;

  int get _total => surgicalChecklist.fold(0, (n, s) => n + s.$2.length);

  @override
  void dispose() {
    _procedure.dispose();
    super.dispose();
  }

  void _open(DentalRecord? r) => setState(() {
    _editing = r;
    _procedure.text = r?.str('procedure') ?? '';
    _checked
      ..clear()
      ..addAll(
        r?.data['checked'] is List
            ? (r!.data['checked'] as List).map((e) => '$e')
            : const <String>[],
      );
  });

  Future<void> _save() async {
    final data = {
      'procedure': _procedure.text.trim(),
      'checked': _checked.toList(),
      'complete': _checked.length == _total,
      'by': ref.read(doctorIdentityProvider).fullName ?? '',
    };
    final e = _editing;
    final r = e == null
        ? DentalRecord.create(widget.patient.id, RecKind.checklist, data)
        : e.copyWith(data: data);
    await saveDentalRecord(ref, r);
    setState(() => _editing = r);
    if (mounted) {
      recToast(
        context,
        _checked.length == _total ? 'Checklist complete' : 'Checklist saved',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final history =
        ref
            .watch(
              patientRecordsProvider((
                patientId: widget.patient.id,
                kind: RecKind.checklist,
              )),
            )
            .value ??
        const <DentalRecord>[];
    return DentalPanelDialog(
      title: 'Surgical safety checklist',
      subtitle: '${widget.patient.fullName} · WHO, adapted for dental surgery',
      leading: const CruIconTile(
        icon: RecIcons.checklist,
        tone: CruTileTone.accent,
      ),
      width: CruSize.formDialog,
      body: Padding(
        padding: const EdgeInsets.all(CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (history.isNotEmpty) ...[
              Wrap(
                spacing: CruSpace.s8,
                runSpacing: CruSpace.s8,
                children: [
                  DentalChoiceChip(
                    label: 'New checklist',
                    selected: _editing == null,
                    onTap: () => _open(null),
                  ),
                  for (final r in history.take(6))
                    DentalChoiceChip(
                      label:
                          '${DentalFormat.shortDate(r.recordedAt)} · ${r.str('procedure').isEmpty ? 'Surgery' : r.str('procedure')}'
                          '${r.data['complete'] == true ? '' : ' (open)'}',
                      selected: _editing?.id == r.id,
                      onTap: () => _open(r),
                    ),
                ],
              ),
              const SizedBox(height: CruSpace.s12),
            ],
            CruTextField(
              label: 'Procedure and site',
              controller: _procedure,
              hint: 'Surgical extraction of 38',
            ),
            for (final (title, items) in surgicalChecklist) ...[
              DentalGroupLabel(
                title,
                trailing:
                    '${items.where(_checked.contains).length}/${items.length}',
              ),
              for (final item in items)
                CheckboxListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s8,
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: c.label,
                  value: _checked.contains(item),
                  onChanged: (v) => setState(
                    () =>
                        v == true ? _checked.add(item) : _checked.remove(item),
                  ),
                  title: Text(item, style: CruType.subhead.tint(c.label)),
                ),
            ],
          ],
        ),
      ),
      footer: Row(
        children: [
          Text(
            '${_checked.length} of $_total checked',
            style: CruType.subhead.tabular.tint(
              _checked.length == _total ? c.greenText : c.label2,
            ),
          ),
          const Spacer(),
          CruButton(label: 'Save', onPressed: _save),
        ],
      ),
    );
  }
}
