import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/core/errors/patient_exceptions.dart';
import 'package:doctor_management_app/features/appointments/data/services/visits_firestore_service.dart';
import 'package:doctor_management_app/core/errors/visit_exceptions.dart';

/// Clean API the presentation layer talks to for anything visit-related.
///
/// Mirrors [PatientRepository]'s role: wraps [VisitFirestoreService] so
/// the UI never touches Firestore types directly. This is also where
/// every business rule from the appointment spec actually lives —
/// patient existence/active checks, the scheduled/completed/cancelled/
/// missed status enum, soft delete, and overlap detection with its
/// max-4 hard limit. [VisitFirestoreService] underneath does none of
/// this validation itself, so this repository is the one place the UI
/// should call into — never the service directly.
class VisitRepository {
  VisitRepository({
    VisitFirestoreService? firestoreService,
    PatientRepository? patientRepository,
  })  : _firestoreService = firestoreService ?? VisitFirestoreService(),
        _patientRepository = patientRepository ?? PatientRepository();

  final VisitFirestoreService _firestoreService;
  final PatientRepository _patientRepository;

  /// Creates a new visit for an existing patient.
  ///
  /// Always pass a [visit] whose `patientId` refers to a patient that
  /// already exists — create the patient first (via [PatientRepository])
  /// and use the id it returns here. This method never creates a
  /// patient, and never should.
  ///
  /// Throws:
  /// - [VisitValidationException] for missing/invalid fields.
  /// - [PatientNotFoundException] if `visit.patientId` doesn't exist.
  /// - [InactivePatientException] if that patient is archived.
  /// - [SamePatientDoubleBookingException] if the same patient already
  ///   has an overlapping visit — never bypassable.
  /// - [VisitOverlapWarning] if a *different* patient has an overlapping
  ///   visit and [acknowledgeOverlap] is false. Catch this, show the
  ///   doctor the conflicting visits, and call again with
  ///   `acknowledgeOverlap: true` if they confirm.
  /// - [VisitOverlapLimitExceededException] if saving would exceed
  ///   [kMaxOverlappingVisits] simultaneous active visits — never
  ///   bypassable, regardless of [acknowledgeOverlap].
  Future<String> createVisit(
    Visit visit, {
    bool acknowledgeOverlap = false,
  }) async {
    _validate(visit);
    await _checkPatient(visit.patientId);
    await _checkOverlap(
      patientId: visit.patientId,
      start: visit.scheduledStart,
      end: visit.scheduledEnd,
      acknowledgeOverlap: acknowledgeOverlap,
    );

    return _firestoreService.createVisit(visit);
  }

  /// Updates arbitrary fields on an existing visit. Prefer
  /// [rescheduleVisit], [updateStatus], [cancelVisit], or
  /// [softDeleteVisit] for those specific operations — they carry the
  /// right guardrails. `updatedAt` is stamped automatically by the
  /// service layer regardless of what's passed here.
  ///
  /// Throws [VisitValidationException] if [data] contains a `status`
  /// key that isn't one of the predefined [VisitStatus] values — this
  /// is the backstop that keeps free-text statuses out even if a
  /// caller bypasses [updateStatus].
  Future<void> updateVisit(String visitId, Map<String, dynamic> data) {
    if (data.containsKey('status')) {
      final raw = data['status'];
      final validValues = VisitStatus.values.map((s) => s.value).toSet();
      if (raw is! String || !validValues.contains(raw)) {
        throw VisitValidationException(
          'Invalid status "$raw". Must be one of: ${validValues.join(', ')}.',
        );
      }
    }
    return _firestoreService.updateVisit(visitId, data);
  }

  /// Moves an existing visit to a new start time and/or duration,
  /// re-running the same patient/overlap checks as [createVisit]
  /// (excluding the visit's own current slot from the conflict search).
  Future<void> rescheduleVisit(
    String visitId, {
    required DateTime newStart,
    int? newDurationMinutes,
    bool acknowledgeOverlap = false,
  }) async {
    final existing = await _firestoreService.getVisit(visitId);
    if (existing == null) {
      throw VisitValidationException('No visit found with id "$visitId".');
    }

    final duration = newDurationMinutes ?? existing.durationMinutes;
    if (duration < kMinVisitDurationMinutes ||
        duration > kMaxVisitDurationMinutes) {
      throw VisitValidationException(
        'Visit duration must be between $kMinVisitDurationMinutes and '
        '$kMaxVisitDurationMinutes minutes.',
      );
    }

    final newEnd = newStart.add(Duration(minutes: duration));

    await _checkOverlap(
      patientId: existing.patientId,
      start: newStart,
      end: newEnd,
      excludeVisitId: visitId,
      acknowledgeOverlap: acknowledgeOverlap,
    );

    await updateVisit(visitId, {
      'scheduledStart': newStart,
      'durationMinutes': duration,
    });
  }

