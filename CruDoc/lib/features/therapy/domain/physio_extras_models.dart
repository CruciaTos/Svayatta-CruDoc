import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/physio_flags.dart';

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
    required this.invoiceId,
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
      invoiceId: r.str('invoiceId'),
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

  /// The invoice raised when the package was sold, or empty when it has not
  /// been billed yet. A package is paid for up front and the sessions draw
  /// it down, so there is one invoice per package, not one per session.
  final String invoiceId;

  /// Whether the sale has been invoiced.
  bool get billed => invoiceId.trim().isNotEmpty;

  /// Worth billing: sold for a price, and no invoice raised for it yet.
  bool get needsInvoice => !billed && (price ?? 0) > 0;

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
    if (billed) 'invoiceId': invoiceId,
    'used': [for (final u in used) u.millisecondsSinceEpoch],
  };

  /// A copy of the record data with [id] recorded as the package's invoice.
  Map<String, dynamic> dataWithInvoice(String id) => {
    ...record.data,
    'invoiceId': id,
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

/// Where a goal ended up.
enum GoalStatus {
  open('Working on it'),
  reached('Reached'),
  missed('Not reached');

  const GoalStatus(this.label);
  final String label;

  static GoalStatus fromName(String n) =>
      values.firstWhere((v) => v.name == n, orElse: () => open);
}

/// One thing the patient is working towards, by a date (record kind
/// `physioGoal`).
///
/// Written by the physio in the patient's own terms — "climb the stairs at
/// home without the rail" rather than "improve knee flexion" — because the
/// goal is what the patient came for, and it is what the discharge summary
/// reports against.
class PhysioGoal {
  const PhysioGoal({
    required this.text,
    required this.target,
    required this.status,
    required this.note,
    required this.record,
  });

  factory PhysioGoal.fromRecord(DentalRecord r) => PhysioGoal(
    text: r.str('text'),
    target: r.date('target'),
    status: GoalStatus.fromName(r.str('status')),
    note: r.str('note'),
    record: r,
  );

  final String text;

  /// The day it is meant to be reached by. Null when the physio set none:
  /// a goal without a date is still a goal, it just cannot run late.
  final DateTime? target;
  final GoalStatus status;
  final String note;
  final DentalRecord record;

  String get id => record.id;
  DateTime get setOn => record.recordedAt;

  bool get isOpen => status == GoalStatus.open;

  /// Still open with its date gone by. Worth raising at the next visit,
  /// which is the whole point of putting a date on it.
  bool overdue(DateTime now) {
    final t = target;
    if (!isOpen || t == null) return false;
    return DateTime(t.year, t.month, t.day).isBefore(
      DateTime(now.year, now.month, now.day),
    );
  }

  /// Days until the target, negative once it has passed. Null without one.
  int? daysLeft(DateTime now) {
    final t = target;
    if (t == null) return null;
    return DateTime(
      t.year,
      t.month,
      t.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  static Map<String, dynamic> toData({
    required String text,
    required DateTime? target,
    required GoalStatus status,
    required String note,
  }) => {
    'text': text,
    if (target != null) 'target': target.millisecondsSinceEpoch,
    'status': status.name,
    'note': note,
  };
}

/// A patient's goals: still open first (soonest target leading), then the
/// ones already settled, newest first. What is still to do comes before what
/// is already done.
List<PhysioGoal> physioGoals(Iterable<DentalRecord> recs) {
  final all = [for (final r in recs) PhysioGoal.fromRecord(r)];
  final open = [for (final g in all) if (g.isOpen) g]
    ..sort((a, b) {
      final at = a.target, bt = b.target;
      if (at == null && bt == null) return b.setOn.compareTo(a.setOn);
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
  final done = [for (final g in all) if (!g.isOpen) g]
    ..sort((a, b) => b.setOn.compareTo(a.setOn));
  return [...open, ...done];
}

/// Goals whose target date has gone by with nobody deciding on them.
///
/// The point of putting a date on a goal is that somebody is asked about it
/// when the date arrives.
List<PhysioGoal> goalsDueForReview(List<PhysioGoal> goals, DateTime now) => [
  for (final g in goals)
    if (g.overdue(now)) g,
];

/// A line for the discharge summary: how the goals ended up.
///
/// Null when no goal was ever settled, so an episode of care where nobody
/// decided says nothing at all rather than claiming "0 reached".
String? goalOutcomeLine(List<PhysioGoal> goals) {
  final reached = [
    for (final g in goals)
      if (g.status == GoalStatus.reached) g,
  ];
  final missed = [
    for (final g in goals)
      if (g.status == GoalStatus.missed) g,
  ];
  if (reached.isEmpty && missed.isEmpty) return null;
  final parts = [
    if (reached.isNotEmpty) '${reached.length} reached',
    if (missed.isNotEmpty) '${missed.length} not reached',
  ];
  return 'Goals: ${parts.join(', ')}';
}

/// What the physio found when they asked about one flag.
///
/// [notAsked] is its own answer and not the same as [absent]: a record that
/// cannot tell the difference between "I asked and it is not there" and "we
/// never got to it" is worse than useless on the one that matters.
enum FlagAnswer {
  notAsked,
  absent,
  present;

  static FlagAnswer fromName(String n) =>
      values.firstWhere((v) => v.name == n, orElse: () => notAsked);
}

/// A patient's intake screening (record kind `physioScreening`).
class PhysioScreening {
  const PhysioScreening({
    required this.answers,
    required this.note,
    required this.record,
  });

  factory PhysioScreening.fromRecord(DentalRecord r) {
    final raw = r.data['flags'];
    return PhysioScreening(
      answers: {
        if (raw is Map)
          for (final e in raw.entries)
            '${e.key}': FlagAnswer.fromName('${e.value}'),
      },
      note: r.str('note'),
      record: r,
    );
  }

  /// Flag id to what was found. A flag missing from the map was not asked.
  final Map<String, FlagAnswer> answers;
  final String note;
  final DentalRecord? record;

  DateTime? get at => record?.recordedAt;

  FlagAnswer answerFor(String id) => answers[id] ?? FlagAnswer.notAsked;

  /// Ids answered [FlagAnswer.present], in [kPhysioFlags] order so the
  /// banner reads the same way every time.
  List<PhysioFlag> presentOf(FlagKind kind) => [
    for (final f in kPhysioFlags)
      if (f.kind == kind && answerFor(f.id) == FlagAnswer.present) f,
  ];

  /// Something serious was found. The one thing the patient's page has to
  /// say before anything else.
  bool get hasRed => presentOf(FlagKind.red).isNotEmpty;

  bool get hasYellow => presentOf(FlagKind.yellow).isNotEmpty;

  /// How many of the flags have been asked about at all.
  int get asked => [
    for (final f in kPhysioFlags)
      if (answerFor(f.id) != FlagAnswer.notAsked) f,
  ].length;

  bool get started => asked > 0;

  /// Flags nobody has asked about yet.
  int get unanswered => kPhysioFlags.length - asked;

  static Map<String, dynamic> toData({
    required Map<String, FlagAnswer> answers,
    required String note,
  }) => {
    'flags': {
      for (final e in answers.entries)
        if (e.value != FlagAnswer.notAsked) e.key: e.value.name,
    },
    'note': note,
  };
}

/// The newest screening among [recs], or an empty one when there is none.
PhysioScreening screeningOf(Iterable<DentalRecord> recs) {
  final sorted = [...recs]
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  final r = sorted.firstOrNull;
  return r == null
      ? const PhysioScreening(answers: {}, note: '', record: null)
      : PhysioScreening.fromRecord(r);
}

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
