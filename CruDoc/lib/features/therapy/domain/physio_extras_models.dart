import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

/// A prepaid or planned session package (record kind `physioPackage`).
class SessionPackage {
  const SessionPackage({
    required this.record,
    required this.name,
    required this.total,
    required this.price,
    required this.validUntil,
    required this.note,
    required this.used,
  });

  factory SessionPackage.fromRecord(DentalRecord r) {
    final raw = r.data['used'];
    return SessionPackage(
      record: r,
      name: r.str('name'),
      total: r.integer('total') ?? 0,
      price: r.number('price'),
      validUntil: r.date('validUntil'),
      note: r.str('note'),
      used: [
        if (raw is List)
          for (final e in raw)
            if (e is num) DateTime.fromMillisecondsSinceEpoch(e.toInt()),
      ]..sort(),
    );
  }

  final DentalRecord record;
  final String name;
  final int total;
  final double? price;
  final DateTime? validUntil;
  final String note;

  /// Oldest first.
  final List<DateTime> used;

  DateTime get date => record.recordedAt;
  int get left => (total - used.length).clamp(0, total);
  bool get completed => left == 0;

  bool get expired {
    final v = validUntil;
    if (v == null) return false;
    final today = DateTime.now();
    return DateTime(
      v.year,
      v.month,
      v.day,
    ).isBefore(DateTime(today.year, today.month, today.day));
  }

  /// Two or fewer sessions left (and not finished).
  bool get low => !completed && left <= 2;

  Map<String, dynamic> toData() => {
    'name': name,
    'total': total,
    'price': ?price,
    if (validUntil != null) 'validUntil': validUntil!.millisecondsSinceEpoch,
    'note': note,
    'used': [for (final u in used) u.millisecondsSinceEpoch],
  };

  /// A copy with [at] added to the usage list.
  Map<String, dynamic> dataWithUse(DateTime at) => {
    ...record.data,
    'used': [for (final u in [...used, at]) u.millisecondsSinceEpoch],
  };

  /// A copy of the record data with one usage removed.
  Map<String, dynamic> dataWithoutUse(DateTime at) => {
    ...record.data,
    'used': [
      for (final u in used)
        if (u != at) u.millisecondsSinceEpoch,
    ],
  };
}

/// Newest first.
List<SessionPackage> sessionPackages(Iterable<DentalRecord> recs) =>
    [for (final r in recs) SessionPackage.fromRecord(r)]
      ..sort((a, b) => b.date.compareTo(a.date));

/// The result of one special test (record kind `physioTestResult`).
class TestResult {
  const TestResult({
    required this.record,
    required this.testId,
    required this.side,
    required this.result,
    required this.note,
  });

  factory TestResult.fromRecord(DentalRecord r) => TestResult(
    record: r,
    testId: r.str('testId'),
    side: r.str('side'),
    result: r.str('result'),
    note: r.str('note'),
  );

  final DentalRecord record;
  final String testId;

  /// `left`, `right` or `both`.
  final String side;

  /// `positive`, `negative` or `notDone`.
  final String result;
  final String note;

  DateTime get date => record.recordedAt;

  static Map<String, dynamic> toData({
    required String testId,
    required String side,
    required String result,
    required String note,
  }) => {'testId': testId, 'side': side, 'result': result, 'note': note};

  static String sideLabel(String side) => switch (side) {
    'left' => 'Left',
    'right' => 'Right',
    _ => 'Both sides',
  };

  static String resultLabel(String result) => switch (result) {
    'positive' => 'Positive',
    'negative' => 'Negative',
    _ => 'Not done',
  };
}

/// Newest first.
List<TestResult> testResults(Iterable<DentalRecord> recs) =>
    [for (final r in recs) TestResult.fromRecord(r)]
      ..sort((a, b) => b.date.compareTo(a.date));
