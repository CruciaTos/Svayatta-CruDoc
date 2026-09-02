import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/repo/queue_repository.dart';

final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(),
);

/// Streams today's walk-in queue — every non-deleted token for today,
/// in every status, urgent-first then by token number.
final todaysQueueProvider = StreamProvider<List<QueueEntry>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(queueRepositoryProvider).watchTodaysQueue();
});

/// A [QueueEntry] paired with its resolved [Patient] — null for a
/// walk-in that isn't linked to a registered patient. Mirrors
/// `VisitWithPatient` in visit_providers.dart.
class QueueEntryWithPatient {
  final QueueEntry entry;
  final Patient? patient;
  const QueueEntryWithPatient({required this.entry, required this.patient});

  /// Best available display name: the linked patient's name, the
  /// walk-in name captured at check-in, or a final fallback — a queue
  /// entry alone never stores a name directly (see [QueueEntry]'s doc),
  /// so this is the one place that join happens for display.
  String get displayName {
    final patientName = patient?.fullName.trim() ?? '';
    if (patientName.isNotEmpty) return patientName;
    final walkInName = entry.walkInName?.trim() ?? '';
    if (walkInName.isNotEmpty) return walkInName;
    return 'Walk-in';
  }
}

/// Joins [todaysQueueProvider] with the patients feature's existing
/// `patientsStreamProvider`, so screens never need their own patient
/// lookups.
final todaysQueueWithPatientsProvider =
    Provider<AsyncValue<List<QueueEntryWithPatient>>>((ref) {
  final queueAsync = ref.watch(todaysQueueProvider);
  final patientsAsync = ref.watch(patientsStreamProvider);

  if (queueAsync.isLoading || patientsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (queueAsync.hasError) {
    return AsyncValue.error(queueAsync.error!, queueAsync.stackTrace!);
  }
  if (patientsAsync.hasError) {
    return AsyncValue.error(patientsAsync.error!, patientsAsync.stackTrace!);
  }

  final entries = queueAsync.value!.where((e) => !e.isDeleted).toList();
  final patientsById = {for (final p in patientsAsync.value!) p.id: p};

  final combined = entries
      .map(
        (e) => QueueEntryWithPatient(
          entry: e,
          patient: e.patientId == null ? null : patientsById[e.patientId],
        ),
      )
      .toList();

  return AsyncValue.data(combined);
});

int _priorityRank(QueuePriority priority) =>
    priority == QueuePriority.urgent ? 0 : 1;

/// The token currently being served ([QueueStatus.called] or
/// [QueueStatus.inConsultation]), if any. Only one can be active at a
/// time — see `QueueRepository.callNext`.
final activeQueueEntryProvider = Provider<QueueEntryWithPatient?>((ref) {
  final combined = ref.watch(todaysQueueWithPatientsProvider).value ?? const [];
  for (final item in combined) {
    if (item.entry.isActiveServing) return item;
  }
  return null;
});

/// Tokens still [QueueStatus.waiting], in call order — urgent tokens
/// first, then lowest token number.
final waitingQueueProvider = Provider<List<QueueEntryWithPatient>>((ref) {
  final combined = ref.watch(todaysQueueWithPatientsProvider).value ?? const [];
  final waiting =
      combined.where((i) => i.entry.status == QueueStatus.waiting).toList()
        ..sort((a, b) {
          final rankCompare = _priorityRank(
            a.entry.priority,
          ).compareTo(_priorityRank(b.entry.priority));
          if (rankCompare != 0) return rankCompare;
          return a.entry.tokenNumber.compareTo(b.entry.tokenNumber);
        });
  return waiting;
});

/// Tokens already resolved today ([QueueStatus.completed],
/// [QueueStatus.skipped], or [QueueStatus.cancelled]), most recently
/// updated first.
final resolvedQueueProvider = Provider<List<QueueEntryWithPatient>>((ref) {
  final combined = ref.watch(todaysQueueWithPatientsProvider).value ?? const [];
  final resolved =
      combined
          .where(
            (i) =>
                i.entry.status == QueueStatus.completed ||
                i.entry.status == QueueStatus.skipped ||
                i.entry.status == QueueStatus.cancelled,
          )
          .toList()
        ..sort((a, b) => b.entry.updatedAt.compareTo(a.entry.updatedAt));
  return resolved;
});
