import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_art.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';

/// 3D view: teeth coloured by what was found, or planned work standing
/// out.
enum ChartMode { findings, plan }

/// What the 2D chart shows on the teeth.
enum ChartLayer {
  /// What was found and what was done.
  dental,

  /// Work still to do, drawn where it will go; the rest steps back.
  plan,

  /// Gum line, pockets and bleeding from the latest perio exam.
  perio,

  /// Pulp and canals, with the endo records.
  endo,

  /// Everything at once.
  all;

  String get label => switch (this) {
        dental => 'Dental',
        plan => 'Plan',
        perio => 'Perio',
        endo => 'Endo',
        all => 'All',
      };

  bool get showsPlan => this == plan || this == all;
  bool get showsPerio => this == perio || this == all;
  bool get showsEndo => this == endo || this == all;

  /// The closest 3D mode.
  ChartMode get mode => this == plan ? ChartMode.plan : ChartMode.findings;
}

/// The gist of a tooth's endo record.
class EndoState {
  const EndoState({
    required this.record,
    required this.obturated,
    required this.canals,
    required this.pulpal,
    required this.periapical,
  });

  factory EndoState.of(DentalRecord r) => EndoState(
        record: r,
        obturated: r.str('status') == 'obturated',
        canals: r.data['canals'] is List ? (r.data['canals'] as List).length : 0,
        pulpal: r.str('pulpal'),
        periapical: r.str('periapical'),
      );

  final DentalRecord record;
  final bool obturated;
  final int canals;
  final String pulpal;
  final String periapical;

  /// Infection at the root tip.
  bool get lesion =>
      periapical.isNotEmpty && periapical != 'Normal apical tissues';

  /// Pulp inflamed or dead.
  bool get inflamed =>
      pulpal.contains('pulpitis') || pulpal.contains('necrosis');

  /// "Obturated · 3 canals", "In progress · Pulp necrosis".
  String get summary => [
        obturated ? 'Obturated' : 'In progress',
        if (canals > 0) '$canals canal${canals == 1 ? '' : 's'}',
        if (!obturated && pulpal.isNotEmpty) pulpal,
      ].join(' · ');
}

/// Everything the charts need to draw one tooth.
class ToothVisual {
  const ToothVisual({
    required this.number,
    required this.state,
    this.condition,
    this.treatment,
    this.surfaces = const [],
    this.planned = const [],
    this.plannedWork = const [],
    this.perio,
    this.endo,
  });

  final String number;
  final ToothState state;
  final ToothCondition? condition;
  final ToothTreatment? treatment;
  final List<ToothSurface> surfaces;

  /// Procedures still to do on this tooth (proposed or accepted).
  final List<String> planned;

  /// What each planned procedure leaves on the tooth (null when it
  /// doesn't map to a treatment).
  final List<ToothTreatment?> plannedWork;

  /// This tooth in the latest perio exam.
  final PerioTooth? perio;

  /// The latest endo record for this tooth.
  final EndoState? endo;

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
  bool get impacted =>
      condition == ToothCondition.impacted && treatment == null;

  /// Perio readings exist for this tooth.
  bool get charted =>
      perio != null &&
      !perio!.missing &&
      (perio!.pd.any((d) => d != null) || perio!.rec.any((r) => r != null));

  /// "Decay", "Crown", "Root canal"; null for a healthy tooth.
  String? callout(ChartMode mode) {
    if (mode == ChartMode.plan) {
      return isPlanned ? planned.join(', ') : null;
    }
    if (treatment != null) return DentalChart.treatmentLabel(treatment!);
    if (condition != null) return DentalChart.conditionLabel(condition!);
    return null;
  }

  /// What the chart says about this tooth in [layer]; null when there's
  /// nothing to say.
  String? detail(ChartLayer layer) {
    switch (layer) {
      case ChartLayer.plan:
        return isPlanned ? 'Planned: ${planned.join(', ')}' : null;
      case ChartLayer.perio:
        final p = perio;
        if (!charted || p == null) return null;
        final depths = p.pd.whereType<int>();
        final deepest = depths.isEmpty ? null : depths.reduce((a, b) => a > b ? a : b);
        final bleeding = p.bop.where((b) => b).length;
        return [
          if (deepest != null) 'Deepest pocket $deepest mm',
          if (bleeding > 0) 'bleeds at $bleeding site${bleeding == 1 ? '' : 's'}',
          if ((p.mobility ?? 0) > 0) 'mobility ${p.mobility}',
        ].join(' · ');
      case ChartLayer.endo:
        return endo?.summary ?? (rootCanal ? 'Root canal treated' : null);
      case ChartLayer.dental || ChartLayer.all:
        final found = callout(ChartMode.findings);
        final s = surfaces.isEmpty
            ? ''
            : ' · ${surfaces.map(DentalChart.surfaceLetter).join(', ')}';
        final parts = [
          if (found != null) '$found$s',
          if (layer == ChartLayer.all && isPlanned) 'Planned: ${planned.join(', ')}',
        ];
        return parts.isEmpty ? null : parts.join(' · ');
    }
  }

