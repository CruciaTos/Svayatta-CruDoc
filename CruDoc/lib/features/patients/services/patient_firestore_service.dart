import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/patients/models/patient.dart';

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
  Future<String> createPatient(Patient patient) async {
    final id = const Uuid().v4();
    await _patientsRef.doc(id).set(patient.toMap());
    return id;
  }

  /// Updates an existing patient document with the given fields.
  Future<void> updatePatient(String patientId, Map<String, dynamic> data) async {
    await _patientsRef.doc(patientId).update(data);
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
        .map((snapshot) =>
            snapshot.docs.map(Patient.fromFirestore).toList());
  }
}