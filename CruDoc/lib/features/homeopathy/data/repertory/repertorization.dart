import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/repertory_engine.dart';

/// A repertorization saved for a patient (record kind
/// `homeoRepertorization`): the rubrics picked with their weights, a note,
/// and optionally the remedy the physician chose from the grid.
///
/// Nothing here is written to the case sheet.
class Repertorization {
  const Repertorization({
    required this.id,
    required this.patientId,
    required this.rubrics,
    required this.note,
    required this.chosenRemedy,
    required this.date,
    required this.record,
  });

  factory Repertorization.fromRecord(DentalRecord r) {
    final raw = r.data['rubrics'];
    final chosen = r.str('chosenRemedy').trim();
    return Repertorization(
      id: r.id,
      patientId: r.patientId,
      rubrics: [
        if (raw is List)
          for (final e in raw) ?SelectedRubric.fromJson(e),
      ],
      note: r.str('note'),
      chosenRemedy: chosen.isEmpty ? null : chosen,
      date: r.recordedAt,
      record: r,
    );
  }

  final String id;
  final String patientId;
  final List<SelectedRubric> rubrics;
  final String note;

  /// A remedy abbreviation, e.g. "Puls."; null when none was chosen.
  final String? chosenRemedy;
  final DateTime date;
  final DentalRecord record;

  /// Recomputed from the bundled data each time, so a corrected rubric
  /// corrects old results too.
  RepertorizationResult get result => repertorize(rubrics);

  static Map<String, dynamic> toData({
    required List<SelectedRubric> rubrics,
    required String note,
    String? chosenRemedy,
  }) => {
    'rubrics': [for (final r in rubrics) r.toJson()],
    'note': note,
    if (chosenRemedy != null && chosenRemedy.isNotEmpty)
      'chosenRemedy': chosenRemedy,
  };
}
