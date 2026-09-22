import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';

/// Turns repository data into the dashboard's view models.
///
/// Pure: everything it knows comes from its arguments, so it's unit
/// tested directly and the widgets never compute anything themselves.
/// A null source means "still loading"; the sections that need it come
/// back null too.
DashboardData buildDashboard({
  required DateTime now,
  List<QueueEntry>? queue,
  List<Visit>? visits,
  List<Patient>? patients,
  List<RevenueEntry>? revenue,
  List<MedicineModel>? medicines,
  int maxAttentionItems = 3,
}) {
  final today = DateTime(now.year, now.month, now.day);

  List<ScheduleItem>? schedule;
  GlanceData? glance;
  UpNextData? upNext;
  DateTime? nextBooking;

  if (queue != null && visits != null && patients != null) {
    final byId = {for (final p in patients) p.id: p};
    final result = _buildSchedule(
      now: now,
      today: today,
      queue: queue,
      visits: visits,
      patientsById: byId,
    );
    schedule = result.items;
    upNext = result.upNext;
    nextBooking = result.nextBooking;

    final seen = schedule.where((i) => i.status == ScheduleStatus.done).length;
    final open = schedule.where((i) => i.status.isOpen).length;
    final waiting =
        schedule.where((i) => i.status == ScheduleStatus.waiting).toList();
    glance = GlanceData(
      seen: seen,
      total: seen + open,
      waiting: waiting.length,
      averageWaitMinutes: waiting.isEmpty
          ? null
          : (waiting.fold<int>(0, (s, i) => s + (i.waitMinutes ?? 0)) /
                  waiting.length)
              .round(),
    );
  }

  CollectedToday? collected;
  CollectionsData? collections;
  if (revenue != null) {
    final income = revenue.where(
      (e) => !e.isDeleted && e.kind == TransactionKind.income,
    );
    double on(DateTime day) => income
        .where((e) => _sameDay(e.date, day))
        .fold(0.0, (s, e) => s + e.amount);
    final lastWeek = DateTime(today.year, today.month, today.day - 7);
    collected = CollectedToday(
      today: on(today),
      sameDayLastWeek: on(lastWeek),
      weekdayName: DashFormat.weekday(today),
    );
    collections = CollectionsData(days: [
      for (var i = 6; i >= 0; i--)
        () {
          final day = DateTime(today.year, today.month, today.day - i);
          return CollectionDay(date: day, amount: on(day), isToday: i == 0);
        }(),
    ]);
  }

  List<AttentionItem>? attention;
  if (medicines != null) {
    attention = _buildAttention(now, medicines).take(maxAttentionItems).toList();
  }

  return DashboardData(
    now: now,
    glance: glance,
    collected: collected,
    upNext: upNext,
    nextBooking: nextBooking,
    schedule: schedule,
    collections: collections,
    attention: attention,
  );
}

class _ScheduleResult {
  _ScheduleResult(this.items, this.upNext, this.nextBooking);
  final List<ScheduleItem> items;
  final UpNextData? upNext;
  final DateTime? nextBooking;
}

