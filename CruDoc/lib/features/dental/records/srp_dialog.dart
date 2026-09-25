import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// Root planing (SRP) by quadrant: one `srp` record per course of therapy.
//
// { "quadrants": { "UR": {"status": "planned" | "done", "date": ms,
//                         "anaesthesia": "…", "notes": ""}, "UL": …, … },
//   "reevaluationDue": ms, "reevaluatedExamId": "", "recallId": "" }

/// Re-evaluate six weeks after the last quadrant is done.
const _reevaluateAfter = Duration(days: 42);

/// Quadrants as the dentist faces the patient: the patient's right is on
/// the left, so UR sits top-left.
const _grid = [
  ['UR', 'UL'],
  ['LR', 'LL'],
];

const _quadrantName = {
  'UR': 'Upper right',
  'UL': 'Upper left',
  'LL': 'Lower left',
  'LR': 'Lower right',
};

/// First and last FDI tooth of each quadrant, midline last.
const _quadrantTeeth = {
  'UR': ('18', '11'),
  'UL': ('21', '28'),
  'LL': ('31', '38'),
  'LR': ('48', '41'),
};

Map<String, dynamic> _quadrant(DentalRecord? r, String q) {
  final all = r?.data['quadrants'];
  final one = all is Map ? all[q] : null;
  return one is Map ? Map<String, dynamic>.from(one) : const {};
}

String _status(DentalRecord? r, String q) =>
    _quadrant(r, q)['status'] as String? ?? '';

DateTime? _doneOn(Map<String, dynamic> q) => q['date'] is int
    ? DateTime.fromMillisecondsSinceEpoch(q['date'] as int)
    : null;

/// Quadrants planned (done ones included) and done in a course.
({int planned, int done}) _progress(DentalRecord? r) {
  var planned = 0, done = 0;
  for (final q in _quadrantName.keys) {
    final s = _status(r, q);
    if (s == 'planned' || s == 'done') planned++;
    if (s == 'done') done++;
  }
  return (planned: planned, done: done);
}

/// What the Clinical records card says about root planing: "2 of 4
/// quadrants done" while the course is running, then "Re-evaluation due
/// 12 Oct". [courses] is newest first.
({String text, bool warn}) srpCardLine(List<DentalRecord> courses) {
  final course = courses.firstOrNull;
  final p = _progress(course);
  if (course == null || p.planned == 0) {
    return (text: 'None planned', warn: false);
  }
  if (p.done < p.planned) {
    return (
      text: '${p.done} of ${p.planned} quadrants done',
      warn: false,
    );
  }
  final due = course.date('reevaluationDue');
  if (due == null) return (text: 'All quadrants done', warn: false);
  return (
    text: 'Re-evaluation due ${DentalFormat.shortDate(due)}',
    warn: due.isBefore(DateTime.now()),
  );
}

/// The patient's root planing: four quadrant tiles laid out like the
/// mouth. Tap a tile to plan it or record it done; once every planned
/// quadrant is done, set the re-evaluation recall.
Future<void> showSrpDialog(BuildContext context, Patient patient) =>
    showDialog<void>(
      context: context,
      builder: (_) => _SrpDialog(patient: patient),
    );

class _SrpDialog extends ConsumerStatefulWidget {
  const _SrpDialog({required this.patient});

  final Patient patient;

  @override
  ConsumerState<_SrpDialog> createState() => _SrpDialogState();
}

class _SrpDialogState extends ConsumerState<_SrpDialog> {
  /// A course started here but not saved yet (nothing planned so far).
  bool _fresh = false;

  RecKey get _key => (patientId: widget.patient.id, kind: RecKind.srp);

