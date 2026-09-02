import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle states for a single walk-in queue token.
///
/// `waiting` -> `called` -> `inConsultation` -> `completed` is the happy
/// path. `skipped` is a called token whose patient wasn't present — see
/// [QueueRepository.skip]/[QueueRepository.requeue]. `cancelled` is a
/// dead end for a token that's done for the day without being seen.
///
/// Deliberately an enum rather than a free-text string, so an invalid
/// status can never be written from within the app — see
/// [QueueStatus.fromValue] for how unrecognized Firestore data is
/// handled defensively on the read side. Mirrors [VisitStatus]'s shape
/// in visits_model.dart.
enum QueueStatus {
  waiting,
  called,
  inConsultation,
  completed,
  skipped,
  cancelled;

  /// The exact string stored in Firestore/SQLite for this status.
  String get value => name;

  /// Parses a raw stored string into a [QueueStatus]. Falls back to
  /// [QueueStatus.waiting] for anything unrecognized (missing field,
  /// legacy data, a manual Firestore console edit) rather than
  /// throwing, so one corrupted document can't crash an entire queue.
  static QueueStatus fromValue(String? raw) {
    return QueueStatus.values.firstWhere(
      (status) => status.value == raw,
      orElse: () => QueueStatus.waiting,
    );
  }
}

/// How urgently a token should be seen relative to others waiting.
///
/// Only two levels on purpose — a walk-in queue needs "this one jumps
/// the line" more than a fine-grained priority scale. [QueueRepository]
/// sorts every `urgent` token ahead of every `normal` token, breaking
/// ties by [QueueEntry.tokenNumber].
enum QueuePriority {
  normal,
  urgent;

  String get value => name;

  static QueuePriority fromValue(String? raw) {
    return QueuePriority.values.firstWhere(
      (priority) => priority.value == raw,
      orElse: () => QueuePriority.normal,
    );
  }
}

