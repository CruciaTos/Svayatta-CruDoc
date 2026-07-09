import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';

/// Base type for every visit-related domain error thrown by
/// [VisitRepository]. Lets calling code `catch (e) { if (e is
/// VisitException) ... }` to handle all of them generically, or catch a
/// specific subtype (e.g. [VisitOverlapWarning]) when it needs to react
/// differently — such as showing a confirmation dialog instead of a
/// plain error message.
sealed class VisitException implements Exception {
  final String message;
  const VisitException(this.message);

  @override
  String toString() => message;
}

/// A required field was missing, empty, or out of the allowed range
/// (e.g. no patientId, no address, an out-of-bounds duration).
class VisitValidationException extends VisitException {
  const VisitValidationException(super.message);
}

/// [Visit.patientId] does not correspond to any existing patient.
///
/// Guards the "every visit belongs to exactly one real patient" rule —
/// a visit can never be created (or silently orphaned) against an id
/// that doesn't resolve to an actual Patient document.
class PatientNotFoundException extends VisitException {
  PatientNotFoundException(String patientId)
      : super(
          'No patient found with id "$patientId". Create the patient '
          'first, then create the visit using its id — never the '
          'other way around.',
        );
}

/// The target patient exists but is archived (`isArchived == true`).
///
/// Scheduling a new visit for an archived patient is blocked by
/// default, since it's almost always a sign the wrong patient was
/// selected. Reactivate the patient first if this is intentional.
class InactivePatientException extends VisitException {
  InactivePatientException(String patientId)
      : super(
          'Patient "$patientId" is archived and cannot be booked for a '
          'new visit. Reactivate the patient first.',
        );
}

/// The same patient already has another active visit that overlaps
/// this one.
///
/// Unlike [VisitOverlapWarning], this is never allowed through — a
/// single patient cannot legitimately be at two appointments at once,
/// so there is nothing to acknowledge past. Not the same
/// [VisitStatus] restriction as [VisitOverlapWarning]; this fires even
/// when there'd otherwise be room under [kMaxOverlappingVisits].
class SamePatientDoubleBookingException extends VisitException {
  final Visit conflict;
  SamePatientDoubleBookingException(this.conflict)
      : super(
          'This patient already has a visit scheduled at '
          '${conflict.scheduledStart} that overlaps this time.',
        );
}

/// One or more *different* patients already have active visits
/// overlapping this time slot.
///
/// This is recoverable: catch it, show the doctor the conflicting
/// visits, and retry the same repository call with
/// `acknowledgeOverlap: true` if they confirm they still want to save.
class VisitOverlapWarning extends VisitException {
  final List<Visit> conflicts;
  VisitOverlapWarning(this.conflicts)
      : super(
          'This time overlaps ${conflicts.length} existing visit(s). '
          'Confirm to save anyway.',
        );
}

/// Saving this visit would push the number of simultaneously
/// overlapping active visits past [kMaxOverlappingVisits].
///
/// Unlike [VisitOverlapWarning], this is a hard limit — it cannot be
/// bypassed with `acknowledgeOverlap`.
class VisitOverlapLimitExceededException extends VisitException {
  final List<Visit> conflicts;
  VisitOverlapLimitExceededException(this.conflicts)
      : super(
          'Cannot schedule this visit — it would exceed the maximum of '
          '$kMaxOverlappingVisits overlapping visits at the same time.',
        );
}