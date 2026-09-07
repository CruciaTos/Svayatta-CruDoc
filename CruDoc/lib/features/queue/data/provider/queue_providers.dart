import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/repo/queue_repository.dart';

final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(),
);

// =============================================================================
// SUPER ADMIN FEATURE GATING PROVIDERS
// =============================================================================

/// Streams real-time list of enabled module keys for the current doctor.
final doctorEnabledModulesStreamProvider = StreamProvider<List<String>>((ref) {
  ref.watch(authStateProvider);
  return DoctorFeatureGuard.watchEnabledModules();
});

/// Reactive check if Walk-in Queue feature is enabled by Super Admin.
final isQueueFeatureEnabledProvider = Provider<bool>((ref) {
  final modules = ref.watch(doctorEnabledModulesStreamProvider).value ??
      DoctorFeatureGuard.defaultModules;
  return DoctorFeatureGuard.isEnabled(modules, 'queue');
});

/// Reactive check if Appointments feature is enabled by Super Admin.
final isAppointmentsFeatureEnabledProvider = Provider<bool>((ref) {
  final modules = ref.watch(doctorEnabledModulesStreamProvider).value ??
      DoctorFeatureGuard.defaultModules;
  return DoctorFeatureGuard.isEnabled(modules, 'appointments');
});

// =============================================================================
// FILTER ENUMS & STATE PROVIDERS
// =============================================================================

/// Time period filter presets for the queue.
enum QueuePeriod {
  today('Today'),
  tomorrow('Tomorrow'),
  thisWeek('This Week'),
  custom('Custom Date');

  final String label;
  const QueuePeriod(this.label);
}

/// Time-of-day session slot filter for triage and OPD management.
enum QueueSessionFilter {
  all('All Day'),
  morning('Morning (8am - 12pm)'),
  afternoon('Afternoon (12pm - 5pm)'),
  evening('Evening (5pm - 9pm)');

  final String label;
  const QueueSessionFilter(this.label);
}

/// Patient source filter: all, pure walk-ins, or pre-booked appointments.
enum QueueSourceFilter {
  all('All Patients'),
  walkInOnly('Walk-ins Only'),
  prebookedOnly('Pre-booked Only');

  final String label;
  const QueueSourceFilter(this.label);
}

final queuePeriodProvider = StateProvider<QueuePeriod>((ref) => QueuePeriod.today);
final queueCustomDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);
final queueSessionFilterProvider = StateProvider<QueueSessionFilter>((ref) => QueueSessionFilter.all);
final queueSourceFilterProvider = StateProvider<QueueSourceFilter>((ref) => QueueSourceFilter.all);

/// Resolved boundary dates for the currently selected [QueuePeriod].
class DateBounds {
  final DateTime start;
  final DateTime end;
  final String label;

  const DateBounds({
    required this.start,
    required this.end,
    required this.label,
  });
}

final activeQueueDateBoundsProvider = Provider<DateBounds>((ref) {
  final period = ref.watch(queuePeriodProvider);
  final customRange = ref.watch(queueCustomDateRangeProvider);
  final now = DateTime.now();

  return switch (period) {
    QueuePeriod.today => DateBounds(
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        label: 'Today',
      ),
    QueuePeriod.tomorrow => () {
        final tomorrow = now.add(const Duration(days: 1));
        return DateBounds(
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
          end: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23, 59, 59),
          label: 'Tomorrow',
        );
      }(),
    QueuePeriod.thisWeek => () {
        final weekday = now.weekday; // 1 = Mon, 7 = Sun
        final monday = now.subtract(Duration(days: weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        return DateBounds(
          start: DateTime(monday.year, monday.month, monday.day),
          end: DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59),
          label: 'This Week',
        );
      }(),
    QueuePeriod.custom => customRange != null
        ? DateBounds(
            start: DateTime(customRange.start.year, customRange.start.month, customRange.start.day),
            end: DateTime(customRange.end.year, customRange.end.month, customRange.end.day, 23, 59, 59),
            label: 'Custom',
          )
        : DateBounds(
            start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day, 23, 59, 59),
            label: 'Custom',
          ),
  };
});

// =============================================================================
// DATA STREAMS & COMBINED MODEL
// =============================================================================

/// Streams all non-deleted queue tokens across all dates in real-time.
final allQueueProvider = StreamProvider<List<QueueEntry>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(queueRepositoryProvider).watchAllQueue();
});

/// Streams today's walk-in queue — kept for legacy/direct callers.
final todaysQueueProvider = StreamProvider<List<QueueEntry>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(queueRepositoryProvider).watchTodaysQueue();
});

