import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a [RevenueEntry]'s money came from.
///
/// Deliberately an enum rather than a free-text string, so an invalid
/// type can never be written from within the app — see
/// [RevenueType.fromValue] for how unrecognized Firestore data is
/// handled defensively on the read side.
enum RevenueType {
  visit,
  online,
  miscellaneous;

  /// The exact string stored in Firestore for this type.
  String get value => name;

  /// Parses a raw Firestore string into a [RevenueType]. Falls back to
  /// [RevenueType.miscellaneous] for anything unrecognized (missing
  /// field, legacy data, a manual Firestore console edit) rather than
  /// throwing, so one corrupted document can't crash an entire revenue
  /// list.
  static RevenueType fromValue(String? raw) {
    return RevenueType.values.firstWhere(
      (type) => type.value == raw,
      orElse: () => RevenueType.miscellaneous,
    );
  }
}

/// Whether a [RevenueEntry] represents money coming in or going out.
///
/// Same shape as [RevenueType] — an enum with a string value and a
/// defensive `fromValue` that falls back to [TransactionKind.income]
/// for missing or unrecognised data, so one bad Firestore document
/// can’t crash the revenue list.
enum TransactionKind {
  income,
  expense;

  /// The exact string stored in Firestore for this kind.
  String get value => name;

  /// Parses a raw Firestore string into a [TransactionKind]. Falls back
  /// to [TransactionKind.income] for anything unrecognized.
  static TransactionKind fromValue(String? raw) {
    return TransactionKind.values.firstWhere(
      (kind) => kind.value == raw,
      orElse: () => TransactionKind.income,
    );
  }
}

/// Core Revenue Entry data model.
///
/// Represents a single recorded payment stored in the `revenue_entries`
/// Firestore collection — money that has actually been received,
/// whether from an in-person [RevenueType.visit], an
/// [RevenueType.online] session, or a [RevenueType.miscellaneous]
/// source (e.g. equipment resale, or a settled [PendingPayment]).
///
/// Written as a plain, hand-rolled model (no freezed/json_serializable)
/// to match [Patient] and [Visit]'s style.
class RevenueEntry {
  final String id;

  /// The date this payment was recorded/received.
  final DateTime date;
  final String description;
  final double amount;
  final RevenueType type;

  /// Display name of who paid, e.g. a patient's full name. Kept as
  /// free text rather than a foreign key today, matching the
  /// presentation layer's current usage. Null for entries with no
  /// single identifiable payer (e.g. miscellaneous income).
  final String? payer;

  // ---- Future-proofing fields ----
  // Both nullable and unused today. They exist so a revenue entry can
  // be traced back to the patient and visit that generated it, once
  // that wiring is built, without a schema migration or a breaking
  // model change.
  final String? patientId;
  final String? visitId;

  /// True once this entry has been soft-deleted (e.g. it was recorded
  /// by mistake). A soft-deleted entry is hidden from every default
  /// query, but the document itself is never removed from Firestore —
  /// history is fully preserved.
  final bool isDeleted;

  /// Whether this entry is income (money in) or expense (money out).
  /// Defaults to [TransactionKind.income] so every existing call site
  /// remains non‑breaking.
  final TransactionKind kind;

  final DateTime createdAt;
  final DateTime updatedAt;

  const RevenueEntry({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.payer,
    this.patientId,
    this.visitId,
    this.isDeleted = false,
    this.kind = TransactionKind.income,
  });

  /// Builds a [RevenueEntry] from a Firestore document snapshot.
  factory RevenueEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return RevenueEntry.fromMap(data, id: doc.id);
  }

  /// Builds a [RevenueEntry] from a raw map (e.g. Firestore data payload).
  factory RevenueEntry.fromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    return RevenueEntry(
      id: id,
      date: _timestampToDate(map['date']),
      description: map['description'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      type: RevenueType.fromValue(map['type'] as String?),
      kind: TransactionKind.fromValue(map['kind'] as String?),
      payer: map['payer'] as String?,
      patientId: map['patientId'] as String?,
      visitId: map['visitId'] as String?,
      isDeleted: map['isDeleted'] as bool? ?? false,
      createdAt: _timestampToDate(map['createdAt']),
      updatedAt: _timestampToDate(map['updatedAt']),
    );
  }

  /// Converts this [RevenueEntry] into a Firestore-writable map. The
  /// document id is not included, since it is the document key.
  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'description': description,
      'amount': amount,
      'type': type.value,
      'kind': kind.value,
      'payer': payer,
      'patientId': patientId,
      'visitId': visitId,
      'isDeleted': isDeleted,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  RevenueEntry copyWith({
    DateTime? date,
    String? description,
    double? amount,
    RevenueType? type,
    String? payer,
    String? patientId,
    String? visitId,
    bool? isDeleted,
    TransactionKind? kind,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RevenueEntry(
      id: id,
      date: date ?? this.date,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      payer: payer ?? this.payer,
      patientId: patientId ?? this.patientId,
      visitId: visitId ?? this.visitId,
      isDeleted: isDeleted ?? this.isDeleted,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _timestampToDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}

/// Core Pending Payment data model.
///
/// Represents money that is owed but not yet received, stored in the
/// `pending_payments` Firestore collection — e.g. a lab test or
/// consultation the patient hasn't paid for yet. Once collected, call
/// `RevenueRepository.markPendingPaymentAsPaid` to mark it [isPaid] and
/// create the matching [RevenueEntry] in one step — the pending
/// payment document itself is never deleted, only marked paid, so the
/// history of what was owed and when it was settled is preserved.
class PendingPayment {
  final String id;

  /// The date this amount became due.
  final DateTime date;
  final String description;
  final double amount;

  /// True once this amount has been collected. A paid pending payment
  /// is hidden from the default "still owed" query, but its document
  /// is never removed from Firestore.
  final bool isPaid;

  final DateTime createdAt;
  final DateTime updatedAt;

  const PendingPayment({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.isPaid = false,
  });

  /// Builds a [PendingPayment] from a Firestore document snapshot.
  factory PendingPayment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return PendingPayment.fromMap(data, id: doc.id);
  }

  /// Builds a [PendingPayment] from a raw map (e.g. Firestore data payload).
  factory PendingPayment.fromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    return PendingPayment(
      id: id,
      date: _timestampToDate(map['date']),
      description: map['description'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      isPaid: map['isPaid'] as bool? ?? false,
      createdAt: _timestampToDate(map['createdAt']),
      updatedAt: _timestampToDate(map['updatedAt']),
    );
  }

  /// Converts this [PendingPayment] into a Firestore-writable map. The
  /// document id is not included, since it is the document key.
  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'description': description,
      'amount': amount,
      'isPaid': isPaid,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  PendingPayment copyWith({
    DateTime? date,
    String? description,
    double? amount,
    bool? isPaid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PendingPayment(
      id: id,
      date: date ?? this.date,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      isPaid: isPaid ?? this.isPaid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _timestampToDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}