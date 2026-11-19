import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

/// One pain and function score (record kind `physioProgress`).
class ProgressEntry {
  const ProgressEntry({
    required this.record,
    required this.pain,
    required this.worst,
    required this.function,
    required this.note,
  });

  factory ProgressEntry.fromRecord(DentalRecord r) => ProgressEntry(
    record: r,
    pain: r.integer('pain') ?? 0,
    worst: r.integer('worst') ?? 0,
    function: r.integer('function') ?? 0,
    note: r.str('note'),
  );

  final DentalRecord record;
  final int pain;
  final int worst;
  final int function;
  final String note;

  DateTime get date => record.recordedAt;

  static Map<String, dynamic> toData({
    required int pain,
    required int worst,
    required int function,
    required String note,
  }) => {'pain': pain, 'worst': worst, 'function': function, 'note': note};
}

/// Oldest first.
List<ProgressEntry> progressEntries(Iterable<DentalRecord> recs) =>
    [for (final r in recs) ProgressEntry.fromRecord(r)]
      ..sort((a, b) => a.date.compareTo(b.date));

/// A region and its standard movements, with textbook normal ranges (AAOS).
class RomRegion {
  const RomRegion(this.id, this.label, this.moves);

  final String id;
  final String label;
  final List<RomMove> moves;
}

class RomMove {
  const RomMove(this.name, this.normal);

  final String name;

  /// Normal range in degrees, shown as a faint hint.
  final int normal;
}

const List<RomRegion> kRomRegions = [
  RomRegion('neck', 'Neck', [
    RomMove('Flexion', 45),
    RomMove('Extension', 45),
    RomMove('Lateral flexion', 45),
    RomMove('Rotation', 60),
  ]),
  RomRegion('shoulder', 'Shoulder', [
    RomMove('Flexion', 180),
    RomMove('Extension', 60),
    RomMove('Abduction', 180),
    RomMove('Internal rotation', 70),
    RomMove('External rotation', 90),
  ]),
  RomRegion('elbow', 'Elbow', [
    RomMove('Flexion', 150),
    RomMove('Extension', 0),
    RomMove('Supination', 80),
    RomMove('Pronation', 80),
  ]),
  RomRegion('wrist', 'Wrist', [
    RomMove('Flexion', 80),
    RomMove('Extension', 70),
    RomMove('Radial deviation', 20),
    RomMove('Ulnar deviation', 30),
  ]),
  RomRegion('hip', 'Hip', [
    RomMove('Flexion', 120),
    RomMove('Extension', 30),
    RomMove('Abduction', 45),
    RomMove('Adduction', 30),
    RomMove('Internal rotation', 45),
    RomMove('External rotation', 45),
  ]),
  RomRegion('knee', 'Knee', [RomMove('Flexion', 135), RomMove('Extension', 0)]),
  RomRegion('ankle', 'Ankle', [
    RomMove('Dorsiflexion', 20),
    RomMove('Plantarflexion', 50),
    RomMove('Inversion', 35),
    RomMove('Eversion', 15),
  ]),
  RomRegion('lumbar', 'Lumbar spine', [
    RomMove('Flexion', 60),
    RomMove('Extension', 25),
    RomMove('Lateral flexion', 25),
    RomMove('Rotation', 30),
  ]),
];

RomRegion romRegionById(String id) =>
    kRomRegions.firstWhere((r) => r.id == id, orElse: () => kRomRegions.first);

/// Values for one movement; any can be null.
class RomRow {
  const RomRow({
    required this.move,
    this.lDeg,
    this.rDeg,
    this.lMmt,
    this.rMmt,
  });

  factory RomRow.fromJson(Map<String, dynamic> j) => RomRow(
    move: j['move'] as String? ?? '',
    lDeg: (j['lDeg'] as num?)?.toInt(),
    rDeg: (j['rDeg'] as num?)?.toInt(),
    lMmt: (j['lMmt'] as num?)?.toInt(),
    rMmt: (j['rMmt'] as num?)?.toInt(),
  );

  final String move;
  final int? lDeg;
  final int? rDeg;
  final int? lMmt;
  final int? rMmt;

  bool get isEmpty =>
      lDeg == null && rDeg == null && lMmt == null && rMmt == null;

  Map<String, dynamic> toJson() => {
    'move': move,
    'lDeg': ?lDeg,
    'rDeg': ?rDeg,
    'lMmt': ?lMmt,
    'rMmt': ?rMmt,
  };
}

/// A dated ROM and strength assessment of one region (kind `physioRom`).
class RomAssessment {
  const RomAssessment({
    required this.record,
    required this.regionId,
    required this.rows,
    required this.note,
  });

  factory RomAssessment.fromRecord(DentalRecord r) {
    final raw = r.data['rows'];
    return RomAssessment(
      record: r,
      regionId: r.str('region'),
      rows: [
        if (raw is List)
          for (final e in raw)
            if (e is Map) RomRow.fromJson(Map<String, dynamic>.from(e)),
      ],
      note: r.str('note'),
    );
  }

  final DentalRecord record;
  final String regionId;
  final List<RomRow> rows;
  final String note;

  DateTime get date => record.recordedAt;

  RomRow? row(String move) => rows.where((r) => r.move == move).firstOrNull;
}

/// Newest first.
List<RomAssessment> romAssessments(Iterable<DentalRecord> recs) =>
    [for (final r in recs) RomAssessment.fromRecord(r)]
      ..sort((a, b) => b.date.compareTo(a.date));
