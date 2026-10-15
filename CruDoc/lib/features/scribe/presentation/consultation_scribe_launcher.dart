import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/router/app_router.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/repo/queue_repository.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_recording_sheet.dart';

/// The session-note specialty the scribe records automatically for a
/// doctor of [type], or null when consultations aren't recorded on start.
String? autoScribeSpecialtyFor(DoctorSpecialtyType type) => switch (type) {
  DoctorSpecialtyType.homeopathy => SessionSpecialty.homeopathy,
  DoctorSpecialtyType.physiotherapy => SessionSpecialty.physiotherapy,
  _ => null,
};

/// Visit id the scribe keeps a walk-in's draft under. A walk-in token has
/// no visit of its own, and none is created: an appointment that nobody
/// booked would show up in the schedule.
String walkInVisitIdFor(String queueEntryId) => 'queue_$queueEntryId';

/// Opens the AI scribe as soon as a consultation starts on this device —
/// from the queue, the dashboard's Up next card or the mobile island — for
/// homeopathy and physiotherapy practices.
///
/// Sits above the app's Navigator (MaterialApp.builder), like VoiceOverlay,
/// so the scribe is opened from the router's navigator.
class ConsultationScribeLauncher extends ConsumerStatefulWidget {
  const ConsultationScribeLauncher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ConsultationScribeLauncher> createState() =>
      _ConsultationScribeLauncherState();
}

class _ConsultationScribeLauncherState
    extends ConsumerState<ConsultationScribeLauncher> {
  StreamSubscription<QueueEntry>? _sub;

  /// A scribe is open (or opening): a second start leaves it alone.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sub = QueueRepository.consultationStarts.listen(_onStarted);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onStarted(QueueEntry entry) async {
    if (_busy) return;
    _busy = true;
    try {
      await _launch(entry);
    } catch (e) {
      debugPrint('[ScribeLauncher] Could not open the scribe: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _launch(QueueEntry entry) async {
    final specialty = await _sessionSpecialty();
    if (specialty == null) return;

    // Only someone who writes clinical records is seeing the patient; a
    // receptionist calling the token in doesn't get a recorder.
    final access = ClinicSession.instance.access;
    if (access != null && !access.can(ClinicPermission.clinicalEdit)) return;

    final patientId = entry.patientId;
    if (patientId == null || patientId.isEmpty) {
      final name = entry.walkInName?.trim();
      _say(
        'Register ${name == null || name.isEmpty ? 'this walk-in' : name} '
        'as a patient to keep session notes.',
      );
      return;
    }

    final patient = await ref
        .read(patientRepositoryProvider)
        .getPatient(patientId);
    final visit = await _visitFor(entry, patientId);

    final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
    if (!mounted || navContext == null || !navContext.mounted) return;
    await showScribeFlow(
      navContext,
      visit: visit,
      patient: patient,
      specialty: specialty,
      queueEntryId: entry.id,
      tokenNumber: entry.tokenNumber,
    );
  }

  Future<String?> _sessionSpecialty() async {
    try {
      final specialty =
          ref.read(activeDoctorSpecialtyProvider).value ??
          await ref
              .read(activeDoctorSpecialtyProvider.future)
              .timeout(const Duration(seconds: 5));
      return autoScribeSpecialtyFor(specialty.type);
    } on TimeoutException {
      return null;
    }
  }

  /// The pre-booked visit the token is for, or a stand-in for a walk-in.
  Future<Visit> _visitFor(QueueEntry entry, String patientId) async {
    final linked = entry.linkedVisitId;
    if (linked != null && linked.isNotEmpty) {
      final visit = await ref.read(visitRepositoryProvider).getVisit(linked);
      if (visit != null) return visit;
    }
    final now = DateTime.now();
    return Visit(
      id: walkInVisitIdFor(entry.id),
      doctorId: entry.doctorId,
      patientId: patientId,
      scheduledStart: entry.consultationStartedAt ?? now,
      durationMinutes: 0,
      address: '',
      status: VisitStatus.scheduled,
      attendingDoctorUid: entry.attendingDoctorUid,
      createdAt: now,
      updatedAt: now,
    );
  }

  void _say(String message) {
    final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
