import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';

/// How a tooth looks on the chart, from its latest finding.
enum ToothState { healthy, needsCare, treated, missing, notErupted }

/// Tooth numbering (FDI), names and findings for the dental screens.
abstract final class DentalChart {
  /// Drawn as the dentist faces the patient: the patient's right is on
  /// the left.
  static const adultUpper = [
    '18', '17', '16', '15', '14', '13', '12', '11',
    '21', '22', '23', '24', '25', '26', '27', '28',
  ];
  static const adultLower = [
    '48', '47', '46', '45', '44', '43', '42', '41',
    '31', '32', '33', '34', '35', '36', '37', '38',
  ];
  static const childUpper = [
    '55', '54', '53', '52', '51', '61', '62', '63', '64', '65',
  ];
  static const childLower = [
    '85', '84', '83', '82', '81', '71', '72', '73', '74', '75',
  ];

  static final Set<String> _all = {
    ...adultUpper,
    ...adultLower,
    ...childUpper,
    ...childLower,
  };

  static bool isValid(String tooth) => _all.contains(tooth);

  /// Milk teeth are quadrants 5 to 8.
  static bool isPrimary(String tooth) {
    final q = int.tryParse(tooth.isEmpty ? '' : tooth[0]);
    return q != null && q >= 5 && q <= 8;
  }

  /// "Upper right first molar", "Lower left canine (milk tooth)".
  static String name(String tooth) {
    if (tooth.length != 2) return 'Tooth $tooth';
    final q = int.tryParse(tooth[0]);
    final n = int.tryParse(tooth[1]);
    if (q == null || n == null) return 'Tooth $tooth';
    final primary = q >= 5;
    final quadrant = primary ? q - 4 : q;
    final side = switch (quadrant) {
      1 => 'Upper right',
      2 => 'Upper left',
      3 => 'Lower left',
      4 => 'Lower right',
      _ => null,
    };
    final kind = primary
        ? switch (n) {
            1 => 'central incisor',
            2 => 'lateral incisor',
            3 => 'canine',
            4 => 'first molar',
            5 => 'second molar',
            _ => null,
          }
        : switch (n) {
            1 => 'central incisor',
            2 => 'lateral incisor',
            3 => 'canine',
            4 => 'first premolar',
            5 => 'second premolar',
            6 => 'first molar',
            7 => 'second molar',
            8 => 'wisdom tooth',
            _ => null,
          };
    if (side == null || kind == null) return 'Tooth $tooth';
    return '$side $kind${primary ? ' (milk tooth)' : ''}';
  }

  // ---------------------------------------------------------------- findings

  static ToothCondition? condition(String? stored) {
    final v = stored?.trim().toLowerCase();
    if (v == null || v.isEmpty) return null;
    for (final c in ToothCondition.values) {
      if (c.name.toLowerCase() == v) return c;
    }
    return null;
  }

  static ToothTreatment? treatment(String? stored) {
    final v = stored?.trim().toLowerCase();
    if (v == null || v.isEmpty) return null;
    for (final t in ToothTreatment.values) {
      if (t.name.toLowerCase() == v) return t;
    }
    return null;
  }

  static String conditionLabel(ToothCondition c) => switch (c) {
        ToothCondition.caries => 'Decay',
        ToothCondition.fractured => 'Fractured',
        ToothCondition.missing => 'Missing',
        ToothCondition.unerupted => 'Not erupted',
        ToothCondition.impacted => 'Impacted',
        ToothCondition.restored => 'Restored',
        ToothCondition.rootCanal => 'Root canal treated',
      };

  static String treatmentLabel(ToothTreatment t) => switch (t) {
        ToothTreatment.filling => 'Filling',
        ToothTreatment.extraction => 'Extraction',
        ToothTreatment.crown => 'Crown',
        ToothTreatment.bridge => 'Bridge',
        ToothTreatment.implant => 'Implant',
        ToothTreatment.scaling => 'Scaling',
        ToothTreatment.rct => 'Root canal',
      };

  /// One letter per surface, as dentists write them (M, D, O, B, L, I, C).
  static String surfaceLetter(ToothSurface s) => switch (s) {
        ToothSurface.mesial => 'M',
        ToothSurface.distal => 'D',
        ToothSurface.occlusal => 'O',
        ToothSurface.buccal => 'B',
        ToothSurface.lingual => 'L',
        ToothSurface.incisal => 'I',
        ToothSurface.cervical => 'C',
      };

  static String surfaceLabel(ToothSurface s) =>
      '${s.name[0].toUpperCase()}${s.name.substring(1)}';

  /// Surfaces are stored comma-separated ("mesial,occlusal").
  static List<ToothSurface> surfaces(String? stored) {
    if (stored == null || stored.trim().isEmpty) return const [];
    final parts = stored.toLowerCase().split(RegExp(r'[,\s]+'));
    return [
      for (final s in ToothSurface.values)
        if (parts.contains(s.name)) s,
    ];
  }