  /// How the tooth is drawn in [layer].
  ToothLook look(ChartLayer layer) {
    final spec = ToothSpec.of(number);
    final back = spec.kind == ToothKind.premolar || spec.kind == ToothKind.molar;
    Set<ToothSurface> where() => surfaces.isNotEmpty
        ? surfaces.toSet()
        : {back ? ToothSurface.occlusal : ToothSurface.buccal};
    final pulp = !missing &&
        !implant &&
        (layer == ChartLayer.endo ||
            (layer == ChartLayer.all && (endo != null || rootCanal)));
    return ToothLook(
      missing: missing,
      implant: implant,
      capped: capped,
      rootCanal: rootCanal,
      fractured: fractured,
      impacted: impacted,
      unerupted: state == ToothState.notErupted,
      decay: decay ? where() : const {},
      filled: filled ? where() : const {},
      planned: layer.showsPlan ? plannedWork : const [],
      dim: layer == ChartLayer.plan && !isPlanned,
      pulp: pulp,
      canals: endo == null
          ? CanalState.none
          : endo!.obturated
              ? CanalState.obturated
              : CanalState.inProgress,
      lesion: pulp && (endo?.lesion ?? false),
      inflamed: pulp && (endo?.inflamed ?? false),
    );
  }
}

/// The chart for one patient: every tooth's latest finding, its planned
/// work, perio readings and endo record.
class ToothChartData {
  ToothChartData(this._teeth, {this.perioExam});

  factory ToothChartData.from(
    List<ToothChartEntryModel> entries,
    List<TreatmentPlanLineItemModel> plan, {
    DentalRecord? perioExam,
    List<DentalRecord> endo = const [],
  }) {
    final latest = DentalChart.latest(entries);
    final planned = <String, List<String>>{};
    final work = <String, List<ToothTreatment?>>{};
    for (final i in plan) {
      if (i.isDeleted) continue;
      final s = TreatmentPlanItemStatus.fromString(i.status);
      if (s != TreatmentPlanItemStatus.proposed &&
          s != TreatmentPlanItemStatus.accepted) {
        continue;
      }
      final name = i.procedureName.trim();
      for (final t in i.toothNumbers) {
        final n = t.trim();
        if (n.isEmpty) continue;
        (planned[n] ??= []).add(name.isEmpty ? 'Procedure' : name);
        (work[n] ??= []).add(DentalChart.treatmentForProcedure('', name));
      }
    }
    final perio = <String, PerioTooth>{};
    final rawTeeth = perioExam?.data['teeth'];
    if (rawTeeth is Map) {
      for (final e in rawTeeth.entries) {
        perio['${e.key}'] = PerioTooth.fromJson(e.value);
      }
    }
    // Newest record per tooth (the list comes newest first).
    final endoOf = <String, EndoState>{};
    for (final r in endo) {
      final t = r.str('tooth').trim();
      if (t.isNotEmpty) endoOf.putIfAbsent(t, () => EndoState.of(r));
    }
    final teeth = <String, ToothVisual>{};
    for (final n in {...latest.keys, ...planned.keys, ...perio.keys, ...endoOf.keys}) {
      final e = latest[n];
      teeth[n] = ToothVisual(
        number: n,
        state: DentalChart.stateOf(e),
        condition: DentalChart.condition(e?.condition),
        treatment: DentalChart.treatment(e?.treatment),
        surfaces: DentalChart.surfaces(e?.surface),
        planned: planned[n] ?? const [],
        plannedWork: work[n] ?? const [],
        perio: perio[n],
        endo: endoOf[n],
      );
    }
    return ToothChartData(teeth, perioExam: perio.isEmpty ? null : perioExam);
  }

  final Map<String, ToothVisual> _teeth;

  /// The perio exam the readings come from; null when there are none.
  final DentalRecord? perioExam;

  ToothVisual of(String n) =>
      _teeth[n] ?? ToothVisual(number: n, state: ToothState.healthy);

  bool get hasPrimary => _teeth.keys.any(DentalChart.isPrimary);
  bool get hasPermanent =>
      _teeth.keys.any((t) => !DentalChart.isPrimary(t));

  int count(ToothState s) =>
      _teeth.values.where((t) => t.state == s).length;

  int get plannedTeeth => _teeth.values.where((t) => t.isPlanned).length;

  bool get hasEndo => _teeth.values.any((t) => t.endo != null || t.rootCanal);
}
