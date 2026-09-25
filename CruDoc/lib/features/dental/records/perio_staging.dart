import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _interdentalSites = [0, 2, 3, 5];
const _buccalOralSites = [1, 4];

const _complexityLabels = <String, String>{
  'verticalDefect': 'Vertical defect ≥3 mm',
  'furcationII': 'Furcation II/III',
  'ridgeDefect': 'Moderate ridge defect',
  'mastDysfunction': 'Masticatory dysfunction',
  'biteCollapse': 'Bite collapse',
  'under20Teeth': 'Fewer than 20 teeth',
};

/// What the 2017 AAP/EFP stage and grade are computed from: the exam
/// alone gives diagnosis, stage and extent; these fill in what a chart
/// can't (bone loss, age, smoking, diabetes) and the complexity flags a
/// single exam can't infer.
class PerioDxInputs {
  PerioDxInputs({
    this.boneLossPct,
    this.teethLostToPerio = 0,
    this.age,
    this.smokingPerDay = 0,
    this.diabetes = 'none',
    this.hba1c,
    Set<String>? complexity,
  }) : complexity = complexity ?? <String>{};

  int? boneLossPct;
  int teethLostToPerio;
  int? age;
  int smokingPerDay;
  String diabetes;
  double? hba1c;
  Set<String> complexity;

