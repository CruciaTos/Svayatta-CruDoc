import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_assess_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Quick entry sheet for a pain and function score.
Future<void> showProgressEntrySheet(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
) async {
  final data = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _EntrySheet(),
  );
  if (data == null) return;
  await saveDentalRecord(
    ref,
    DentalRecord.create(patient.id, RecKind.physioProgress, data),
  );
}

class _EntrySheet extends StatefulWidget {
  const _EntrySheet();

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  int _pain = 0;
  int _worst = 0;
  int _function = 5;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s16,
            0,
            CruSpace.s16,
            CruSpace.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScoreRow(
                title: 'Pain now',
                low: 'No pain',
                high: 'Worst',
                value: _pain,
                onChanged: (v) => setState(() {
                  _pain = v;
                  if (_worst < v) _worst = v;
                }),
              ),
              _ScoreRow(
                title: 'Worst pain in the last week',
                low: 'No pain',
                high: 'Worst',
                value: _worst,
                onChanged: (v) => setState(() => _worst = v),
              ),
              _ScoreRow(
                title: 'Daily function',
                low: 'Cannot do',
                high: 'Normal',
                value: _function,
                onChanged: (v) => setState(() => _function = v),
              ),
              CruTextField(
                label: 'Note',
                controller: _note,
                optional: true,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: CruSpace.s16),
              CruButton(
                label: 'Save score',
                expand: true,
                onPressed: () => Navigator.of(context).pop(
                  ProgressEntry.toData(
                    pain: _pain,
                    worst: _worst < _pain ? _pain : _worst,
                    function: _function,
                    note: _note.text.trim(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.title,
    required this.low,
    required this.high,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String low;
  final String high;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: CruType.body.w600.tint(c.label)),
          const SizedBox(height: CruSpace.s8),
          Row(
            children: [
              for (var i = 0; i <= 10; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Semantics(
                      button: true,
                      selected: i == value,
                      label: '$title $i',
                      child: GestureDetector(
                        onTap: () => onChanged(i),
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: i == value ? c.accent : c.inset,
                            borderRadius: BorderRadius.circular(
                              CruRadius.control,
                            ),
                          ),
                          child: Text(
                            '$i',
                            style: CruType.caption.w600.tint(
                              i == value ? c.onAccent : c.label,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(low, style: CruType.micro.tint(c.label3)),
              Text(high, style: CruType.micro.tint(c.label3)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small trend of pain (dark) and function (grey) across entries, 0 to 10.
class ProgressTrend extends StatelessWidget {
  const ProgressTrend({super.key, required this.entries, this.height = 80});

  /// Oldest first.
  final List<ProgressEntry> entries;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              pain: [for (final e in entries) e.pain],
              function: [for (final e in entries) e.function],
              painColor: c.label,
              functionColor: c.label3,
              gridColor: c.hairline,
            ),
          ),
        ),
        const SizedBox(height: CruSpace.s4),
        Row(
          children: [
            _Dot(color: c.label),
            const SizedBox(width: CruSpace.s4),
            Text('Pain', style: CruType.micro.tint(c.label2)),
            const SizedBox(width: CruSpace.s12),
            _Dot(color: c.label3),
            const SizedBox(width: CruSpace.s4),
            Text('Function', style: CruType.micro.tint(c.label2)),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.pain,
    required this.function,
    required this.painColor,
    required this.functionColor,
    required this.gridColor,
  });

  final List<int> pain;
  final List<int> function;
  final Color painColor;
  final Color functionColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final v in [0, 5, 10]) {
      final y = pad + (size.height - 2 * pad) * (1 - v / 10);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    void line(List<int> vals, Color color) {
      if (vals.isEmpty) return;
      final pts = <Offset>[
        for (var i = 0; i < vals.length; i++)
          Offset(
            vals.length == 1
                ? size.width / 2
                : pad + (size.width - 2 * pad) * i / (vals.length - 1),
            pad + (size.height - 2 * pad) * (1 - vals[i] / 10),
          ),
      ];
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(Path()..addPolygon(pts, false), paint);
      final dot = Paint()..color = color;
      for (final p in pts) {
        canvas.drawCircle(p, 3, dot);
      }
    }

    line(pain, painColor);
    line(function, functionColor);
  }

  @override
  bool shouldRepaint(_TrendPainter o) =>
      o.pain != pain ||
      o.function != function ||
      o.painColor != painColor ||
      o.functionColor != functionColor;
}

/// Full list of scores for a patient, newest first.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patient.id,
        kind: RecKind.physioProgress,
      )),
    );
    final entries = progressEntries(recs.value ?? const <DentalRecord>[]);
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: Text(patient.fullName),
        actions: [
          CruCapsuleButton(
            label: 'Add',
            icon: CruIcons.plus,
            onPressed: () => showProgressEntrySheet(context, ref, patient),
          ),
          const SizedBox(width: CruSpace.s12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(CruSpace.s16),
        children: [
          if (entries.length > 1) ...[
            CruCard(child: ProgressTrend(entries: entries, height: 120)),
            const SizedBox(height: CruSpace.s12),
          ],
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s24),
              child: Center(
                child: Text(
                  'No scores yet.',
                  style: CruType.caption.tint(c.label3),
                ),
              ),
            ),
          for (final e in entries.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: CruSpace.s8),
              child: CruCard(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s16,
                  CruSpace.s12,
                  CruSpace.s4,
                  CruSpace.s12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DentalFormat.date(e.date),
                            style: CruType.caption.tint(c.label2),
                          ),
                          const SizedBox(height: CruSpace.s2),
                          Text(
                            'Pain ${e.pain} · Worst ${e.worst} · Function ${e.function}',
                            style: CruType.body.w600.tint(c.label),
                          ),
                          if (e.note.isNotEmpty)
                            Text(e.note, style: CruType.caption.tint(c.label2)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: c.label2,
                      ),
                      onPressed: () async {
                        final ok = await confirmDental(
                          context,
                          title: 'Delete this score?',
                          body:
                              'The score from ${DentalFormat.date(e.date)} will be removed.',
                          action: 'Delete',
                        );
                        if (ok) await deleteDentalRecord(ref, e.record);
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
