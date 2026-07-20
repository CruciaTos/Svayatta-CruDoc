import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Core Patient data model.
///
/// Represents a single patient document stored in the `patients`
/// Firestore collection. Kept as a plain, hand-written model (no
/// freezed/json_serializable) to match the rest of the app's
/// current simplicity — this can be migrated to freezed later if
/// the project adopts it more broadly.
class Patient {
  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String gender;
  final DateTime dateOfBirth;

  /// Up to [maxDiagnoses] distinct diagnoses for this patient.
  final List<String> diagnosis;

  /// Free-form clinical note the doctor can attach to this patient,
  /// edited from the patient details screen.
  final String notes;

  final double packageBalance;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// A patient may have at most this many diagnoses recorded.
  static const int maxDiagnoses = 4;

  const Patient({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.gender,
    required this.dateOfBirth,
    required this.diagnosis,
    this.notes = '',
    required this.packageBalance,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Convenience getter for display purposes.
  String get fullName => '$firstName $lastName';

  /// Comma-separated diagnoses, for single-line UI contexts (list rows,
  /// cards) that don't have room to render one pill per diagnosis.
  String get diagnosisDisplay => diagnosis.join(', ');

  /// Current age in years, computed from [dateOfBirth].
  int get age {
    final today = DateTime.now();
    var years = today.year - dateOfBirth.year;
    final hasHadBirthdayThisYear =
        today.month > dateOfBirth.month ||
        (today.month == dateOfBirth.month && today.day >= dateOfBirth.day);

    if (!hasHadBirthdayThisYear) years--;
    return years < 0 ? 0 : years;
  }

  /// Builds a [Patient] from a Firestore document snapshot.
  factory Patient.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Patient.fromMap(data, id: doc.id);
  }

  /// Builds a [Patient] from a raw map (e.g. Firestore data payload).
  factory Patient.fromMap(Map<String, dynamic> map, {required String id}) {
    return Patient(
      id: id,
      firstName: map['firstName'] as String? ?? '',
      lastName: map['lastName'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      gender: map['gender'] as String? ?? '',
      dateOfBirth: _timestampToDate(map['dateOfBirth']),
      diagnosis: diagnosisFromStored(map['diagnosis']),
      notes: map['notes'] as String? ?? '',
      packageBalance: (map['packageBalance'] as num?)?.toDouble() ?? 0.0,
      isArchived: map['isArchived'] as bool? ?? false,
      createdAt: _timestampToDate(map['createdAt']),
      updatedAt: _timestampToDate(map['updatedAt']),
    );
  }

  /// Converts this [Patient] into a Firestore-writable map.
  /// The document id is not included, since it is the document key.
  Map<String, dynamic> toMap() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'gender': gender,
      'dateOfBirth': Timestamp.fromDate(dateOfBirth),
      'diagnosis': diagnosisToStored(diagnosis),
      'notes': notes,
      'packageBalance': packageBalance,
      'isArchived': isArchived,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Patient copyWith({
    String? firstName,
    String? lastName,
    String? phone,
    String? gender,
    DateTime? dateOfBirth,
    List<String>? diagnosis,
    String? notes,
    double? packageBalance,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Patient(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      diagnosis: diagnosis ?? this.diagnosis,
      notes: notes ?? this.notes,
      packageBalance: packageBalance ?? this.packageBalance,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _timestampToDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  /// Serializes a diagnosis list into the single TEXT value stored in the
  /// `diagnosis` column/field (SQLite + Firestore both keep this as a
  /// plain string, so no schema change was needed to support multiple
  /// diagnoses). Encoded as JSON rather than a delimiter-joined string so
  /// a diagnosis containing punctuation can't be mis-split on read.
  /// Trims blanks and caps at [maxDiagnoses].
  static String diagnosisToStored(List<String> diagnoses) {
    final cleaned = diagnoses
        .map((d) => d.trim())
        .where((d) => d.isNotEmpty)
        .take(maxDiagnoses)
        .toList();
    return jsonEncode(cleaned);
  }

  /// Parses the stored `diagnosis` value back into a list. Also accepts a
  /// plain (pre-existing) string or a native list, so patients written
  /// before this field supported multiple diagnoses still load correctly.
  static List<String> diagnosisFromStored(Object? value) {
    if (value == null) return const [];

    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .take(maxDiagnoses)
          .toList();
    }

    final raw = (value as String? ?? '').trim();
    if (raw.isEmpty) return const [];

    if (raw.startsWith('[')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .take(maxDiagnoses)
              .toList();
        }
      } catch (_) {
        // Not actually JSON — fall through and treat as a legacy
        // single-diagnosis string below.
      }
    }

    return [raw];
  }
}