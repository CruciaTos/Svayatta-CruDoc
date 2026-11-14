import 'dart:convert';

import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';

/// The state the 3D "show the patient" page starts from: every charted tooth,
/// the work done and planned, and the dentist's saved view state.
///
/// Charted treatments (a row with a `treatment`, `restored` or `rootCanal`)
/// are completed work. Planned work comes from [plan] (proposed or accepted
/// treatment-plan items), since chart rows carry no planned flag.
Map<String, dynamic> buildDental3dSnapshot(
  List<ToothChartEntryModel> entries, {
  List<TreatmentPlanLineItemModel> plan = const [],
  String? savedJson,
}) {
  final teeth = <String, Map<String, dynamic>>{};
  final treatments = <Map<String, dynamic>>[];
  // Per tooth: statuses of its treatments.
  final statuses = <String, List<String>>{};
  var scalingDone = false;

  Map<String, dynamic> toothOf(String fdi) => teeth.putIfAbsent(
    fdi,
    () => {
      'present': true,
      'status': 'normal',
      'chip': 0,
      'conditions': <Map<String, dynamic>>[],
    },
  );

  void addTreatment({
    required String id,
    required String type,
    required List<String> on,
    required List<String> surfaces,
    required String status,
  }) {
    final visit = status == 'completed' ? 0 : 1;
    if (type == 'scaling') {
      treatments.add({
        'id': id,
        'origin': 'chart',
        'type': type,
        'teeth': <int>[],
        'arches': ['upper', 'lower'],
        'surfaces': <String>[],
        'status': status,
        'visit': visit,
      });
      return;
    }
    treatments.add({
      'id': id,
      'origin': 'chart',
      'type': type,
      'teeth': [for (final t in on) int.parse(t)],
      'surfaces': surfaces,
      'status': status,
      'visit': visit,
    });
    for (final t in on) {
      (statuses[t] ??= []).add(status);
    }
  }

  final latest = DentalChart.latest(entries);
  for (final MapEntry(key: raw, value: e) in latest.entries) {
    final fdi = _toFdi(raw, e.notationSystem);
    if (fdi == null) continue;
    final tooth = toothOf(fdi);
    final surfaces = _surfaces(e.surface);
    final conditions = tooth['conditions'] as List<Map<String, dynamic>>;
    switch (DentalChart.condition(e.condition)) {
      case ToothCondition.caries:
        conditions.add({'type': 'caries', 'surfaces': surfaces});
      case ToothCondition.fractured:
        conditions.add({'type': 'fracture', 'surfaces': surfaces});
        tooth['chip'] = 0.5;
      case ToothCondition.missing || ToothCondition.unerupted:
        tooth['present'] = false;
      case ToothCondition.impacted:
        conditions.add({'type': 'impacted', 'surfaces': surfaces});
      case ToothCondition.restored:
        addTreatment(
          id: 'chart_${e.id}',
          type: 'filling',
          on: [fdi],
          surfaces: surfaces,
          status: 'completed',
        );
      case ToothCondition.rootCanal:
        addTreatment(
          id: 'chart_${e.id}',
          type: 'rct',
          on: [fdi],
          surfaces: const [],
          status: 'completed',
        );
      case ToothCondition.boneLoss:
        // Depth only when the note states it ("bone loss 3.5 mm"): the page
        // shows the number, so none is invented.
        final mm = RegExp(r'(\d+(?:\.\d+)?)\s*mm', caseSensitive: false)
            .firstMatch(e.notes);
        final depth = mm == null ? null : double.tryParse(mm.group(1)!);
        if (depth != null && depth > 0) tooth['boneLoss'] = depth;
      case ToothCondition.periapicalLesion:
        // The viewer's "infection at root tip" condition.
        conditions.add({'type': 'abscess', 'surfaces': surfaces});
      case null:
        break;
    }
    final t = DentalChart.treatment(e.treatment);
    if (t == null) continue;
    if (t == ToothTreatment.scaling) {
      if (!scalingDone) {
        scalingDone = true;
        addTreatment(
          id: 'chart_${e.id}',
          type: 'scaling',
          on: const [],
          surfaces: const [],
          status: 'completed',
        );
      }
      continue;
    }
    addTreatment(
      id: 'chart_${e.id}',
      type: t.name,
      on: [fdi],
      surfaces: surfaces,
      status: 'completed',
    );
    if (t == ToothTreatment.extraction) tooth['present'] = false;
  }

  for (final i in plan) {
    if (i.isDeleted) continue;
    final s = TreatmentPlanItemStatus.fromString(i.status);
    if (s != TreatmentPlanItemStatus.proposed &&
        s != TreatmentPlanItemStatus.accepted) {
      continue;
    }
    final t = DentalChart.treatmentForProcedure('', i.procedureName);
    if (t == null) continue;
    final on = <String>[
      for (final n in i.toothNumbers) ?_toFdi(n.trim(), 'fdi'),
    ];
    if (t != ToothTreatment.scaling && on.isEmpty) continue;
    for (final f in on) {
      toothOf(f);
    }
    addTreatment(
      id: 'plan_${i.id}',
      type: t.name,
      on: on,
      surfaces: const [],
      status: 'planned',
    );
  }

  for (final MapEntry(key: fdi, value: tooth) in teeth.entries) {
    final st = statuses[fdi] ?? const <String>[];
    final hasCondition = (tooth['conditions'] as List).isNotEmpty;
    tooth['status'] = st.contains('inProgress')
        ? 'inProgress'
        : st.contains('planned')
        ? 'planned'
        : st.isNotEmpty
        ? 'completed'
        : hasCondition
        ? 'flagged'
        : 'normal';
  }

  final open = treatments.any((t) => t['status'] != 'completed');
  Object? saved;
  if (savedJson != null && savedJson.isNotEmpty) {
    try {
      saved = jsonDecode(savedJson);
    } on FormatException {
      saved = null;
    }
  }
  return {
    'schema': 1,
    'teeth': teeth,
    'treatments': treatments,
    if (open)
      'visits': [
        {'id': 1, 'label': 'Planned treatment'},
      ],
    'currentVisit': 0,
    'saved': saved,
  };
}

/// FDI permanent tooth (11-48) from a stored number; null for milk teeth or
/// anything else.
String? _toFdi(String raw, String notation) {
  final n = int.tryParse(raw.trim());
  if (n == null) return null;
  if (notation.toLowerCase() == 'universal') {
    if (n < 1 || n > 32) return null;
    final q = (n - 1) ~/ 8;
    final i = (n - 1) % 8;
    return switch (q) {
      0 => '${10 + 8 - i}',
      1 => '${20 + i + 1}',
      2 => '${30 + 8 - i}',
      _ => '${40 + i + 1}',
    };
  }
  final quadrant = n ~/ 10;
  final pos = n % 10;
  if (quadrant < 1 || quadrant > 4 || pos < 1 || pos > 8) return null;
  return '$n';
}

/// M / D / O / B / L from the stored comma-separated surfaces, without repeats.
List<String> _surfaces(String? stored) {
  final out = <String>[];
  for (final s in DentalChart.surfaces(stored)) {
    final code = switch (s) {
      ToothSurface.mesial => 'M',
      ToothSurface.distal => 'D',
      ToothSurface.occlusal || ToothSurface.incisal => 'O',
      ToothSurface.buccal || ToothSurface.cervical => 'B',
      ToothSurface.lingual => 'L',
    };
    if (!out.contains(code)) out.add(code);
  }
  return out;
}
