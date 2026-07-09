/// Thrown by [PatientRepository]/[PatientFirestoreService] when a patient
/// fails basic validation (e.g. an empty name). Kept as a distinct, typed
/// exception so calling UI code can catch it specifically and show a
/// friendly message, instead of parsing a generic Firestore error.
class PatientValidationException implements Exception {
  final String message;
  const PatientValidationException(this.message);

  @override
  String toString() => message;
}