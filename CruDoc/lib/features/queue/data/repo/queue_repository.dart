import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/services/visits_local_service.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/services/queue_local_service.dart';

/// Clean API the presentation layer talks to for anything walk-in-queue
/// related.
///
/// Reads and writes go through SQLite; writes are marked pending
/// locally and the sync engine is triggered in the background — same
/// shape as `VisitRepository`. This is also where every queue business
/// rule lives: exactly-one-of-patient-or-walk-in on check-in, atomic
/// daily token numbering, and the waiting -> called -> inConsultation ->
/// completed state machine (with skip/requeue/cancel side paths).
class QueueRepository {
  QueueRepository({
    QueueLocalService? localService,
    FirestoreSyncService? syncService,
    PatientRepository? patientRepository,
    VisitLocalService? visitLocalService,
  }) : _localService = localService ?? QueueLocalService(),
       _syncService = syncService ?? FirestoreSyncService.instance,
       _patientRepository = patientRepository ?? PatientRepository(),
       _visitLocalService = visitLocalService ?? VisitLocalService();

  final QueueLocalService _localService;
  final FirestoreSyncService _syncService;
  final PatientRepository _patientRepository;
  final VisitLocalService _visitLocalService;

  /// The signed-in doctor's UID — see PatientRepository for why this
  /// matters and what it guards against.
  String get _currentDoctorId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('No signed-in doctor — cannot access queue data.');
    }
    return uid;
  }

  /// Checks a patient into today's walk-in queue and assigns the next
  /// token number for today, atomically.
  ///
  /// Pass exactly one of [patientId] (an existing, registered patient)
  /// or [walkInName] (captured on the spot for someone not yet
  /// registered) — never both, never neither.
  ///
  /// Throws:
  /// - [QueueValidationException] if that exactly-one rule is violated.
  /// - [QueuePatientArchivedException] if [patientId] resolves to an
  ///   archived patient.
  ///
  /// The archived-patient check is best-effort: a lookup failure (e.g.
  /// offline) never blocks the check-in, only a *confirmed* archived
  /// patient does — the same "never let a side read block the write"
  /// lesson `VisitRepository.createVisit` already learned the hard way
  /// (see its TEMPORARY note about `_checkPatient`).
  Future<QueueEntry> checkIn({
    String? patientId,
    String? walkInName,
    String? walkInPhone,
    String? reason,
    QueuePriority priority = QueuePriority.normal,
  }) async {
    final trimmedPatientId = patientId?.trim() ?? '';
    final trimmedWalkInName = walkInName?.trim() ?? '';
    final hasPatient = trimmedPatientId.isNotEmpty;
    final hasWalkIn = trimmedWalkInName.isNotEmpty;

    if (hasPatient == hasWalkIn) {
      throw const QueueValidationException(
        'Check in either an existing patient or a walk-in name — '
        'not both, and not neither.',
      );
    }

    if (hasPatient) {
      try {
        final patient = await _patientRepository.getPatient(trimmedPatientId);
        if (patient != null && patient.isArchived) {
          throw QueuePatientArchivedException(trimmedPatientId);
        }
      } on QueuePatientArchivedException {
        rethrow;
      } catch (_) {
        // Lookup failed (offline, a Web/Firestore hiccup, etc.) —
        // proceed. The token is still useful even if the patient link
        // can't be verified right now.
      }
    }

    final trimmedPhone = walkInPhone?.trim() ?? '';
    final trimmedReason = reason?.trim() ?? '';
    final now = DateTime.now();

    final draft = QueueEntry(
      id: const Uuid().v4(),
      doctorId: _currentDoctorId,
      patientId: hasPatient ? trimmedPatientId : null,
      walkInName: hasPatient ? null : trimmedWalkInName,
      walkInPhone: trimmedPhone.isEmpty ? null : trimmedPhone,
      tokenNumber: 0, // assigned atomically by QueueLocalService.checkIn
      queueDate: queueDateKeyFor(now),
      status: QueueStatus.waiting,
      priority: priority,
      reason: trimmedReason.isEmpty ? null : trimmedReason,
      checkedInAt: now,
      createdAt: now,
      updatedAt: now,
    );

    final created = await _localService.checkIn(draft);
    unawaited(_syncService.triggerPostWriteSync());
    return created;
  }

  /// Calls the next waiting token: the earliest [QueuePriority.urgent]
  /// token if any are waiting, otherwise the lowest [QueueEntry.tokenNumber].
  /// Marks it [QueueStatus.called] and stamps [QueueEntry.calledAt].
  ///
  /// Throws [QueueAlreadyServingException] if another token is already
  /// [QueueStatus.called] or [QueueStatus.inConsultation] — resolve
  /// that one first via [complete], [skip], or [cancel]. Throws
  /// [QueueEmptyException] if nobody is waiting.
  Future<QueueEntry> callNext() async {
    final today = await _localService.getTodaysQueue();

    final active = today.where((e) => e.isActiveServing);
    if (active.isNotEmpty) {
      throw QueueAlreadyServingException(active.first);
    }

    final waiting = today.where((e) => e.status == QueueStatus.waiting).toList()
      ..sort((a, b) {
        final rankA = a.priority == QueuePriority.urgent ? 0 : 1;
        final rankB = b.priority == QueuePriority.urgent ? 0 : 1;
        if (rankA != rankB) return rankA.compareTo(rankB);
        return a.tokenNumber.compareTo(b.tokenNumber);
      });

    if (waiting.isEmpty) {
      throw const QueueEmptyException();
    }

    final next = waiting.first;
    final calledAt = DateTime.now();
    await _updateStatus(next.id, QueueStatus.called, extra: {
      'calledAt': calledAt,
    });
    unawaited(_syncService.triggerPostWriteSync());
    return next.copyWith(status: QueueStatus.called, calledAt: calledAt);
  }

  /// Moves a [QueueStatus.called] token into [QueueStatus.inConsultation]
  /// — the doctor has actually started seeing this patient.
  ///
  /// Throws [QueueInvalidTransitionException] if [entryId] isn't
  /// currently [QueueStatus.called].
  Future<QueueEntry> startConsultation(String entryId) async {
    final entry = await _requireEntry(entryId);
    if (entry.status != QueueStatus.called) {
      throw QueueInvalidTransitionException(entry, QueueStatus.inConsultation);
    }
    final startedAt = DateTime.now();
    await _updateStatus(entryId, QueueStatus.inConsultation, extra: {
      'consultationStartedAt': startedAt,
    });
    unawaited(_syncService.triggerPostWriteSync());
    return entry.copyWith(
      status: QueueStatus.inConsultation,
      consultationStartedAt: startedAt,
    );
  }

  /// Marks a token [QueueStatus.completed] — the visit is done.
  /// Callable from [QueueStatus.called] directly too, for a quick
  /// consult that doesn't need a separate [startConsultation] step.
  ///
  /// Throws [QueueInvalidTransitionException] if [entryId] is in any
  /// other state.
  Future<QueueEntry> complete(String entryId) async {
    final entry = await _requireEntry(entryId);
    if (entry.status != QueueStatus.inConsultation &&
        entry.status != QueueStatus.called) {
      throw QueueInvalidTransitionException(entry, QueueStatus.completed);
    }
    final completedAt = DateTime.now();
    await _updateStatus(entryId, QueueStatus.completed, extra: {
      'completedAt': completedAt,
    });

    // If linked to a pre-booked appointment, synchronize its status in visits.
    if (entry.linkedVisitId != null && entry.linkedVisitId!.isNotEmpty) {
      try {
        await _visitLocalService.updateVisit(entry.linkedVisitId!, {
          'status': VisitStatus.completed.value,
          'updatedAt': completedAt,
        });
      } catch (_) {
        // Best-effort sync to visit record
      }
    }

    unawaited(_syncService.triggerPostWriteSync());
    return entry.copyWith(status: QueueStatus.completed, completedAt: completedAt);
  }

  /// Marks a called-but-absent token [QueueStatus.skipped] — called,
  /// but the patient wasn't there. A skipped token can be brought back
  /// with [requeue]. Callable from [QueueStatus.waiting] too, for
  /// removing someone from the line before they were ever called.
  ///
  /// Throws [QueueInvalidTransitionException] if [entryId] is
  /// [QueueStatus.inConsultation] or already resolved — pull them out
  /// of consultation with [complete] or [cancel] instead.
  Future<void> skip(String entryId) async {
    final entry = await _requireEntry(entryId);
    if (entry.status != QueueStatus.called &&
        entry.status != QueueStatus.waiting) {
      throw QueueInvalidTransitionException(entry, QueueStatus.skipped);
    }
    await _updateStatus(entryId, QueueStatus.skipped);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Sends a [QueueStatus.skipped] token back to [QueueStatus.waiting],
  /// keeping its original [QueueEntry.tokenNumber] — it re-enters the
  /// queue in its original numeric position, not at the back of the
  /// line. Call [checkIn] again instead for a fresh token at the back.
  ///
  /// Throws [QueueInvalidTransitionException] if [entryId] isn't
  /// currently [QueueStatus.skipped].
  Future<void> requeue(String entryId) async {
    final entry = await _requireEntry(entryId);
    if (entry.status != QueueStatus.skipped) {
      throw QueueInvalidTransitionException(entry, QueueStatus.waiting);
    }
    await _updateStatus(entryId, QueueStatus.waiting);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Cancels a token entirely — the patient left, or it was checked in
  /// by mistake. Distinct from [skip]: a cancelled token is done for
  /// the day and [requeue] won't bring it back.
  Future<void> cancel(String entryId) async {
    final entry = await _localService.getEntry(entryId);
    if (entry != null &&
        entry.linkedVisitId != null &&
        entry.linkedVisitId!.isNotEmpty) {
      try {
        await _visitLocalService.updateVisit(entry.linkedVisitId!, {
          'status': VisitStatus.cancelled.value,
          'updatedAt': DateTime.now(),
        });
      } catch (_) {
        // Best-effort sync
      }
    }
    await _updateStatus(entryId, QueueStatus.cancelled);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Checks a pre-booked clinic appointment into the queue if not already
  /// queued, or returns the existing linked token.
  Future<QueueEntry> checkInVisit(
    Visit visit, {
    QueuePriority priority = QueuePriority.normal,
  }) async {
    final created = await _localService.ensureVisitInQueue(
      visitId: visit.id,
      patientId: visit.patientId,
      scheduledStart: visit.scheduledStart,
      reason: visit.treatmentType ?? visit.therapistNotes,
      priority: priority,
      status: visit.status == VisitStatus.completed
          ? QueueStatus.completed
          : (visit.status == VisitStatus.cancelled
              ? QueueStatus.cancelled
              : QueueStatus.waiting),
    );
    unawaited(_syncService.triggerPostWriteSync());
    return created;
  }

  /// Soft-deletes a queue entry (e.g. a mis-entered check-in). Hidden
  /// from every default query but never removed from Firestore/SQLite —
  /// matches Visit's soft-delete convention.
  Future<void> softDeleteEntry(String entryId) async {
    await _localService.updateEntry(entryId, {
      'isDeleted': true,
      'updatedAt': DateTime.now(),
    });
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Streams today's queue — every non-deleted token whose
  /// [QueueEntry.queueDate] is today, in every status.
  Stream<List<QueueEntry>> watchTodaysQueue() => _localService.watchTodaysQueue();

  /// Streams all non-deleted queue tokens across all dates in real-time.
  Stream<List<QueueEntry>> watchAllQueue() => _localService.watchAllQueue();

  /// Queries non-deleted queue tokens within a date range (inclusive).
  Future<List<QueueEntry>> getQueueForDateRange(DateTime start, DateTime end) =>
      _localService.getQueueForDateRange(start, end);

  Future<QueueEntry?> getEntry(String entryId) => _localService.getEntry(entryId);

  Future<QueueEntry> _requireEntry(String entryId) async {
    final entry = await _localService.getEntry(entryId);
    if (entry == null) {
      throw const QueueValidationException('No queue entry found.');
    }
    return entry;
  }

  Future<void> _updateStatus(
    String entryId,
    QueueStatus status, {
    Map<String, dynamic> extra = const {},
  }) {
    return _localService.updateEntry(entryId, {
      'status': status.value,
      'updatedAt': DateTime.now(),
      ...extra,
    });
  }
}