_ScheduleResult _buildSchedule({
  required DateTime now,
  required DateTime today,
  required List<QueueEntry> queue,
  required List<Visit> visits,
  required Map<String, Patient> patientsById,
}) {
  final todayKey = queueDateKeyFor(now);
  final todaysEntries = queue
      .where((e) =>
          !e.isDeleted &&
          e.queueDate == todayKey &&
          e.status != QueueStatus.cancelled)
      .toList();
  final activeVisits = visits.where((v) => !v.isDeleted).toList();
  final visitsById = {for (final v in activeVisits) v.id: v};
  final todaysVisits = activeVisits
      .where((v) =>
          _sameDay(v.scheduledStart, today) &&
          v.status != VisitStatus.cancelled)
      .toList();
  final queuedVisitIds =
      todaysEntries.map((e) => e.linkedVisitId).whereType<String>().toSet();

  // Earlier visits per patient, for "Returning" and "Last visit".
  final earlier = <String, Visit>{};
  for (final v in activeVisits) {
    if (!v.scheduledStart.isBefore(today)) continue;
    if (v.status == VisitStatus.cancelled) continue;
    final prev = earlier[v.patientId];
    if (prev == null || v.scheduledStart.isAfter(prev.scheduledStart)) {
      earlier[v.patientId] = v;
    }
  }

  String? kindFor(Patient? p, Visit? visit) {
    if (visit?.visitType == VisitType.home) return 'Home visit';
    if (p == null) return 'Walk-in';
    return earlier.containsKey(p.id) ? 'Returning' : 'New patient';
  }

  final items = <ScheduleItem>[];

  // A booked visit checked into the queue enters with status "waiting"
  // and checkedInAt = its appointment time, before the patient arrives.
  // There's no arrival timestamp, so it only counts as waiting once that
  // time has passed, and the wait is measured from the appointment time.
  bool arrived(QueueEntry e) =>
      !e.isPrebooked || !e.checkedInAt.isAfter(now);

  for (final e in todaysEntries) {
    final visit = e.linkedVisitId == null ? null : visitsById[e.linkedVisitId];
    final patient = e.patientId == null ? null : patientsById[e.patientId];
    final name = _displayName(patient, e.walkInName);
    final status = switch (e.status) {
      QueueStatus.inConsultation => ScheduleStatus.inConsultation,
      QueueStatus.called => ScheduleStatus.called,
      QueueStatus.completed => ScheduleStatus.done,
      QueueStatus.skipped => ScheduleStatus.skipped,
      QueueStatus.waiting =>
        arrived(e) ? ScheduleStatus.waiting : ScheduleStatus.booked,
      QueueStatus.cancelled => ScheduleStatus.missed, // filtered above
    };
    items.add(ScheduleItem(
      id: 'q_${e.id}',
      time: visit?.scheduledStart ?? e.checkedInAt,
      name: name,
      firstName: _firstName(patient, name),
      status: status,
      ageSex: _ageSex(patient, now),
      reason: _clean(e.reason) ?? _clean(visit?.treatmentType),
      kindLabel: kindFor(patient, visit),
      waitMinutes: status == ScheduleStatus.waiting
          ? _minutesBetween(e.checkedInAt, now)
          : null,
      tokenNumber: e.tokenNumber > 0 ? e.tokenNumber : null,
      patient: patient,
      queueEntryId: e.id,
      visitId: visit?.id ?? e.linkedVisitId,
    ));
  }

  for (final v in todaysVisits) {
    if (queuedVisitIds.contains(v.id)) continue;
    final patient = patientsById[v.patientId];
    final name = _displayName(patient, null);
    items.add(ScheduleItem(
      id: 'v_${v.id}',
      time: v.scheduledStart,
      name: name,
      firstName: _firstName(patient, name),
      status: switch (v.status) {
        VisitStatus.completed => ScheduleStatus.done,
        VisitStatus.missed => ScheduleStatus.missed,
        _ => ScheduleStatus.booked,
      },
      ageSex: _ageSex(patient, now),
      reason: _clean(v.treatmentType),
      kindLabel: kindFor(patient, v),
      patient: patient,
      visitId: v.id,
    ));
  }

  items.sort((a, b) {
    final t = a.time.compareTo(b.time);
    if (t != 0) return t;
    return (a.tokenNumber ?? 0).compareTo(b.tokenNumber ?? 0);
  });

  // Up next: earliest waiting token in exactly the order
  // QueueRepository.callNext uses (urgent first, then token number), so
  // "Start consultation" calls the patient shown.
  int rank(QueueEntry e) => e.priority == QueuePriority.urgent ? 0 : 1;
  int callOrder(QueueEntry a, QueueEntry b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final t = a.tokenNumber.compareTo(b.tokenNumber);
    return t != 0 ? t : a.checkedInAt.compareTo(b.checkedInAt);
  }

  final rawWaiting = todaysEntries
      .where((e) => e.status == QueueStatus.waiting)
      .toList()
    ..sort(callOrder);
  final waiting = rawWaiting.where(arrived).toList();
  final serving = todaysEntries.where((e) => e.isActiveServing).firstOrNull;

  UpNextData? upNext;
  if (waiting.isNotEmpty) {
    final e = waiting.first;
    final patient = e.patientId == null ? null : patientsById[e.patientId];
    final visit = e.linkedVisitId == null ? null : visitsById[e.linkedVisitId];
    final name = _displayName(patient, e.walkInName);
    upNext = UpNextData(
      entryId: e.id,
      name: name,
      tokenNumber: e.tokenNumber > 0 ? e.tokenNumber : null,
      waitMinutes: _minutesBetween(e.checkedInAt, now),
      details: _details(patient, earlier[patient?.id], now),
      reason: _clean(e.reason) ?? _clean(visit?.treatmentType),
      patient: patient,
      isNextInCallOrder: rawWaiting.first.id == e.id,
      servingName: serving == null
          ? null
          : _displayName(
              serving.patientId == null ? null : patientsById[serving.patientId],
              serving.walkInName,
            ),
    );
  }

  final nextBooking = items
      .where((i) => i.status == ScheduleStatus.booked && !i.time.isBefore(now))
      .map((i) => i.time)
      .firstOrNull;

  return _ScheduleResult(items, upNext, nextBooking);
}

