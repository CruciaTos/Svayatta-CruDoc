import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/utils/search_normalisation.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/core/errors/patient_exceptions.dart';

/// Talks directly to the `patients` Firestore collection.
///
/// This is the only layer in the feature that knows about
/// `cloud_firestore` types. Everything above it (the repository,
/// the UI) works with plain [Patient] objects.
class PatientFirestoreService {
  PatientFirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _patientsRef =>
      _firestore.collection('patients');

  /// Creates a new patient document and returns the generated document id.
  ///
  /// The id is generated here (client-side) rather than via Firestore's
  /// auto-id, so a retried call can safely reuse the same id instead of
  /// risking a duplicate patient document.
  ///
  /// Throws [PatientValidationException] for an empty name. This is a
  /// second line of defense — the UI should already stop this — never
  /// the only one.
  Future<String> createPatient(Patient patient) async {
    _validate(patient);
    final id = patient.id.trim().isEmpty ? const Uuid().v4() : patient.id;
    await _patientsRef.doc(id).set(patient.toMap());
    return id;
  }

  /// Updates an existing patient document with the given fields.
  ///
  /// If [data] touches `firstName`, it's re-validated the same way as
  /// [createPatient] — a patient can't be edited into having an empty
  /// name any more than they could be created with one.
  Future<void> updatePatient(
    String patientId,
    Map<String, dynamic> data,
  ) async {
    if (data.containsKey('firstName')) {
      final firstName = data['firstName'] as String? ?? '';
      if (firstName.trim().isEmpty) {
        throw const PatientValidationException('First name cannot be empty.');
      }
    }
    final sanitized = <String, dynamic>{
      for (final entry in data.entries)
        entry.key: entry.value is DateTime
            ? Timestamp.fromDate(entry.value as DateTime)
            : entry.value,
    };
    await _patientsRef.doc(patientId).update(sanitized);
  }

  /// Deletes a patient document permanently.
  Future<void> deletePatient(String patientId) async {
    await _patientsRef.doc(patientId).delete();
  }

  /// Fetches a single patient by id. Returns null if it doesn't exist.
  Future<Patient?> getPatient(String patientId) async {
    final snapshot = await _patientsRef.doc(patientId).get();
    if (!snapshot.exists) return null;
    return Patient.fromFirestore(snapshot);
  }

  /// Streams the list of non-archived patients, ordered by most recently
  /// created first.
  Stream<List<Patient>> watchPatients() {
    return _patientsRef
        .where('isArchived', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Patient.fromFirestore).toList());
  }

  /// Finds patients matching [rawQuery] by name, phone, or exact patient
  /// id — this is what backs the "search existing patients before
  /// creating a new one" step of the appointment flow, so a doctor
  /// doesn't accidentally create a duplicate.
  ///
  /// - Name matching is case-insensitive and substring-based (searching
  ///   "john" finds "John Doe").
  /// - Phone matching ignores spacing, dashes, and a leading country
  ///   code (searching "9876543210" finds "+91 98765 43210").
  /// - A query that exactly matches a document id is also resolved
  ///   directly, in case a future flow feeds this a scanned/looked-up id.
  ///
  /// Defaults to searching archived patients too ([includeArchived] =
  /// true) — a patient who previously stopped treatment can come back,
  /// and excluding them here would risk creating a duplicate for
  /// exactly the person this search exists to protect against.
  ///
  /// This fetches the full patient collection and filters client-side.
  /// That's the right tradeoff for a single practice's patient list
  /// (realistically tens to low hundreds of documents) — it gets
  /// correct case/format-insensitive matching for free, which Firestore
  /// can't do natively without maintaining extra indexed fields. If the
  /// patient list grows into the thousands, revisit this with a
  /// maintained lowercase/digits-only index field or a dedicated search
  /// service (e.g. Algolia/Typesense).
  Future<List<Patient>> searchPatients(
    String rawQuery, {
    bool includeArchived = true,
  }) async {
    final query = rawQuery.trim();
    print('🔍 searchPatients START: query="$query"');
    if (query.isEmpty) {
      print('🔍 Query empty, returning []');
      return [];
    }

    // Keeps insertion order and de-dupes by id if a patient matches more
    // than one way (e.g. the id short-circuit below AND a name match).
    final results = <String, Patient>{};

    // Exact-id short-circuit. [query] is free-typed text, not a
    // validated document path, so this is only attempted when it can't
    // be mistaken for a multi-segment Firestore path (containing "/"),
    // and any unexpected failure is swallowed rather than breaking the
    // rest of the search.
    if (!query.contains('/')) {
      print('🔍 Trying exact ID lookup...');
      try {
        final byId = await getPatient(query);
        if (byId != null && (includeArchived || !byId.isArchived)) {
          results[byId.id] = byId;
          print('🔍 Found patient by ID: ${byId.fullName}');
        }
      } catch (e) {
        print('🔍 ID lookup failed (expected): $e');
      }
    }

    print('🔍 Normalizing query...');
    final normalizedQuery = normalizeForSearch(query);
    final normalizedPhoneQuery = normalizePhoneDigits(query);
    print(
      '🔍 Normalized: name="$normalizedQuery", phone="$normalizedPhoneQuery"',
    );
    // Guards against a 1-2 digit query (or a short name that happens to
    // contain digits) matching almost every phone number in the list.
    final canMatchPhone = normalizedPhoneQuery.length >= 3;

    print('🔍 Fetching all patients from Firestore...');
    final snapshot = await _patientsRef.get();
    print('🔍 Got ${snapshot.docs.length} patient documents');

    for (int i = 0; i < snapshot.docs.length; i++) {
      final doc = snapshot.docs[i];
      print('🔍 Processing doc $i/${snapshot.docs.length}: ${doc.id}');
      try {
        final patient = Patient.fromFirestore(doc);
        if (results.containsKey(patient.id)) {
          print('🔍   Already in results, skipping');
          continue;
        }
        if (!includeArchived && patient.isArchived) {
          print('🔍   Archived, skipping');
          continue;
        }

        final nameMatch = normalizeForSearch(
          patient.fullName,
        ).contains(normalizedQuery);
        final phoneMatch =
            canMatchPhone &&
            normalizePhoneDigits(patient.phone).contains(normalizedPhoneQuery);

        if (nameMatch || phoneMatch) {
          results[patient.id] = patient;
          print('🔍   MATCH: ${patient.fullName}');
        }
      } catch (e) {
        print('❌ Error processing doc $i: $e');
      }
    }

    print('🔍 searchPatients END: found ${results.length} results');
    return results.values.toList();
  }

  void _validate(Patient patient) {
    if (patient.firstName.trim().isEmpty) {
      throw const PatientValidationException('First name cannot be empty.');
    }
  }
}
