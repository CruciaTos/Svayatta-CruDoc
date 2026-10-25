import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';

/// One entry from `access_logs`, reduced to what the analytics count.
class TeamLogEntry {
  const TeamLogEntry({
    required this.actorUid,
    required this.action,
    required this.at,
  });

  final String actorUid;
  final String action;
  final DateTime at;
}

/// What one person did in the clinic over a period.
class MemberStats {
  int booked = 0;
  int attended = 0;
  int completed = 0;
  int checkedIn = 0;
  double collected = 0;
  int invoices = 0;
  int recordsOpened = 0;
  int filesDownloaded = 0;
  DateTime? lastActivity;

  bool get isEmpty =>
      booked == 0 &&
      attended == 0 &&
      checkedIn == 0 &&
      collected == 0 &&
      invoices == 0 &&
      recordsOpened == 0 &&
      filesDownloaded == 0;

  void _seen(DateTime t) {
    final last = lastActivity;
    if (last == null || t.isAfter(last)) lastActivity = t;
  }
}

/// The team's work over [from]..[to], per person and for the whole clinic.
class TeamStats {
  TeamStats._(this.byPerson, this.clinic, this.unattributed);

  /// Keyed by uid.
  final Map<String, MemberStats> byPerson;

  /// Everything in the period, including records nobody is named on.
  final MemberStats clinic;

  /// Records in the period made before the app noted who made them, so
  /// they count for the clinic but for no one person.
  final int unattributed;

  MemberStats of(String uid) => byPerson[uid] ?? MemberStats();

  /// Counts each record once per role it gives someone: who booked a visit
  /// and who attended it are often different people. Deleted records and
  /// cancelled visits don't count. Expenses aren't money collected.
  factory TeamStats.compute({
    required DateTime from,
    required DateTime to,
    Iterable<Visit> visits = const [],
    Iterable<QueueEntry> queue = const [],
    Iterable<RevenueEntry> revenue = const [],
    Iterable<InvoiceModel> invoices = const [],
    Iterable<TeamLogEntry> logs = const [],
  }) {
    final people = <String, MemberStats>{};
    final clinic = MemberStats();
    var unattributed = 0;
    bool inRange(DateTime t) => !t.isBefore(from) && t.isBefore(to);
    MemberStats? person(String uid) =>
        uid.isEmpty ? null : people.putIfAbsent(uid, MemberStats.new);

    for (final v in visits) {
      if (v.isDeleted) continue;
      if (inRange(v.createdAt)) {
        clinic.booked++;
        final p = person(v.createdByUid);
        if (p == null) {
          unattributed++;
        } else {
          p.booked++;
          p._seen(v.createdAt);
        }
      }
      if (v.status == VisitStatus.cancelled || !inRange(v.scheduledStart)) {
        continue;
      }
      final done = v.status == VisitStatus.completed;
      clinic.attended++;
      if (done) clinic.completed++;
      final p = person(v.attendingDoctorUid);
      if (p == null) continue;
      p.attended++;
      if (done) {
        p.completed++;
        p._seen(v.updatedAt);
      }
    }

    for (final q in queue) {
      if (q.isDeleted || !inRange(q.checkedInAt)) continue;
      clinic.checkedIn++;
      final p = person(q.createdByUid);
      if (p == null) {
        unattributed++;
      } else {
        p.checkedIn++;
        p._seen(q.checkedInAt);
      }
    }

    for (final r in revenue) {
      if (r.isDeleted || r.kind != TransactionKind.income || !inRange(r.date)) {
        continue;
      }
      clinic.collected += r.amount;
      final p = person(r.createdByUid);
      if (p == null) {
        unattributed++;
      } else {
        p.collected += r.amount;
        p._seen(r.createdAt);
      }
    }

    for (final i in invoices) {
      if (i.status == 'Cancelled' || !inRange(i.date)) continue;
      clinic.invoices++;
      final p = person(i.createdByUid);
      if (p == null) {
        unattributed++;
      } else {
        p.invoices++;
        p._seen(i.createdAt);
      }
    }

    for (final l in logs) {
      if (!inRange(l.at)) continue;
      final p = person(l.actorUid);
      switch (l.action) {
        case 'patient.view':
          clinic.recordsOpened++;
          p?.recordsOpened++;
        case 'file.download':
          clinic.filesDownloaded++;
          p?.filesDownloaded++;
      }
      p?._seen(l.at);
    }

    return TeamStats._(people, clinic, unattributed);
  }
}