  static String? storeSurfaces(Iterable<ToothSurface> surfaces) =>
      surfaces.isEmpty ? null : surfaces.map((s) => s.name).join(',');

  static ToothState stateOf(ToothChartEntryModel? e) {
    if (e == null) return ToothState.healthy;
    final t = treatment(e.treatment);
    if (t == ToothTreatment.extraction) return ToothState.missing;
    if (t != null) return ToothState.treated;
    return switch (condition(e.condition)) {
      ToothCondition.caries ||
      ToothCondition.fractured ||
      ToothCondition.impacted =>
        ToothState.needsCare,
      ToothCondition.missing => ToothState.missing,
      ToothCondition.unerupted => ToothState.notErupted,
      ToothCondition.restored || ToothCondition.rootCanal => ToothState.treated,
      null => ToothState.healthy,
    };
  }

  static String stateLabel(ToothState s) => switch (s) {
        ToothState.healthy => 'Healthy',
        ToothState.needsCare => 'Needs care',
        ToothState.treated => 'Treated',
        ToothState.missing => 'Missing',
        ToothState.notErupted => 'Not erupted',
      };

  /// "Decay · M, O · Filling"; "Healthy" when nothing was found.
  static String findingText(ToothChartEntryModel e) {
    final c = condition(e.condition);
    final t = treatment(e.treatment);
    final s = surfaces(e.surface);
    final parts = [
      if (c != null) conditionLabel(c),
      if (s.isNotEmpty) s.map(surfaceLetter).join(', '),
      if (t != null) '${treatmentLabel(t)} done',
    ];
    return parts.isEmpty ? 'Healthy' : parts.join(' · ');
  }

  /// Newest finding per tooth.
  static Map<String, ToothChartEntryModel> latest(
    List<ToothChartEntryModel> entries,
  ) {
    final sorted = [...entries]
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final map = <String, ToothChartEntryModel>{};
    for (final e in sorted) {
      if (e.isDeleted) continue;
      map.putIfAbsent(e.toothNumber, () => e);
    }
    return map;
  }

  /// Teeth with a plan item still to do (proposed or accepted).
  static Set<String> planned(List<TreatmentPlanLineItemModel> items) => {
        for (final i in items)
          if (!i.isDeleted &&
              const {
                TreatmentPlanItemStatus.proposed,
                TreatmentPlanItemStatus.accepted,
              }.contains(TreatmentPlanItemStatus.fromString(i.status)))
            ...i.toothNumbers.map((t) => t.trim()),
      };

  /// Reads "16, 17 21" as tooth numbers. [invalid] is the first word that
  /// isn't a tooth.
  static ({List<String> teeth, String? invalid}) parseTeeth(String text) {
    final teeth = <String>[];
    for (final part in text.split(RegExp(r'[,\s]+'))) {
      final t = part.trim();
      if (t.isEmpty) continue;
      if (!isValid(t)) return (teeth: teeth, invalid: t);
      if (!teeth.contains(t)) teeth.add(t);
    }
    return (teeth: teeth, invalid: null);
  }

  /// "Tooth 16" / "Teeth 16, 17"; null when there are none. Shown in
  /// whichever numbering the clinic has chosen.
  static String? teethText(
    Iterable<String> teeth, [
    ToothNumbering numbering = ToothNumbering.fdi,
  ]) {
    final list = teeth
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .map((t) => toothLabel(t, numbering))
        .toList();
    if (list.isEmpty) return null;
    return '${list.length == 1 ? 'Tooth' : 'Teeth'} ${list.join(', ')}';
  }

  /// What a completed procedure leaves on the tooth, for the chart.
  static ToothTreatment? treatmentForProcedure(String code, String name) {
    final c = code.toUpperCase();
    final n = name.toLowerCase();
    if (c.startsWith('RCT') || n.contains('root canal')) {
      return ToothTreatment.rct;
    }
    if (c.startsWith('EXT') || n.contains('extraction')) {
      return ToothTreatment.extraction;
    }
    if (c.startsWith('IMPL') || n.contains('implant')) {
      return ToothTreatment.implant;
    }
    if (c.startsWith('BRIDGE') || n.contains('bridge')) {
      return ToothTreatment.bridge;
    }
    if (c.startsWith('CROWN') || n.contains('crown')) {
      return ToothTreatment.crown;
    }
    if (c.startsWith('FILL') ||
        n.contains('filling') ||
        n.contains('restoration')) {
      return ToothTreatment.filling;
    }
    if (c.startsWith('SCALE') || n.contains('scaling')) {
      return ToothTreatment.scaling;
    }
    return null;
  }
}