  /// Updates only the [VisitStatus] — the enum is the only way to move
  /// a visit between states, so a free-text status can never slip in.
  Future<void> updateStatus(String visitId, VisitStatus status) {
    return updateVisit(visitId, {'status': status.value});
  }

  /// Marks a visit as cancelled. A real, legitimate cancellation
  /// (distinct from [softDeleteVisit]) — it stays visible in the
  /// patient's history as a cancelled appointment, and immediately
  /// frees up its slot for overlap purposes.
  Future<void> cancelVisit(String visitId) {
    return updateStatus(visitId, VisitStatus.cancelled);
  }

  /// Soft-deletes a visit (e.g. it was created by mistake). The
  /// document is never removed from Firestore — it's only excluded from
  /// every default query — so history is fully preserved.
  Future<void> softDeleteVisit(String visitId) {
    return updateVisit(visitId, {'isDeleted': true});
  }

  /// Fetches a single visit by id, or null if it doesn't exist.
  Future<Visit?> getVisit(String visitId) => _firestoreService.getVisit(visitId);

  /// Streams active upcoming visits from [from] (defaults to now)
  /// onward, ordered by start time ascending.
  Stream<List<Visit>> watchUpcomingVisits({DateTime? from}) {
    return _firestoreService.watchUpcomingVisits(from: from);
  }

  /// Streams a single patient's visit history, most recent first.
  Stream<List<Visit>> watchVisitsForPatient(
    String patientId, {
    bool includeDeleted = false,
  }) {
    return _firestoreService.watchVisitsForPatient(
      patientId,
      includeDeleted: includeDeleted,
    );
  }

  /// Read-only overlap check for the UI to call live — e.g. as soon as
  /// the doctor picks a time — so it can show a warning *before* they
  /// even tap save. [createVisit] and [rescheduleVisit] re-run this
  /// check themselves regardless, so this is a courtesy for a
  /// responsive UI, never the only line of defense.
  Future<List<Visit>> findOverlapping({
    required DateTime start,
    required DateTime end,
    String? excludeVisitId,
  }) {
    return _firestoreService.findOverlapping(
      start: start,
      end: end,
      excludeVisitId: excludeVisitId,
    );
  }

  // ---------------- internal helpers ----------------

  void _validate(Visit visit) {
    if (visit.patientId.trim().isEmpty) {
      throw const VisitValidationException('A visit must have a patientId.');
    }
    if (visit.address.trim().isEmpty) {
      throw const VisitValidationException(
        'A visit must have an address — this app covers offline/'
        'in-person visits only.',
      );
    }
    if (visit.durationMinutes < kMinVisitDurationMinutes ||
        visit.durationMinutes > kMaxVisitDurationMinutes) {
      throw VisitValidationException(
        'Visit duration must be between $kMinVisitDurationMinutes and '
        '$kMaxVisitDurationMinutes minutes.',
      );
    }
    if (!visit.scheduledStart.isBefore(visit.scheduledEnd)) {
      throw const VisitValidationException(
        'A visit must have a positive duration.',
      );
    }
  }

  Future<void> _checkPatient(String patientId) async {
    final patient = await _patientRepository.getPatient(patientId);
    if (patient == null) {
      throw PatientNotFoundException(patientId);
    }
    if (patient.isArchived) {
      throw InactivePatientException(patientId);
    }
  }

  Future<void> _checkOverlap({
    required String patientId,
    required DateTime start,
    required DateTime end,
    String? excludeVisitId,
    required bool acknowledgeOverlap,
  }) async {
    final conflicts = await _firestoreService.findOverlapping(
      start: start,
      end: end,
      excludeVisitId: excludeVisitId,
    );

    if (conflicts.isEmpty) return;

    // The same patient can never legitimately be at two visits at
    // once — that's never something to "acknowledge", it's just wrong,
    // regardless of how much headroom is left under the max-overlap cap.
    final samePatientConflicts =
        conflicts.where((v) => v.patientId == patientId);
    if (samePatientConflicts.isNotEmpty) {
      throw SamePatientDoubleBookingException(samePatientConflicts.first);
    }

    if (conflicts.length >= kMaxOverlappingVisits) {
      throw VisitOverlapLimitExceededException(conflicts);
    }

    if (!acknowledgeOverlap) {
      throw VisitOverlapWarning(conflicts);
    }
  }
}