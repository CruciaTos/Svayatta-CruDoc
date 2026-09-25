import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';

/// Findings: teeth coloured by what was found. Plan: teeth with work
/// still to do stand out, the rest step back.
enum ChartMode { findings, plan }

/// Everything the 2D and 3D charts need to draw one tooth.
class ToothVisual {
  const ToothVisual({
    required this.number,
    required this.state,
    this.condition,
    this.treatment,
    this.surfaces = const [],
    this.planned = const [],
  });

  final String number;
  final ToothState state;
  final ToothCondition? condition;
  final ToothTreatment? treatment;
  final List<ToothSurface> surfaces;

  /// Procedures still to do on this tooth (proposed or accepted).
  final List<String> planned;

  bool get isPlanned => planned.isNotEmpty;
  bool get missing => state == ToothState.missing;
  bool get implant => treatment == ToothTreatment.implant;
  bool get rootCanal =>
      treatment == ToothTreatment.rct || condition == ToothCondition.rootCanal;
  bool get filled =>
      treatment == ToothTreatment.filling ||
      (treatment == null && condition == ToothCondition.restored);
  bool get capped =>
      treatment == ToothTreatment.crown ||
      treatment == ToothTreatment.bridge ||
      treatment == ToothTreatment.implant;
  bool get decay => condition == ToothCondition.caries && treatment == null;
  bool get fractured =>
      condition == ToothCondition.fractured && treatment == null;

  /// "Decay", "Crown", "Plan: Root canal"; null for a healthy tooth.
  String? callout(ChartMode mode) {
    if (mode == ChartMode.plan) {
      return isPlanned ? planned.join(', ') : null;
    }
    if (treatment != null) return DentalChart.treatmentLabel(treatment!);
    if (condition != null) return DentalChart.conditionLabel(condition!);
    return null;
  }
}

/// The chart for one patient: every tooth's latest finding and plan.
class ToothChartData {
  ToothChartData(this._teeth);

  factory ToothChartData.from(
    List<ToothChartEntryModel> entries,
    List<TreatmentPlanLineItemModel> plan,
  ) {
    final latest = DentalChart.latest(entries);
    final planned = <String, List<String>>{};
    for (final i in plan) {
      if (i.isDeleted) continue;
      final s = TreatmentPlanItemStatus.fromString(i.status);
      if (s != TreatmentPlanItemStatus.proposed &&
          s != TreatmentPlanItemStatus.accepted) {
        continue;
      }
      for (final t in i.toothNumbers) {
        final n = t.trim();
        if (n.isEmpty) continue;
        final name = i.procedureName.trim();
        (planned[n] ??= []).add(name.isEmpty ? 'Procedure' : name);
      }
    }
    final teeth = <String, ToothVisual>{};
    for (final n in {...latest.keys, ...planned.keys}) {
      final e = latest[n];
      teeth[n] = ToothVisual(
        number: n,
        state: DentalChart.stateOf(e),
        condition: DentalChart.condition(e?.condition),
        treatment: DentalChart.treatment(e?.treatment),
        surfaces: DentalChart.surfaces(e?.surface),
        planned: planned[n] ?? const [],
      );
    }
    return ToothChartData(teeth);
  }

  final Map<String, ToothVisual> _teeth;

  ToothVisual of(String n) =>
      _teeth[n] ?? ToothVisual(number: n, state: ToothState.healthy);

  bool get hasPrimary => _teeth.keys.any(DentalChart.isPrimary);
  bool get hasPermanent =>
      _teeth.keys.any((t) => !DentalChart.isPrimary(t));

  int count(ToothState s) =>
      _teeth.values.where((t) => t.state == s).length;

  int get plannedTeeth => _teeth.values.where((t) => t.isPlanned).length;
}
