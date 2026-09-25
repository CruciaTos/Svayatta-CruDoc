import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';

/// Result of evaluating Decayed, Missing, Filled Teeth (DMFT / dmft) indices.
class DmftResult {
  /// Permanent dentition Decayed teeth count (D).
  final int d;

  /// Permanent dentition Missing teeth count (M), excluding unerupted teeth.
  final int m;

  /// Permanent dentition Filled / Restored teeth count (F) without active decay.
  final int f;

  /// Permanent DMFT total score (D + M + F).
  int get total => d + m + f;

  /// Primary (deciduous) dentition decayed teeth count (d).
  final int primaryD;

  /// Primary (deciduous) dentition missing teeth count (m).
  final int primaryM;

  /// Primary (deciduous) dentition filled teeth count (f).
  final int primaryF;

  /// Primary dmft total score (d + m + f).
  int get primaryTotal => primaryD + primaryM + primaryF;

  /// List of tooth numbers evaluated in each category.
  final Set<String> decayedTeeth;
  final Set<String> missingTeeth;
  final Set<String> filledTeeth;

  const DmftResult({
    required this.d,
    required this.m,
    required this.f,
    this.primaryD = 0,
    this.primaryM = 0,
    this.primaryF = 0,
    this.decayedTeeth = const {},
    this.missingTeeth = const {},
    this.filledTeeth = const {},
  });

  static const empty = DmftResult(d: 0, m: 0, f: 0);

  Map<String, dynamic> toJson() => {
        'd': d,
        'm': m,
        'f': f,
        'dmft': total,
        'primaryD': primaryD,
        'primaryM': primaryM,
        'primaryF': primaryF,
        'primaryDmft': primaryTotal,
        'decayedTeeth': decayedTeeth.toList(),
        'missingTeeth': missingTeeth.toList(),
        'filledTeeth': filledTeeth.toList(),
      };
}

/// Computes DMFT (permanent) and dmft (primary) indices from a patient's tooth chart entries.
///
/// Rules (PH3 spec):
/// - Uses the latest entry per tooth via [DentalChart.latest].
/// - D: Teeth with active caries condition.
/// - M: Missing teeth due to caries or extraction (excluding unerupted teeth).
/// - F: Restored or filled teeth with no active caries.
DmftResult computeDmft(List<ToothChartEntryModel> entries) {
  if (entries.isEmpty) return DmftResult.empty;

  final latestByTooth = DentalChart.latest(entries);

  int d = 0;
  int m = 0;
  int f = 0;

  int pd = 0;
  int pm = 0;
  int pf = 0;

  final decayed = <String>{};
  final missing = <String>{};
  final filled = <String>{};

  for (final MapEntry(key: tooth, value: entry) in latestByTooth.entries) {
    final cond = DentalChart.condition(entry.condition);
    final treat = DentalChart.treatment(entry.treatment);

    // Primary teeth in FDI have quadrant prefix 5, 6, 7, 8
    final isPrimary = tooth.startsWith('5') ||
        tooth.startsWith('6') ||
        tooth.startsWith('7') ||
        tooth.startsWith('8');

    // 1. Caries check (Decayed)
    final isDecayed = cond == ToothCondition.caries;

    // 2. Missing check (Missing due to caries/extraction, never unerupted)
    final isMissing = cond == ToothCondition.missing ||
        treat == ToothTreatment.extraction;
    final isUnerupted = cond == ToothCondition.unerupted;

    // 3. Filled check (Restored or filled, without active caries)
    final isFilled = !isDecayed &&
        (cond == ToothCondition.restored ||
            treat == ToothTreatment.filling ||
            treat == ToothTreatment.crown ||
            treat == ToothTreatment.bridge ||
            treat == ToothTreatment.rct);

    if (isPrimary) {
      if (isDecayed) {
        pd++;
      } else if (isMissing && !isUnerupted) {
        pm++;
      } else if (isFilled) {
        pf++;
      }
    } else {
      if (isDecayed) {
        d++;
        decayed.add(tooth);
      } else if (isMissing && !isUnerupted) {
        m++;
        missing.add(tooth);
      } else if (isFilled) {
        f++;
        filled.add(tooth);
      }
    }
  }

  return DmftResult(
    d: d,
    m: m,
    f: f,
    primaryD: pd,
    primaryM: pm,
    primaryF: pf,
    decayedTeeth: decayed,
    missingTeeth: missing,
    filledTeeth: filled,
  );
}

/// Provider that computes DMFT indices for a patient from their tooth chart.
final patientDmftProvider =
    FutureProvider.family<DmftResult, String>((ref, patientId) async {
  final entries = await ref.watch(patientToothChartProvider(patientId).future);
  return computeDmft(entries);
});