  factory PerioDxInputs.fromJson(Object? j) {
    if (j is! Map) return PerioDxInputs();
    final m = Map<String, dynamic>.from(j);
    return PerioDxInputs(
      boneLossPct: (m['boneLossPct'] as num?)?.toInt(),
      teethLostToPerio: (m['teethLostToPerio'] as num?)?.toInt() ?? 0,
      age: (m['age'] as num?)?.toInt(),
      smokingPerDay: (m['smokingPerDay'] as num?)?.toInt() ?? 0,
      diabetes: m['diabetes'] as String? ?? 'none',
      hba1c: (m['hba1c'] as num?)?.toDouble(),
      complexity: {
        if (m['complexity'] is List)
          for (final v in (m['complexity'] as List)) v.toString(),
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'boneLossPct': boneLossPct,
    'teethLostToPerio': teethLostToPerio,
    'age': age,
    'smokingPerDay': smokingPerDay,
    'diabetes': diabetes,
    'hba1c': hba1c,
    'complexity': complexity.toList()..sort(),
  };
}

/// The computed diagnosis, with every rule that fired (shown under
/// "Why" so the dentist can see the reasoning, not just the result).
class PerioDxComputation {
  const PerioDxComputation({
    required this.diagnosis,
    required this.stage,
    required this.extent,
    required this.grade,
    required this.reasons,
  });

  final String diagnosis;
  final int stage;
  final String? extent;
  final String grade;
  final List<String> reasons;

  Map<String, dynamic> toJson() => {
    'diagnosis': diagnosis,
    'stage': stage,
    'extent': extent,
    'grade': grade,
    'reasons': reasons,
  };
}

/// 2017 AAP/EFP classification: periodontitis vs gingivitis vs health,
/// staged I–IV, extent localized/generalized, graded A–C.
PerioDxComputation computePerioDx({
  required DentalRecord exam,
  required PerioDxInputs inputs,
}) {
  final teeth = _teethOf(exam);
  final summary = PerioSummary(teeth);
  final reasons = <String>[];

  // ---------------------------------------------------------------- diagnosis
  final interdental = _hasNonAdjacent(
    teeth,
    (t, s) =>
        _interdentalSites.contains(s) &&
        (teeth[t]!.cal(s) ?? -999) >= 2,
  );
  final buccalOral = _hasNonAdjacent(
    teeth,
    (t, s) =>
        _buccalOralSites.contains(s) &&
        (teeth[t]!.cal(s) ?? -999) >= 3 &&
        (teeth[t]!.pd[s] ?? 0) > 3,
  );

  String diagnosis;
  String? extent;

  if (interdental || buccalOral) {
    diagnosis = 'periodontitis';
    if (interdental) {
      reasons.add(
        'Periodontitis: interdental CAL ≥2 mm at ≥2 non-adjacent teeth',
      );
    }
    if (buccalOral) {
      reasons.add(
        'Periodontitis: buccal/oral CAL ≥3 mm with PD >3 mm at ≥2 teeth',
      );
    }
  } else if ((summary.bopPct ?? 0) >= 10) {
    diagnosis = 'gingivitis';
    final pct = summary.bopPct ?? 0;
    extent = pct > 30 ? 'generalized' : 'localized';
    reasons.add('Gingivitis: bleeding ${pct.toStringAsFixed(0)}% (≥10%)');
    reasons.add(
      extent == 'generalized'
          ? 'Extent generalized: bleeding >30%'
          : 'Extent localized: bleeding 10–30%',
    );
  } else {
    diagnosis = 'health';
    reasons.add('Health: no periodontitis and bleeding <10%');
  }

  // ---------------------------------------------------------------- stage
  var stage = diagnosis == 'periodontitis' ? 1 : 0;

  final worstCal = _worstInterdentalCal(teeth);
  if (worstCal != null) {
    if (worstCal >= 5) {
      stage = math.max(stage, 3);
      reasons.add('Stage III: worst interdental CAL $worstCal mm (≥5 mm)');
    } else if (worstCal >= 3) {
      stage = math.max(stage, 2);
      reasons.add('Stage II: worst interdental CAL $worstCal mm (3–4 mm)');
    } else if (worstCal >= 1) {
      stage = math.max(stage, 1);
      reasons.add('Stage I: worst interdental CAL $worstCal mm (1–2 mm)');
    }
  }

  if (inputs.boneLossPct != null) {
    final pct = inputs.boneLossPct!;
    if (pct < 15) {
      stage = math.max(stage, 1);
      reasons.add('Stage I: radiographic bone loss $pct% (<15%)');
    } else if (pct <= 33) {
      stage = math.max(stage, 2);
      reasons.add('Stage II: radiographic bone loss $pct% (15–33%)');
    } else {
      stage = math.max(stage, 3);
      reasons.add(
        'Stage III: radiographic bone loss $pct% (beyond coronal third)',
      );
    }
  }

  if (inputs.teethLostToPerio >= 5) {
    stage = 4;
    reasons.add('Stage IV: ≥5 teeth lost to periodontitis');
  } else if (inputs.teethLostToPerio >= 1) {
    stage = math.max(stage, 3);
    reasons.add(
      'Stage III: ${inputs.teethLostToPerio} teeth lost to periodontitis (1–4)',
    );
  }

  final maxPd = _maxPd(teeth);
  if (maxPd != null && maxPd >= 6) {
    stage = math.max(stage, 3);
    final where = _maxPdTooth(teeth);
    reasons.add(
      'Stage III: max PD $maxPd mm${where == null ? '' : ' at $where'}',
    );
  }

  if (inputs.complexity.contains('verticalDefect')) {
    stage = math.max(stage, 3);
    reasons.add('Stage III: vertical defect ≥3 mm');
  }
  if (inputs.complexity.contains('furcationII')) {
    stage = math.max(stage, 3);
    reasons.add('Stage III: furcation II/III');
  }
  if (inputs.complexity.contains('ridgeDefect')) {
    stage = math.max(stage, 3);
    reasons.add('Stage III: moderate ridge defect');
  }

  final maxMob = _maxMobility(teeth);
  if (maxMob != null && maxMob >= 2) {
    stage = 4;
    reasons.add('Stage IV: mobility ≥2 (secondary occlusal trauma)');
  }
  if (inputs.complexity.contains('mastDysfunction')) {
    stage = 4;
    reasons.add('Stage IV: masticatory dysfunction');
  }
  if (inputs.complexity.contains('biteCollapse')) {
    stage = 4;
    reasons.add('Stage IV: bite collapse');
  }
  if (inputs.complexity.contains('under20Teeth')) {
    stage = 4;
    reasons.add('Stage IV: fewer than 20 teeth');
  }

  if (diagnosis == 'periodontitis' && stage == 0) stage = 1;

  // ---------------------------------------------------------------- extent
  if (diagnosis == 'periodontitis') {
    final present = _presentTeeth(teeth);
    final involved = _involvedTeeth(teeth);
    final pct = present == 0 ? 0.0 : involved * 100 / present;
    extent = pct < 30 ? 'localized' : 'generalized';
    reasons.add(
      extent == 'localized'
          ? 'Extent localized: $involved of $present teeth involved (<30%)'
          : 'Extent generalized: $involved of $present teeth involved (≥30%)',
    );
  }

  // ---------------------------------------------------------------- grade
  var grade = 'B';

  if (inputs.boneLossPct != null && inputs.age != null && inputs.age! > 0) {
    final ratio = inputs.boneLossPct! / inputs.age!;
    if (ratio < 0.25) {
      grade = 'A';
      reasons.add('Grade A: bone loss/age ${ratio.toStringAsFixed(2)} <0.25');
    } else if (ratio > 1.0) {
      grade = 'C';
      reasons.add('Grade C: bone loss/age ${ratio.toStringAsFixed(2)} >1.0');
    } else {
      reasons.add(
        'Grade B: bone loss/age ${ratio.toStringAsFixed(2)} (0.25–1.0)',
      );
    }
  }

  if (inputs.smokingPerDay >= 10) {
    grade = _maxGrade(grade, 'C');
    reasons.add('Grade C: smoking ≥10/day');
  } else if (inputs.smokingPerDay > 0) {
    grade = _maxGrade(grade, 'B');
    reasons.add('Grade B: smoking <10/day');
  }

  if (inputs.diabetes != 'none') {
    final h = inputs.hba1c;
    if (h != null) {
      if (h >= 7) {
        grade = _maxGrade(grade, 'C');
        reasons.add('Grade C: HbA1c ${h.toStringAsFixed(1)}% (≥7%)');
      } else {
        grade = _maxGrade(grade, 'B');
        reasons.add('Grade B: HbA1c ${h.toStringAsFixed(1)}% (<7%)');
      }
    } else if (inputs.diabetes == 'uncontrolled') {
      grade = _maxGrade(grade, 'C');
      reasons.add('Grade C: uncontrolled diabetes');
    } else {
      grade = _maxGrade(grade, 'B');
      reasons.add('Grade B: controlled diabetes');
    }
  }

  return PerioDxComputation(
    diagnosis: diagnosis,
    stage: stage,
    extent: extent,
    grade: grade,
    reasons: reasons,
  );
}

/// "Periodontitis · Stage III · Generalized · Grade B", for cards, lists
/// and the perio chart header.
String perioDxSummary(DentalRecord r) {
  final dx = r.str('diagnosis');
  final stage = r.integer('stage');
  final extent = r.str('extent');
  final grade = r.str('grade');

  final parts = <String>[];
  if (dx.isNotEmpty) parts.add(_title(dx));
  if (stage != null && stage > 0) parts.add('Stage ${_roman(stage)}');
  if (extent.isNotEmpty) parts.add(_extentLabel(extent));
  if (grade.isNotEmpty) parts.add('Grade $grade');
  return parts.join(' · ');
}

/// "Stage III · Grade B" for list rows, or "Gingivitis" / "Health" when
/// there's no periodontitis to stage.
String perioStageGrade(DentalRecord r) {
  final dx = r.str('diagnosis');
  if (dx != 'periodontitis') return _title(dx);
  final stage = r.integer('stage');
  final grade = r.str('grade');
  return [
    if (stage != null && stage > 0) 'Stage ${_roman(stage)}',
    if (grade.isNotEmpty) 'Grade $grade',
  ].join(' · ');
}

/// The patient's current age, for the bone-loss/age grade ratio.
int? ageFromPatient(Patient p) => p.age;

// ------------------------------------------------------------------ UI panel

/// Two columns: the inputs a single exam can't supply (bone loss, age,
/// smoking, diabetes, complexity) on the left, the computed result —
/// editable, with every rule that fired — on the right.
class PerioStagingPanel extends StatefulWidget {
  const PerioStagingPanel({
    super.key,
    required this.exam,
    required this.patient,
    required this.onSave,
    this.existing,
  });

  final DentalRecord exam;
  final DentalRecord? existing;
  final Patient patient;
  final Future<void> Function(DentalRecord) onSave;

  @override
  State<PerioStagingPanel> createState() => _PerioStagingPanelState();
}

class _PerioStagingPanelState extends State<PerioStagingPanel> {
  late PerioDxInputs _inputs;
  late PerioDxComputation _auto;
  late String _diagnosis;
  late int _stage;
  String? _extent;
  late String _grade;
  bool _overridden = false;

  final _boneLoss = TextEditingController();
  final _teethLost = TextEditingController();
  final _age = TextEditingController();
  final _smoking = TextEditingController();
  final _hba1c = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();

    final ex = widget.existing;
    _inputs = ex == null
        ? PerioDxInputs(age: ageFromPatient(widget.patient), diabetes: 'none')
        : PerioDxInputs.fromJson(ex.data['inputs']);

    _inputs.age ??= ageFromPatient(widget.patient);
    _notes.text = ex?.str('notes') ?? '';
    _writeControllers();

    _auto = computePerioDx(exam: widget.exam, inputs: _inputs);

    if (ex != null && ex.data['overridden'] == true) {
      _diagnosis =
          ex.str('diagnosis').isEmpty ? _auto.diagnosis : ex.str('diagnosis');
      _stage = ex.integer('stage') ?? _auto.stage;
      _extent = ex.str('extent').isEmpty ? _auto.extent : ex.str('extent');
      _grade = ex.str('grade').isEmpty ? _auto.grade : ex.str('grade');
      _overridden = true;
    } else {
      _applyAuto();
    }
  }

  void _writeControllers() {
    _boneLoss.text = _inputs.boneLossPct?.toString() ?? '';
    _teethLost.text =
        _inputs.teethLostToPerio == 0 ? '' : '${_inputs.teethLostToPerio}';
    _age.text = _inputs.age?.toString() ?? '';
    _smoking.text =
        _inputs.smokingPerDay == 0 ? '' : '${_inputs.smokingPerDay}';
    _hba1c.text = _inputs.hba1c?.toString() ?? '';
  }

  void _applyAuto() {
    _diagnosis = _auto.diagnosis;
    _stage = _auto.stage;
    _extent = _auto.extent;
    _grade = _auto.grade;
  }

  @override
  void dispose() {
    _boneLoss.dispose();
    _teethLost.dispose();
    _age.dispose();
    _smoking.dispose();
    _hba1c.dispose();
    _notes.dispose();
    super.dispose();
  }

  PerioDxInputs _readInputs() {
    return PerioDxInputs(
      boneLossPct: int.tryParse(_boneLoss.text.trim()),
      teethLostToPerio: int.tryParse(_teethLost.text.trim()) ?? 0,
      age: int.tryParse(_age.text.trim()),
      smokingPerDay: int.tryParse(_smoking.text.trim()) ?? 0,
      diabetes: _inputs.diabetes,
      hba1c: double.tryParse(_hba1c.text.trim()),
      complexity: {..._inputs.complexity},
    );
  }

  void _recompute() {
    final next = _readInputs();
    final auto = computePerioDx(exam: widget.exam, inputs: next);
    setState(() {
      _inputs = next;
      _auto = auto;
      if (!_overridden) _applyAuto();
    });
  }

  Future<void> _save() async {
    final inputs = _readInputs();
    final auto = computePerioDx(exam: widget.exam, inputs: inputs);
    final overridden = _diagnosis != auto.diagnosis ||
        _stage != auto.stage ||
        _extent != auto.extent ||
        _grade != auto.grade;

    final data = {
      'examId': widget.exam.id,
      'diagnosis': _diagnosis,
      'stage': _stage,
      'extent': _extent,
      'grade': _grade,
      'inputs': inputs.toJson(),
      'auto': auto.toJson(),
      'overridden': overridden,
      'notes': _notes.text.trim(),
    };

    final r = widget.existing == null
        ? DentalRecord.create(
            widget.exam.patientId,
            RecKind.perioDx,
            data,
            at: widget.exam.recordedAt,
          )
        : widget.existing!.copyWith(
            data: data,
            recordedAt: widget.exam.recordedAt,
          );

    await widget.onSave(r);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 980),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: _inputsColumn(context),
            ),
          ),
          const SizedBox(width: CruSpace.s20),
          Expanded(
            child: SingleChildScrollView(
              child: _resultColumn(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputsColumn(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Inputs', style: CruType.headline.tint(c.label)),
        const SizedBox(height: CruSpace.s12),
        CruTextField(
          label: 'Bone loss %',
          optional: true,
          controller: _boneLoss,
          keyboardType: TextInputType.number,
          onChanged: (_) => _recompute(),
        ),
        const SizedBox(height: CruSpace.s8),
        CruTextField(
          label: 'Teeth lost to periodontitis',
          optional: true,
          controller: _teethLost,
          keyboardType: TextInputType.number,
          onChanged: (_) => _recompute(),
        ),
        const SizedBox(height: CruSpace.s8),
        CruTextField(
          label: 'Age',
          optional: true,
          controller: _age,
          keyboardType: TextInputType.number,
          onChanged: (_) => _recompute(),
        ),
        const SizedBox(height: CruSpace.s8),
        CruTextField(
          label: 'Smoking per day',
          optional: true,
          controller: _smoking,
          keyboardType: TextInputType.number,
          onChanged: (_) => _recompute(),
        ),
        const SizedBox(height: CruSpace.s16),
        Text('Diabetes', style: CruType.subhead.w600.tint(c.label)),
        const SizedBox(height: CruSpace.s6),
        DentalChipWrap<String>(
          options: const ['none', 'controlled', 'uncontrolled'],
          label: (v) => switch (v) {
            'controlled' => 'Controlled',
            'uncontrolled' => 'Uncontrolled',
            _ => 'No diabetes',
          },
          isSelected: (v) => _inputs.diabetes == v,
          onTap: (v) {
            setState(() => _inputs.diabetes = v);
            _recompute();
          },
        ),
        if (_inputs.diabetes != 'none') ...[
          const SizedBox(height: CruSpace.s8),
          CruTextField(
            label: 'HbA1c %',
            optional: true,
            controller: _hba1c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _recompute(),
          ),
        ],
        const SizedBox(height: CruSpace.s16),
        Text('Complexity', style: CruType.subhead.w600.tint(c.label)),
        const SizedBox(height: CruSpace.s6),
        DentalChipWrap<String>(
          options: _complexityLabels.keys.toList(),
          label: (k) => _complexityLabels[k]!,
          isSelected: (k) => _inputs.complexity.contains(k),
          onTap: (k) {
            setState(() {
              if (_inputs.complexity.contains(k)) {
                _inputs.complexity.remove(k);
              } else {
                _inputs.complexity.add(k);
              }
            });
            _recompute();
          },
        ),
      ],
    );
  }

  Widget _resultColumn(BuildContext context) {
    final c = context.cru;
    final resultText = [
      _title(_diagnosis),
      if (_stage > 0) 'Stage ${_roman(_stage)}',
      if (_extent != null) _extentLabel(_extent),
      'Grade $_grade',
    ].join(' · ');

    void overrideWith(void Function() apply) {
      setState(() {
        apply();
        _overridden = true;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Result', style: CruType.headline.tint(c.label)),
        const SizedBox(height: CruSpace.s8),
        Text(resultText, style: CruType.title2.tint(c.label)),
        const SizedBox(height: CruSpace.s16),
        Text('Diagnosis', style: CruType.subhead.w600.tint(c.label)),
        const SizedBox(height: CruSpace.s6),
        DentalChipWrap<String>(
          options: const ['health', 'gingivitis', 'periodontitis'],
          label: _title,
          isSelected: (v) => _diagnosis == v,
          onTap: (v) => overrideWith(() => _diagnosis = v),
        ),
        const SizedBox(height: CruSpace.s12),
        Text('Stage', style: CruType.subhead.w600.tint(c.label)),
        const SizedBox(height: CruSpace.s6),
        DentalChipWrap<int>(
          options: const [0, 1, 2, 3, 4],
          label: (v) => v == 0 ? '—' : _roman(v),
          isSelected: (v) => _stage == v,
          onTap: (v) => overrideWith(() => _stage = v),
        ),
        const SizedBox(height: CruSpace.s12),
        Text('Extent', style: CruType.subhead.w600.tint(c.label)),
        const SizedBox(height: CruSpace.s6),
        DentalChipWrap<String>(
          options: const ['', 'localized', 'generalized', 'molarIncisor'],
          label: (v) => v.isEmpty ? '—' : _extentLabel(v),
          isSelected: (v) => (_extent ?? '') == v,
          onTap: (v) =>
              overrideWith(() => _extent = v.isEmpty ? null : v),
        ),
        const SizedBox(height: CruSpace.s12),
        Text('Grade', style: CruType.subhead.w600.tint(c.label)),
        const SizedBox(height: CruSpace.s6),
        DentalChipWrap<String>(
          options: const ['A', 'B', 'C'],
          label: (v) => v,
          isSelected: (v) => _grade == v,
          onTap: (v) => overrideWith(() => _grade = v),
        ),
        const SizedBox(height: CruSpace.s16),
        Text('Why', style: CruType.headline.tint(c.label)),
        const SizedBox(height: CruSpace.s4),
        for (final r in _auto.reasons)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• $r', style: CruType.caption.tint(c.label2)),
          ),
        const SizedBox(height: CruSpace.s16),
        CruTextField(
          label: 'Notes',
          optional: true,
          controller: _notes,
          maxLines: 2,
        ),
        const SizedBox(height: CruSpace.s16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            CruButton(
              label: 'Cancel',
              kind: CruButtonKind.secondary,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: CruSpace.s8),
            CruButton(label: 'Save diagnosis', onPressed: _save),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ helpers

Map<String, PerioTooth> _teethOf(DentalRecord r) {
  final raw = r.data['teeth'];
  final out = <String, PerioTooth>{};
  for (final t in [...DentalChart.adultUpper, ...DentalChart.adultLower]) {
    out[t] = PerioTooth.fromJson(raw is Map ? raw[t] : null);
  }
  return out;
}

bool _hasNonAdjacent(
  Map<String, PerioTooth> teeth,
  bool Function(String, int) qualify,
) {
  final qualifying = <String>{};

  for (final arch in [DentalChart.adultUpper, DentalChart.adultLower]) {
    for (final t in arch) {
      final tooth = teeth[t];
      if (tooth == null || tooth.missing) continue;
      for (var s = 0; s < 6; s++) {
        if (qualify(t, s)) {
          qualifying.add(t);
          break;
        }
      }
    }
  }

  if (qualifying.length < 2) return false;
  if (qualifying.length >= 3) return true;

  final list = qualifying.toList();
  bool adjacent(String a, String b) {
    for (final arch in [DentalChart.adultUpper, DentalChart.adultLower]) {
      final ia = arch.indexOf(a);
      final ib = arch.indexOf(b);
      if (ia >= 0 && ib >= 0) return (ia - ib).abs() == 1;
    }
    return false;
  }

  return !adjacent(list[0], list[1]);
}

int? _worstInterdentalCal(Map<String, PerioTooth> teeth) {
  int? worst;
  for (final t in teeth.values) {
    if (t.missing) continue;
    for (final s in _interdentalSites) {
      final v = t.cal(s);
      if (v != null && (worst == null || v > worst)) worst = v;
    }
  }
  return worst;
}

int? _maxPd(Map<String, PerioTooth> teeth) {
  int? max;
  for (final t in teeth.values) {
    if (t.missing) continue;
    for (final v in t.pd) {
      if (v != null && (max == null || v > max)) max = v;
    }
  }
  return max;
}

String? _maxPdTooth(Map<String, PerioTooth> teeth) {
  int? max;
  String? tooth;
  for (final e in teeth.entries) {
    final t = e.value;
    if (t.missing) continue;
    for (final v in t.pd) {
      if (v != null && (max == null || v > max)) {
        max = v;
        tooth = e.key;
      }
    }
  }
  return tooth;
}

int? _maxMobility(Map<String, PerioTooth> teeth) {
  int? max;
  for (final t in teeth.values) {
    if (t.missing) continue;
    final v = t.mobility;
    if (v != null && (max == null || v > max)) max = v;
  }
  return max;
}

int _presentTeeth(Map<String, PerioTooth> teeth) =>
    teeth.values.where((t) => !t.missing).length;

int _involvedTeeth(Map<String, PerioTooth> teeth) {
  var n = 0;
  for (final t in teeth.values) {
    if (t.missing) continue;
    var involved = false;
    for (var s = 0; s < 6; s++) {
      if ((t.cal(s) ?? -999) >= 3) {
        involved = true;
        break;
      }
    }
    if (involved) n++;
  }
  return n;
}

String _maxGrade(String a, String b) {
  const order = {'A': 0, 'B': 1, 'C': 2};
  return order[a]! >= order[b]! ? a : b;
}

String _roman(int v) => switch (v) {
  1 => 'I',
  2 => 'II',
  3 => 'III',
  4 => 'IV',
  _ => '$v',
};

String _title(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _extentLabel(String? e) => switch (e) {
  'localized' => 'Localized',
  'generalized' => 'Generalized',
  'molarIncisor' => 'Molar/incisor',
  _ => '',
};