/// Builds the local-calendar-date key ('yyyy-MM-dd') a queue token
/// belongs to. Token numbers reset to 1 on the next date — a token from
/// yesterday never collides with, or shows up in, today's queue.
///
/// Deliberately based on [DateTime]'s local getters (not UTC) so the
/// queue resets at local midnight, matching when a clinic's day
/// actually turns over.
String queueDateKeyFor(DateTime moment) {
  final year = moment.year.toString().padLeft(4, '0');
  final month = moment.month.toString().padLeft(2, '0');
  final day = moment.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// A single walk-in queue token.
///
/// Represents one patient's place in a given day's walk-in line, stored
/// in the `walk_in_queue` Firestore collection / SQLite table.
///
/// A token belongs to either a registered patient ([patientId] set) or
/// an unregistered walk-in captured on the spot ([walkInName] set) —
/// never both, never neither. [QueueRepository.checkIn] enforces this.
/// Like [Visit], this deliberately never stores the linked patient's
/// name/phone itself — those are looked up by id when needed for
/// display (see `QueueEntryWithPatient` in queue_providers.dart), so
/// there is exactly one place they can go stale.
class QueueEntry {
  final String id;

  /// UID of the doctor this token belongs to — scoped the same way as
  /// [Patient.doctorId] / [Visit.doctorId].
  final String doctorId;

  /// Id of the registered patient this token is for, or null when this
  /// is an unregistered walk-in — see [walkInName]/[walkInPhone].
  final String? patientId;

  /// Name captured at check-in for a walk-in who isn't (yet) a
  /// registered patient. Null when [patientId] is set.
  final String? walkInName;

  /// Phone captured at check-in for a walk-in. Optional even for a
  /// walk-in — a name is enough to hold a place in line.
  final String? walkInPhone;

  /// The number shown to the patient and called out by the doctor.
  /// Starts at 1 each [queueDate] and is unique within that date.
  /// Assigned atomically by `QueueLocalService.checkIn` — never set by
  /// hand, so pass any value (e.g. 0) when constructing a token to
  /// check in.
  final int tokenNumber;

  /// The local calendar date (see [queueDateKeyFor]) this token
  /// belongs to.
  final String queueDate;

  final QueueStatus status;
  final QueuePriority priority;

  /// Optional short note captured at check-in (e.g. "fever", "follow-up
  /// dressing change") to help with triage while waiting.
  final String? reason;

  final DateTime checkedInAt;

  /// When this token was called to be seen. Null until
  /// [QueueRepository.callNext] calls it.
  final DateTime? calledAt;

  /// When the consultation actually started. Null until
  /// [QueueRepository.startConsultation].
  final DateTime? consultationStartedAt;

  /// When this token's visit was marked done. Null until
  /// [QueueRepository.complete].
  final DateTime? completedAt;

  // ---- Future-proofing field ----
  // Nullable and unused today. Exists so a completed queue token can
  // later be linked to a proper [Visit] record for billing/history
  // without a schema migration — same idiom as Visit's own
  // future-proofing fields.
  final String? linkedVisitId;

  /// True once this token has been soft-deleted (e.g. created by
  /// mistake). Hidden from every default query, but the document is
  /// never removed — matches [Visit.isDeleted].
  final bool isDeleted;

  final DateTime createdAt;
  final DateTime updatedAt;

  const QueueEntry({
    required this.id,
    this.doctorId = '',
    this.patientId,
    this.walkInName,
    this.walkInPhone,
    required this.tokenNumber,
    required this.queueDate,
    required this.status,
    this.priority = QueuePriority.normal,
    this.reason,
    required this.checkedInAt,
    this.calledAt,
    this.consultationStartedAt,
    this.completedAt,
    this.linkedVisitId,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// True for [QueueStatus.called] or [QueueStatus.inConsultation] —
  /// the one token actively being served, if any.
  bool get isActiveServing =>
      status == QueueStatus.called || status == QueueStatus.inConsultation;

  /// Builds a [QueueEntry] from a Firestore document snapshot.
  factory QueueEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return QueueEntry.fromMap(data, id: doc.id);
  }

  /// Builds a [QueueEntry] from a raw map (e.g. Firestore data payload).
  factory QueueEntry.fromMap(Map<String, dynamic> map, {required String id}) {
    return QueueEntry(
      id: id,
      doctorId: map['doctorId'] as String? ?? '',
      patientId: map['patientId'] as String?,
      walkInName: map['walkInName'] as String?,
      walkInPhone: map['walkInPhone'] as String?,
      tokenNumber: (map['tokenNumber'] as num?)?.toInt() ?? 0,
      queueDate: map['queueDate'] as String? ?? '',
      status: QueueStatus.fromValue(map['status'] as String?),
      priority: QueuePriority.fromValue(map['priority'] as String?),
      reason: map['reason'] as String?,
      checkedInAt: _timestampToDate(map['checkedInAt']),
      calledAt: _nullableTimestampToDate(map['calledAt']),
      consultationStartedAt: _nullableTimestampToDate(
        map['consultationStartedAt'],
      ),
      completedAt: _nullableTimestampToDate(map['completedAt']),
      linkedVisitId: map['linkedVisitId'] as String?,
      isDeleted: map['isDeleted'] as bool? ?? false,
      createdAt: _timestampToDate(map['createdAt']),
      updatedAt: _timestampToDate(map['updatedAt']),
    );
  }

  /// Converts this [QueueEntry] into a Firestore-writable map. The
  /// document id is not included, since it is the document key.
  Map<String, dynamic> toMap() {
    return {
      'doctorId': doctorId,
      'patientId': patientId,
      'walkInName': walkInName,
      'walkInPhone': walkInPhone,
      'tokenNumber': tokenNumber,
      'queueDate': queueDate,
      'status': status.value,
      'priority': priority.value,
      'reason': reason,
      'checkedInAt': Timestamp.fromDate(checkedInAt),
      'calledAt': calledAt == null ? null : Timestamp.fromDate(calledAt!),
      'consultationStartedAt': consultationStartedAt == null
          ? null
          : Timestamp.fromDate(consultationStartedAt!),
      'completedAt': completedAt == null
          ? null
          : Timestamp.fromDate(completedAt!),
      'linkedVisitId': linkedVisitId,
      'isDeleted': isDeleted,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  QueueEntry copyWith({
    String? patientId,
    String? walkInName,
    String? walkInPhone,
    int? tokenNumber,
    String? queueDate,
    QueueStatus? status,
    QueuePriority? priority,
    String? reason,
    DateTime? checkedInAt,
    DateTime? calledAt,
    DateTime? consultationStartedAt,
    DateTime? completedAt,
    String? linkedVisitId,
    bool? isDeleted,
    DateTime? updatedAt,
  }) {
    return QueueEntry(
      id: id,
      doctorId: doctorId,
      patientId: patientId ?? this.patientId,
      walkInName: walkInName ?? this.walkInName,
      walkInPhone: walkInPhone ?? this.walkInPhone,
      tokenNumber: tokenNumber ?? this.tokenNumber,
      queueDate: queueDate ?? this.queueDate,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      reason: reason ?? this.reason,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      calledAt: calledAt ?? this.calledAt,
      consultationStartedAt: consultationStartedAt ?? this.consultationStartedAt,
      completedAt: completedAt ?? this.completedAt,
      linkedVisitId: linkedVisitId ?? this.linkedVisitId,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _timestampToDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  static DateTime? _nullableTimestampToDate(dynamic value) {
    if (value == null) return null;
    return _timestampToDate(value);
  }
}
