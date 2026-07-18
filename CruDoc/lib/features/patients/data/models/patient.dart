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
  final String diagnosis;
  final double packageBalance;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Patient({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.gender,
    required this.dateOfBirth,
    required this.diagnosis,
    required this.packageBalance,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Convenience getter for display purposes.
  String get fullName => '$firstName $lastName';

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
      diagnosis: map['diagnosis'] as String? ?? '',
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
      'diagnosis': diagnosis,
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
    String? diagnosis,
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
}