  Future<void> _editQuadrant(DentalRecord? course, String q) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _QuadrantDialog(
        quadrant: q,
        current: _quadrant(course, q),
      ),
    );
    if (result == null) return;

    final quadrants = <String, dynamic>{
      for (final k in _quadrantName.keys)
        if (_quadrant(course, k).isNotEmpty) k: _quadrant(course, k),
    };
    if ((result['status'] as String? ?? '').isEmpty) {
      quadrants.remove(q);
    } else {
      quadrants[q] = result;
    }

    final data = <String, dynamic>{
      ...?course?.data,
      'quadrants': quadrants,
      'reevaluatedExamId': course?.str('reevaluatedExamId') ?? '',
    };

    // Every planned quadrant done: re-evaluate six weeks after the last.
    final draft = course == null
        ? DentalRecord.create(widget.patient.id, RecKind.srp, data)
        : course.copyWith(data: data);
    final p = _progress(draft);
    if (p.planned > 0 && p.done == p.planned) {
      final last = quadrants.values
          .map((v) => _doneOn(Map<String, dynamic>.from(v as Map)))
          .whereType<DateTime>()
          .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      data['reevaluationDue'] =
          (last ?? DateTime.now()).add(_reevaluateAfter).millisecondsSinceEpoch;
    } else {
      data
        ..remove('reevaluationDue')
        ..remove('recallId');
    }

    await saveDentalRecord(ref, draft.copyWith(data: data));
    if (mounted) setState(() => _fresh = false);
  }

  Future<void> _setRecall(DentalRecord course, DateTime due) async {
    final recall = DentalRecord.create(
      widget.patient.id,
      RecKind.recall,
      {
        'patientName': widget.patient.fullName,
        'reason': 'Perio re-evaluation',
        'status': RecallStatus.pending.name,
        'source': 'srp',
        'notes': '',
      },
      at: due,
    );
    await saveDentalRecord(ref, recall);
    await saveDentalRecord(
      ref,
      course.copyWith(data: {...course.data, 'recallId': recall.id}),
    );
    if (mounted) {
      recToast(context, 'Recall set for ${DentalFormat.date(due)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final courses =
        ref.watch(patientRecordsProvider(_key)).value ??
        const <DentalRecord>[];
    final course = _fresh ? null : courses.firstOrNull;
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final p = _progress(course);
    final complete = p.planned > 0 && p.done == p.planned;
    final due = course?.date('reevaluationDue');
    final recallSet = (course?.str('recallId') ?? '').isNotEmpty;

    return DentalPanelDialog(
      title: 'Root planing',
      subtitle: [
        widget.patient.fullName,
        if (p.planned > 0) '${p.done} of ${p.planned} quadrants done',
      ].join(' · '),
      leading: const CruIconTile(icon: RecIcons.perio, tone: CruTileTone.accent),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'As you face the patient. Tap a quadrant to plan it or record '
              'it done.',
              style: CruType.subhead.tint(c.label2),
            ),
          ),
          for (var row = 0; row < _grid.length; row++) ...[
            if (row > 0) const SizedBox(height: CruSpace.s12),
            Row(
              children: [
                for (var col = 0; col < _grid[row].length; col++) ...[
                  if (col > 0) const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: _QuadrantTile(
                      quadrant: _grid[row][col],
                      data: _quadrant(course, _grid[row][col]),
                      numbering: numbering,
                      onTap: () => _editQuadrant(course, _grid[row][col]),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (complete && due != null) ...[
            const SizedBox(height: CruSpace.s16),
            Container(
              padding: const EdgeInsets.all(CruSpace.s14),
              decoration: ShapeDecoration(
                color: c.accentTint,
                shape: cruShape(CruRadius.control),
              ),
              child: Row(
                children: [
                  CruIcon(RecIcons.recall, size: 18, color: c.accentText),
                  const SizedBox(width: CruSpace.s10),
                  Expanded(
                    child: Text(
                      'Re-evaluate on ${DentalFormat.date(due)}',
                      style: CruType.callout.w600.tint(c.accentText),
                    ),
                  ),
                  CruButton(
                    label: recallSet ? 'Recall set' : 'Set recall',
                    kind: CruButtonKind.tinted,
                    onPressed: recallSet
                        ? null
                        : () => _setRecall(course!, due),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: Text(
              courses.length > 1
                  ? '${courses.length} courses on record · showing the latest'
                  : '',
              style: CruType.caption.tint(c.label3),
            ),
          ),
          if (complete)
            CruButton(
              label: 'New course',
              icon: CruIcons.plus,
              kind: CruButtonKind.secondary,
              onPressed: () => setState(() => _fresh = true),
            ),
        ],
      ),
    );
  }
}

class _QuadrantTile extends StatelessWidget {
  const _QuadrantTile({
    required this.quadrant,
    required this.data,
    required this.numbering,
    required this.onTap,
  });

  final String quadrant;
  final Map<String, dynamic> data;
  final ToothNumbering numbering;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final status = data['status'] as String? ?? '';
    final date = _doneOn(data);
    final anaesthesia = (data['anaesthesia'] as String? ?? '').trim();
    final (from, to) = _quadrantTeeth[quadrant]!;
    final name = _quadrantName[quadrant]!;
    final (fill, fg, label) = switch (status) {
      'done' => (c.greenTint, c.greenText, 'Done'),
      'planned' => (c.amberTint, c.amberText, 'Planned'),
      _ => (c.inset, c.label2, 'Not planned'),
    };
    final detail = [
      if (status == 'done' && date != null) DentalFormat.date(date),
      if (anaesthesia.isNotEmpty) anaesthesia,
    ].join(' · ');

    return CruPressable(
      onTap: onTap,
      semanticLabel: '$name. $label${detail.isEmpty ? '' : '. $detail'}',
      scaleOnPress: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: 116,
        padding: const EdgeInsets.all(CruSpace.s14),
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(c.inset, c) : c.inset,
          shape: cruShape(CruRadius.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: CruType.callout.w600.tint(c.label),
                  ),
                ),
                CruPill(text: label, background: fill, foreground: fg),
              ],
            ),
            const SizedBox(height: CruSpace.s2),
            Text(
              'Teeth ${toothLabel(from, numbering)}–${toothLabel(to, numbering)}',
              style: CruType.caption.tabular.tint(c.label3),
            ),
            const Spacer(),
            Text(
              detail.isEmpty
                  ? (status.isEmpty ? 'Tap to plan' : 'Tap to record it done')
                  : detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.subhead.tabular.tint(
                detail.isEmpty ? c.label3 : c.label2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One quadrant: not planned, planned or done (with the date,
/// anaesthesia and notes). Pops the quadrant's new data; an empty status
/// removes it from the course.
class _QuadrantDialog extends StatefulWidget {
  const _QuadrantDialog({required this.quadrant, required this.current});

  final String quadrant;
  final Map<String, dynamic> current;

  @override
  State<_QuadrantDialog> createState() => _QuadrantDialogState();
}

class _QuadrantDialogState extends State<_QuadrantDialog> {
  late String _status = widget.current['status'] as String? ?? 'planned';
  late DateTime _date = _doneOn(widget.current) ?? DateTime.now();
  late final _anaesthesia = TextEditingController(
    text: widget.current['anaesthesia'] as String? ?? '',
  );
  late final _notes = TextEditingController(
    text: widget.current['notes'] as String? ?? '',
  );

  @override
  void dispose() {
    _anaesthesia.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(<String, dynamic>{
      'status': _status,
      if (_status == 'done') 'date': _date.millisecondsSinceEpoch,
      'anaesthesia': _anaesthesia.text.trim(),
      'notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _quadrantTeeth[widget.quadrant]!;
    return CruFormDialog(
      title: _quadrantName[widget.quadrant]!,
      subtitle: 'Root planing · teeth $from–$to',
      leading: const CruIconTile(icon: RecIcons.perio, tone: CruTileTone.accent),
      submitLabel: 'Save quadrant',
      onSubmit: _save,
      width: CruSize.formDialog - 160,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruSegmentedControl<String>(
            semanticLabel: 'Status',
            segments: const [
              CruSegment('', 'Not planned'),
              CruSegment('planned', 'Planned'),
              CruSegment('done', 'Done'),
            ],
            selected: _status,
            onChanged: (s) => setState(() => _status = s),
          ),
          const SizedBox(height: CruSpace.s16),
          if (_status == 'done') ...[
            CruPickerField(
              label: 'Done on',
              icon: CruIcons.calendar,
              value: DentalFormat.date(_date),
              placeholder: 'Pick a date',
              onTap: () async {
                final d = await pickDentalDate(
                  context,
                  initial: _date,
                  last: DateTime.now(),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: CruSpace.s16),
          ],
          CruTextField(
            label: 'Anaesthesia',
            optional: true,
            controller: _anaesthesia,
            hint: 'Lidocaine 2% 1 cartridge',
          ),
          const SizedBox(height: CruSpace.s16),
          CruTextField(
            label: 'Notes',
            optional: true,
            controller: _notes,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
