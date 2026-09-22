import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/utils/search_normalisation.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';

/// Pure functions that turn repository data into Patients view models.
/// No Flutter, no I/O: easy to test.
abstract final class PatientsBuilder {
  /// One summary per patient, keeping the order of [patients].
  static List<PatientSummary> summaries({
    required List<Patient> patients,
    required List<Visit> visits,
    required DateTime now,
  }) {
    final byPatient = <String, List<Visit>>{};
    for (final v in visits) {
      if (v.isDeleted) continue;
      (byPatient[v.patientId] ??= []).add(v);
    }
    return [
      for (final p in patients) summarize(p, byPatient[p.id] ?? const [], now),
    ];
  }

  static PatientSummary summarize(Patient p, List<Visit> raw, DateTime now) {
    final visits = [...raw.where((v) => !v.isDeleted)]
      ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));

    Visit? last;
    Visit? next;
    Visit? unrecorded;
    Visit? note;
    var completed = 0;
    for (final v in visits) {
      final started = !v.scheduledStart.isAfter(now);
      if (v.status == VisitStatus.completed) {
        completed++;
        if (started) last ??= v;
      }
      if (v.status == VisitStatus.scheduled) {
        if (started) {
          unrecorded ??= v;
        } else {
          next = v; // newest-first order: the last one seen is the soonest
        }
      }
      if (note == null && (v.therapistNotes?.trim().isNotEmpty ?? false)) {
        note = v;
      }
    }
    // A past booking only counts as overdue if nothing was done since.
    final overdue = next == null &&
            unrecorded != null &&
            (last == null ||
                last.scheduledStart.isBefore(unrecorded.scheduledStart))
        ? unrecorded.scheduledStart
        : null;

    final today = _day(now);
    final seenToday = last != null && _day(last.scheduledStart) == today;
    final seen7 = last != null &&
        !_day(last.scheduledStart)
            .isBefore(today.subtract(const Duration(days: 6)));

    return PatientSummary(
      patient: p,
      visits: visits,
      lastVisit: last,
      nextVisit: next,
      overdueSince: overdue,
      completedCount: completed,
      latestNote: note,
      balance: p.packageBalance > 0 ? p.packageBalance : 0,
      isNewThisMonth:
          p.createdAt.year == now.year && p.createdAt.month == now.month,
      seenToday: seenToday,
      seenWithin7Days: seen7,
      inTreatment: completed > 0 && next != null,
    );
  }

  static bool matches(PatientSummary s, PatientFilter f) => switch (f) {
        PatientFilter.all => true,
        PatientFilter.last7Days => s.seenWithin7Days,
        PatientFilter.followUpOverdue => s.followUpOverdue,
        PatientFilter.balanceDue => s.hasBalance,
        PatientFilter.inTreatment => s.inTreatment,
        PatientFilter.newThisMonth => s.isNewThisMonth,
      };

  /// Live chip counts (before search).
  static Map<PatientFilter, int> counts(List<PatientSummary> all) => {
        for (final f in PatientFilter.values)
          f: all.where((s) => matches(s, f)).length,
      };

  /// Name, phone (spaces ignored), patient ID or condition.
  static bool matchesQuery(PatientSummary s, String query) {
    final q = normalizeForSearch(query);
    if (q.isEmpty) return true;
    final p = s.patient;
    if (normalizeForSearch(p.fullName).contains(q)) return true;
    if (normalizeForSearch(p.diagnosisDisplay).contains(q)) return true;
    final t = s.treatment;
    if (t != null && normalizeForSearch(t).contains(q)) return true;
    if (q.length >= 4 && normalizeForSearch(p.id).startsWith(q)) return true;
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 3 &&
        digits.length == q.replaceAll(RegExp(r'[\s+\-()]'), '').length &&
        normalizePhoneDigits(p.phone).contains(normalizePhoneDigits(digits))) {
      return true;
    }
    return false;
  }

  /// The default sort a filter opens with.
  static PatientSort defaultSort(PatientFilter f) => switch (f) {
        PatientFilter.balanceDue => PatientSort.amountDue,
        PatientFilter.followUpOverdue => PatientSort.mostOverdue,
        _ => PatientSort.lastVisit,
      };

  static List<PatientSummary> apply(
    List<PatientSummary> all, {
    required PatientFilter filter,
    required PatientSort sort,
    required String query,
  }) {
    final rows = all
        .where((s) => matches(s, filter) && matchesQuery(s, query))
        .toList();
    int byName(PatientSummary a, PatientSummary b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    int byLast(PatientSummary a, PatientSummary b) {
      final la = a.lastVisit?.scheduledStart;
      final lb = b.lastVisit?.scheduledStart;
      if (la == null && lb == null) {
        return b.patient.createdAt.compareTo(a.patient.createdAt);
      }
      if (la == null) return 1;
      if (lb == null) return -1;
      return lb.compareTo(la);
    }

    rows.sort(switch (sort) {
      PatientSort.lastVisit => byLast,
      PatientSort.name => byName,
      PatientSort.amountDue => (a, b) {
          final c = b.balance.compareTo(a.balance);
          return c != 0 ? c : byName(a, b);
        },
      PatientSort.mostOverdue => (a, b) {
          final oa = a.overdueSince;
          final ob = b.overdueSince;
          if (oa == null && ob == null) return byLast(a, b);
          if (oa == null) return 1;
          if (ob == null) return -1;
          return oa.compareTo(ob);
        },
      PatientSort.newest => (a, b) =>
          b.patient.createdAt.compareTo(a.patient.createdAt),
    });
    return rows;
  }

  /// "Seen today" / "Past 7 days" / "Earlier" when sorted by last visit;
  /// otherwise one untitled group. Empty groups are dropped.
  static List<PatientGroup> group(
    List<PatientSummary> rows,
    PatientSort sort,
  ) {
    if (rows.isEmpty) return const [];
    if (sort != PatientSort.lastVisit) {
      return [PatientGroup(title: null, rows: rows)];
    }
    final today = <PatientSummary>[];
    final week = <PatientSummary>[];
    final earlier = <PatientSummary>[];
    for (final s in rows) {
      (s.seenToday ? today : (s.seenWithin7Days ? week : earlier)).add(s);
    }
    return [
      if (today.isNotEmpty) PatientGroup(title: 'Seen today', rows: today),
      if (week.isNotEmpty) PatientGroup(title: 'Past 7 days', rows: week),
      if (earlier.isNotEmpty) PatientGroup(title: 'Earlier', rows: earlier),
    ];
  }

  static BalanceStripData balanceStrip(List<PatientSummary> rows) =>
      BalanceStripData(
        total: rows.fold(0, (t, s) => t + s.balance),
        patients: rows.where((s) => s.hasBalance).length,
      );

  static FollowUpStripData followUpStrip(
    List<PatientSummary> rows,
    DateTime now,
  ) {
    var longest = 0;
    var n = 0;
    for (final s in rows) {
      final since = s.overdueSince;
      if (since == null) continue;
      n++;
      final d = daysSince(since, now);
      if (d > longest) longest = d;
    }
    return FollowUpStripData(patients: n, longestDays: longest);
  }

  static VisitRowStatus visitStatus(Visit v, DateTime now) =>
      switch (v.status) {
        VisitStatus.completed => VisitRowStatus.done,
        VisitStatus.cancelled => VisitRowStatus.cancelled,
        VisitStatus.missed => VisitRowStatus.missed,
        VisitStatus.scheduled => v.scheduledStart.isAfter(now)
            ? VisitRowStatus.booked
            : VisitRowStatus.notRecorded,
      };

  static int daysSince(DateTime t, DateTime now) =>
      _day(now).difference(_day(t)).inDays;

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// Display strings for the Patients screens.
abstract final class PatientFormat {
  /// "30 · M". Null when the sex isn't recorded.
  static String ageSex(Patient p) {
    final s = sexLetter(p.gender);
    return s == null ? '${p.age}' : '${p.age} · $s';
  }

  /// "30 y · Male".
  static String ageSexLong(Patient p) {
    final s = sexWord(p.gender);
    return s == null ? '${p.age} y' : '${p.age} y · $s';
  }

  static String? sexWord(String gender) {
    final g = gender.trim().toLowerCase();
    if (g.isEmpty || g == 'not specified' || g == 'unknown') return null;
    if (g.startsWith('m')) return 'Male';
    if (g.startsWith('f')) return 'Female';
    return gender.trim()[0].toUpperCase() + gender.trim().substring(1);
  }

  static String? sexLetter(String gender) {
    final w = sexWord(gender);
    return w == null ? null : w[0];
  }

  /// "93215 59182" (5+5 for 10-digit numbers; otherwise as stored).
  static String phone(String raw) {
    final d = normalizePhoneDigits(raw);
    if (d.length == 10) return '${d.substring(0, 5)} ${d.substring(5)}';
    return raw.trim();
  }

  /// "Today", "Tomorrow", "Yesterday" or "Mon 21 Sep".
  static String day(DateTime t, DateTime now) {
    final diff = PatientsBuilder.daysSince(t, now);
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Tomorrow';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEE d MMM').format(t);
  }

  /// "Today · 10:25 AM" / "Mon 21 Sep · 5:30 PM".
  static String dayTime(DateTime t, DateTime now) =>
      '${day(t, now)} · ${DashFormat.time(t)}';

  /// "Fri 16 Oct, 6:00 PM" (inline, after "Next:").
  static String dayTimeInline(DateTime t, DateTime now) =>
      '${day(t, now)}, ${DashFormat.time(t)}';

  /// "7 Sep 2026".
  static String longDate(DateTime t) => DateFormat('d MMM y').format(t);

  /// "Mon 7 Sep".
  static String weekdayDate(DateTime t) => DateFormat('EEE d MMM').format(t);

  /// "SEP" / "30".
  static String month(DateTime t) => DateFormat('MMM').format(t).toUpperCase();
  static String dayOfMonth(DateTime t) => '${t.day}';

  /// "Wed".
  static String weekdayShort(DateTime t) => DateFormat('EEE').format(t);

  static String rupees(double v) => DashFormat.rupees(v);

  /// "12 days" / "1 day".
  static String days(int n) => DashFormat.plural(n, 'day');

  /// Treatment line under the condition: "Scaling · 3 visits".
  static String? treatmentLine(PatientSummary s) {
    final t = s.treatment;
    final n = s.completedCount;
    if (t == null && n == 0) return null;
    final visits = DashFormat.plural(n, 'visit');
    return t == null ? visits : '$t · $visits';
  }

  /// "248 patients · 18 new this month".
  static String headerLine(int total, int newThisMonth) {
    final base = DashFormat.plural(total, 'patient');
    return newThisMonth > 0 ? '$base · $newThisMonth new this month' : base;
  }
}