Iterable<AttentionItem> _buildAttention(
  DateTime now,
  List<MedicineModel> medicines,
) sync* {
  final active = medicines.where((m) => m.isActive).toList();
  final low = active.where((m) => m.isLowStock).toList()
    ..sort((a, b) {
      double ratio(MedicineModel m) =>
          m.reorderThreshold <= 0 ? 0 : m.currentStock / m.reorderThreshold;
      return ratio(a).compareTo(ratio(b));
    });
  for (final m in low) {
    final unit = m.unit.trim();
    final stock = unit.isEmpty ? '${m.currentStock} left' : '${m.currentStock} $unit';
    yield AttentionItem(
      kind: AttentionKind.lowStock,
      title: m.currentStock <= 0 ? '${m.name} is out of stock' : '${m.name} is low',
      subtitle: '$stock · reorder level ${m.reorderThreshold}',
      actionLabel: 'Reorder',
    );
  }

  // Same 30-day window as MedicineModel.isExpiringSoon, measured from
  // `now` rather than the wall clock so the builder stays pure.
  final lowIds = low.map((m) => m.id).toSet();
  final expiring = active
      .where((m) =>
          m.expiryDate != null &&
          m.expiryDate!.difference(now).inDays <= 30 &&
          !lowIds.contains(m.id))
      .toList()
    ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
  for (final m in expiring) {
    final days = _calendarDaysBetween(now, m.expiryDate!);
    final when = days < 0
        ? 'expired ${DashFormat.plural(-days, 'day')} ago'
        : days == 0
            ? 'expires today'
            : 'expires in ${DashFormat.plural(days, 'day')}';
    final unit = m.unit.trim();
    yield AttentionItem(
      kind: AttentionKind.expiring,
      title: '${m.name} $when',
      subtitle: unit.isEmpty
          ? '${m.currentStock} in stock'
          : '${m.currentStock} $unit in stock',
      actionLabel: 'Review',
    );
  }
}

String _details(Patient? p, Visit? last, DateTime now) {
  if (p == null) return 'Walk-in · not registered';
  final parts = <String>[
    '${_age(p.dateOfBirth, now)} y',
    if (_sexWord(p.gender) != null) _sexWord(p.gender)!,
  ];
  if (last == null) {
    parts.addAll(['New patient', 'First visit']);
  } else {
    final diagnosis = p.diagnosis.isEmpty ? null : p.diagnosis.last.trim();
    parts.add('Returning');
    parts.add(
      diagnosis == null || diagnosis.isEmpty
          ? 'Last visit ${DashFormat.shortDate(last.scheduledStart)}'
          : 'Last visit ${DashFormat.shortDate(last.scheduledStart)}, $diagnosis',
    );
  }
  return parts.join(' · ');
}

String _displayName(Patient? p, String? walkInName) {
  final name = p?.fullName.trim() ?? '';
  if (name.isNotEmpty) return name;
  final walkIn = walkInName?.trim() ?? '';
  return walkIn.isNotEmpty ? walkIn : 'Walk-in';
}

String _firstName(Patient? p, String displayName) {
  final first = p?.firstName.trim() ?? '';
  if (first.isNotEmpty) return first;
  return displayName.split(RegExp(r'\s+')).first;
}

String? _ageSex(Patient? p, DateTime now) {
  if (p == null) return null;
  final sex = _sexLetter(p.gender);
  final age = _age(p.dateOfBirth, now);
  return sex == null ? '$age' : '$age $sex';
}

int _age(DateTime dob, DateTime now) {
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age < 0 ? 0 : age;
}

String? _sexWord(String gender) {
  final g = gender.trim().toLowerCase();
  if (g.isEmpty) return null;
  if (g.startsWith('m')) return 'Male';
  if (g.startsWith('f')) return 'Female';
  return gender.trim();
}

String? _sexLetter(String gender) {
  final word = _sexWord(gender);
  return word == null ? null : word[0].toUpperCase();
}

String? _clean(String? s) {
  final t = s?.trim() ?? '';
  return t.isEmpty ? null : t;
}

int _minutesBetween(DateTime from, DateTime to) {
  final m = to.difference(from).inMinutes;
  return m < 0 ? 0 : m;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole calendar days from [from] to [to], immune to daylight-saving
/// shifts (compared as UTC dates).
int _calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
