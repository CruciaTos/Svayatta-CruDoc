import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';

/// Base type for every queue-related domain error thrown by
/// [QueueRepository]. Lets calling code `catch (e) { if (e is
/// QueueException) ... }` to handle all of them generically, or catch a
/// specific subtype when it needs to react differently — e.g. showing a
/// "call this token again?" prompt for [QueueAlreadyServingException]
/// instead of a plain error message. Mirrors [VisitException]'s shape
/// in visit_exceptions.dart.
sealed class QueueException implements Exception {
  final String message;
  const QueueException(this.message);

  @override
  String toString() => message;
}

/// A required field was missing or invalid — e.g. [checkIn] called with
/// neither a `patientId` nor a `walkInName`, or with both.
class QueueValidationException extends QueueException {
  const QueueValidationException(super.message);
}

/// The patient behind a check-in exists but is archived
/// (`isArchived == true`). Checking in an archived patient is blocked
/// by default, since it's almost always a sign the wrong patient was
/// selected. Reactivate the patient first if this is intentional.
class QueuePatientArchivedException extends QueueException {
  QueuePatientArchivedException(String patientId)
    : super(
        'Patient "$patientId" is archived and cannot be checked into the '
        'queue. Reactivate the patient first.',
      );
}

/// [QueueRepository.callNext] was called with nobody left waiting.
class QueueEmptyException extends QueueException {
  const QueueEmptyException()
    : super('There is no one waiting in the queue.');
}

/// An action expected a queue entry to be in a specific state (e.g.
/// starting a consultation for a token that hasn't been called yet),
/// but it's in a different one.
class QueueInvalidTransitionException extends QueueException {
  final QueueEntry entry;
  final QueueStatus attempted;
  QueueInvalidTransitionException(this.entry, this.attempted)
    : super(
        'Cannot move token #${entry.tokenNumber} from '
        '${entry.status.value} to ${attempted.value}.',
      );
}

/// [QueueRepository.callNext] or [QueueRepository.startConsultation] was
/// called while another token is already [QueueStatus.called] or
/// [QueueStatus.inConsultation] — only one token can be actively served
/// at a time. Resolve [activeEntry] first (complete, skip, or cancel
/// it).
class QueueAlreadyServingException extends QueueException {
  final QueueEntry activeEntry;
  QueueAlreadyServingException(this.activeEntry)
    : super(
        'Token #${activeEntry.tokenNumber} is already being served. '
        'Complete, skip, or cancel it first.',
      );
}