/// A [QueueEntry] paired with its resolved [Patient] and optional linked [Visit].
class QueueEntryWithPatient {
  final QueueEntry entry;
  final Patient? patient;
  final Visit? linkedVisit;

  const QueueEntryWithPatient({
    required this.entry,
    required this.patient,
    this.linkedVisit,
  });

  /// True when this entry corresponds to a pre-booked clinic appointment.
  bool get isPrebooked => entry.isPrebooked || linkedVisit != null;

  /// The scheduled appointment time if pre-booked.
  DateTime? get appointmentTime => linkedVisit?.scheduledStart ?? (entry.isPrebooked ? entry.checkedInAt : null);

  /// Best available display name: linked patient's name, walk-in name, or fallback.
  String get displayName {
    final patientName = patient?.fullName.trim() ?? '';
    if (patientName.isNotEmpty) return patientName;
    final walkInName = entry.walkInName?.trim() ?? '';
    if (walkInName.isNotEmpty) return walkInName;
    return isPrebooked ? 'Pre-booked Patient' : 'Walk-in';
  }
}

bool _matchesSession(DateTime time, QueueSessionFilter session) {
  switch (session) {
    case QueueSessionFilter.all:
      return true;
    case QueueSessionFilter.morning:
      return time.hour >= 6 && time.hour < 12;
    case QueueSessionFilter.afternoon:
      return time.hour >= 12 && time.hour < 17;
    case QueueSessionFilter.evening:
      return time.hour >= 17 && time.hour < 23;
  }
}

bool _matchesSource(QueueEntryWithPatient item, QueueSourceFilter source) {
  switch (source) {
    case QueueSourceFilter.all:
      return true;
    case QueueSourceFilter.walkInOnly:
      return !item.isPrebooked;
    case QueueSourceFilter.prebookedOnly:
      return item.isPrebooked;
  }
}

/// Unified reactive queue provider:
/// 1. Filters queue entries to the selected [QueuePeriod] bounds.
/// 2. If Appointments feature is enabled by Super Admin, seamlessly checks in / links
///    pre-booked clinic visits for that period so they appear with badges & timing.
/// 3. Applies [QueueSessionFilter] (morning/afternoon/evening) and [QueueSourceFilter].
final periodQueueWithPatientsProvider =
    Provider<AsyncValue<List<QueueEntryWithPatient>>>((ref) {
  final queueAsync = ref.watch(allQueueProvider);
  final patientsAsync = ref.watch(patientsStreamProvider);
  final bounds = ref.watch(activeQueueDateBoundsProvider);
  final sessionFilter = ref.watch(queueSessionFilterProvider);
  final sourceFilter = ref.watch(queueSourceFilterProvider);
  final isAppointmentsEnabled = ref.watch(isAppointmentsFeatureEnabledProvider);

  // If appointments enabled, also watch allVisitsProvider
  final AsyncValue<List<Visit>>? visitsAsync =
      isAppointmentsEnabled ? ref.watch(allVisitsProvider) : null;

  if (queueAsync.isLoading || patientsAsync.isLoading || (visitsAsync != null && visitsAsync.isLoading)) {
    return const AsyncValue.loading();
  }
  if (queueAsync.hasError) {
    return AsyncValue.error(queueAsync.error!, queueAsync.stackTrace!);
  }
  if (patientsAsync.hasError) {
    return AsyncValue.error(patientsAsync.error!, patientsAsync.stackTrace!);
  }
  if (visitsAsync != null && visitsAsync.hasError) {
    return AsyncValue.error(visitsAsync.error!, visitsAsync.stackTrace!);
  }

  final allEntries = queueAsync.value!.where((e) => !e.isDeleted).toList();
  final patientsById = {for (final p in patientsAsync.value!) p.id: p};
  final allVisits = (visitsAsync?.value ?? const <Visit>[]).where((v) => !v.isDeleted).toList();
  final visitsById = {for (final v in allVisits) v.id: v};

  // 1. Filter existing SQLite queue entries within the active date bounds
  final periodEntries = allEntries.where((e) {
    final entryTime = e.checkedInAt;
    return !entryTime.isBefore(bounds.start) && !entryTime.isAfter(bounds.end);
  }).toList();

  final Map<String, QueueEntryWithPatient> combinedByTokenId = {};

  for (final entry in periodEntries) {
    final linkedVisit = entry.linkedVisitId != null ? visitsById[entry.linkedVisitId] : null;
    final patient = entry.patientId != null ? patientsById[entry.patientId] : null;
    combinedByTokenId[entry.id] = QueueEntryWithPatient(
      entry: entry,
      patient: patient,
      linkedVisit: linkedVisit,
    );
  }

  // 2. If appointments feature is enabled, find any clinic visits in the period
  // that do not yet have a queue entry and ensure/synthesize them into the queue.
  if (isAppointmentsEnabled) {
    final queuedVisitIds = periodEntries
        .map((e) => e.linkedVisitId)
        .whereType<String>()
        .toSet();

    final clinicVisitsInPeriod = allVisits.where((v) {
      if (v.visitType != VisitType.clinic) return false;
      final start = v.scheduledStart;
      return !start.isBefore(bounds.start) && !start.isAfter(bounds.end);
    }).toList();

    for (final visit in clinicVisitsInPeriod) {
      if (!queuedVisitIds.contains(visit.id)) {
        // Auto-register with QueueRepository in background so SQLite assigns official token
        unawaited(
          ref.read(queueRepositoryProvider).checkInVisit(visit),
        );

        // Pre-render immediately in memory until SQLite reactive re-emit
        final tempEntry = QueueEntry(
          id: 'queue_appt_${visit.id}',
          doctorId: visit.doctorId,
          patientId: visit.patientId,
          tokenNumber: 0,
          queueDate: queueDateKeyFor(visit.scheduledStart),
          status: visit.status == VisitStatus.completed
              ? QueueStatus.completed
              : (visit.status == VisitStatus.cancelled
                  ? QueueStatus.cancelled
                  : QueueStatus.waiting),
          priority: QueuePriority.normal,
          reason: visit.treatmentType ?? visit.therapistNotes ?? 'Pre-booked Appointment',
          checkedInAt: visit.scheduledStart,
          linkedVisitId: visit.id,
          createdAt: visit.createdAt,
          updatedAt: visit.updatedAt,
        );

        combinedByTokenId[tempEntry.id] = QueueEntryWithPatient(
          entry: tempEntry,
          patient: patientsById[visit.patientId],
          linkedVisit: visit,
        );
      }
    }
  }

  // 3. Apply session (time-of-day) and source (walk-in vs prebooked) filters
  final filtered = combinedByTokenId.values.where((item) {
    final time = item.appointmentTime ?? item.entry.checkedInAt;
    if (!_matchesSession(time, sessionFilter)) return false;
    if (!_matchesSource(item, sourceFilter)) return false;
    return true;
  }).toList();

  return AsyncValue.data(filtered);
});

