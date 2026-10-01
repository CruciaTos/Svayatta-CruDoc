import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/muscle_chart/muscle_chart_view.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patient Details card for physiotherapists: the 3D muscle chart, with the
/// findings saved per patient (record kind `muscleChart`).
class MuscleChartCard extends ConsumerStatefulWidget {
  const MuscleChartCard({super.key, required this.patient});

  final Patient patient;

  @override
  ConsumerState<MuscleChartCard> createState() => _MuscleChartCardState();
}

class _MuscleChartCardState extends ConsumerState<MuscleChartCard> {
  DentalRecord? _record;
  Timer? _saveTimer;
  List<MuscleFinding>? _pending;

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_pending != null) unawaited(_save());
    super.dispose();
  }

  void _queueSave(List<MuscleFinding> all) {
    _pending = all;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _save() async {
    final all = _pending;
    if (all == null) return;
    _pending = null;
    final data = {
      'findings': [for (final f in all) f.toJson()],
    };
    final rec = _record == null
        ? DentalRecord.create(widget.patient.id, RecKind.muscleChart, data)
        : _record!.copyWith(data: data);
    _record = rec;
    await saveDentalRecord(ref, rec);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final recordsAsync = ref.watch(
      patientRecordsProvider((
        patientId: widget.patient.id,
        kind: RecKind.muscleChart,
      )),
    );
    final records = [...?recordsAsync.value]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _record ??= records.isEmpty ? null : records.first;
    final findings = [
      for (final f in (_record?.data['findings'] as List? ?? const []))
        MuscleFinding.fromJson(Map<String, dynamic>.from(f as Map)),
    ];
    final affected = findings.where((f) => f.status != 'resolved').length;

    return CruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CruRadius.control),
                ),
                child: Icon(Icons.accessibility_new_rounded, size: 18, color: c.accent),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Muscle chart', style: CruType.headline.w600.tint(c.label)),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      findings.isEmpty
                          ? 'Click a muscle to record a finding'
                          : '$affected active finding${affected == 1 ? '' : 's'} · ${findings.length} recorded',
                      style: CruType.caption.tint(c.label2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          SizedBox(
            height: 700,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CruRadius.control),
              child: recordsAsync.isLoading && _record == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : MuscleChartView(
                      findings: findings,
                      onFindingsChanged: (all) {
                        setState(() {
                          final data = {
                            'findings': [for (final f in all) f.toJson()],
                          };
                          _record = _record?.copyWith(data: data) ??
                              DentalRecord.create(widget.patient.id, RecKind.muscleChart, data);
                        });
                        _queueSave(all);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