/// Drop-in replacement for [todaysQueueWithPatientsProvider] so all existing
/// screens automatically benefit from the connected appointments and period filters.
final todaysQueueWithPatientsProvider = periodQueueWithPatientsProvider;

int _priorityRank(QueuePriority priority) =>
    priority == QueuePriority.urgent ? 0 : 1;

/// The token currently being served ([QueueStatus.called] or
/// [QueueStatus.inConsultation]), if any.
final activeQueueEntryProvider = Provider<QueueEntryWithPatient?>((ref) {
  final combined = ref.watch(periodQueueWithPatientsProvider).value ?? const [];
  for (final item in combined) {
    if (item.entry.isActiveServing) return item;
  }
  return null;
});

/// Tokens still [QueueStatus.waiting], in call order — urgent tokens
/// first, then lowest token number (with unassigned pre-booked tokens ordered by scheduled time).
final waitingQueueProvider = Provider<List<QueueEntryWithPatient>>((ref) {
  final combined = ref.watch(periodQueueWithPatientsProvider).value ?? const [];
  final waiting =
      combined.where((i) => i.entry.status == QueueStatus.waiting).toList()
        ..sort((a, b) {
          final rankCompare = _priorityRank(
            a.entry.priority,
          ).compareTo(_priorityRank(b.entry.priority));
          if (rankCompare != 0) return rankCompare;

          // If both have assigned token numbers, order by token number
          if (a.entry.tokenNumber > 0 && b.entry.tokenNumber > 0) {
            return a.entry.tokenNumber.compareTo(b.entry.tokenNumber);
          }

          // Otherwise order by scheduled / check-in time
          final timeA = a.appointmentTime ?? a.entry.checkedInAt;
          final timeB = b.appointmentTime ?? b.entry.checkedInAt;
          return timeA.compareTo(timeB);
        });
  return waiting;
});

/// Tokens already resolved ([QueueStatus.completed], [QueueStatus.skipped],
/// or [QueueStatus.cancelled]), most recently updated first.
final resolvedQueueProvider = Provider<List<QueueEntryWithPatient>>((ref) {
  final combined = ref.watch(periodQueueWithPatientsProvider).value ?? const [];
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
