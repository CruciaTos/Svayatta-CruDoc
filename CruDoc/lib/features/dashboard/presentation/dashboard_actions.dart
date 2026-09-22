import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:doctor_management_app/features/chatbot/presentation/chatbot_screen.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/desktop_patient_details_screen.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/queue/presentation/check_in_dialog.dart';

/// Desktop tab indices (see DesktopShell). Kept in one place so the
/// dashboard can jump to a screen.
abstract final class DesktopTab {
  static const dashboard = 0;
  static const patients = 1;
  static const inventory = 2;
  static const revenue = 3;
  static const appointments = 4;
  static const campaigns = 5;
  static const scribe = 6;
  static const queue = 7;
}

/// What the dashboard can do. Existing dialogs and screens were built
/// for the Day palette, so they are opened from the root navigator's
/// context: they pick up the app (Day) theme even in the evening.
abstract final class DashboardActions {
  static BuildContext _root(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).context;

  static Future<void> addPatient(BuildContext context) =>
      showAddPatientSheet(_root(context));

  /// Checks a patient or walk-in into today's queue.
  static Future<void> newVisit(BuildContext context) =>
      CheckInDialog.show(_root(context));

  /// "Ask CruDoc": the assistant that used to sit behind the floating
  /// chat button.
  static Future<void> openAssistant(BuildContext context, [String? prompt]) =>
      ChatbotScreen.show(_root(context), initialPrompt: prompt);

  static void openPatient(BuildContext context, Patient patient) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => DesktopPatientDetailsScreen(patient: patient),
      ),
    );
  }

  /// Calls the Up next token and starts the consultation.
  ///
  /// The repository can only call the next token in its own order
  /// (`callNext`). When that isn't the Up next patient (for example a
  /// booked visit with a lower token number hasn't arrived yet), the
  /// doctor is sent to the Queue screen instead of calling someone else.
  static Future<void> startConsultation(
    BuildContext context,
    WidgetRef ref,
    UpNextData upNext, {
    required ValueChanged<int> navigate,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    void say(String m) => messenger?.showSnackBar(
          SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
        );

    if (upNext.servingName != null) {
      say('Finish the consultation with ${upNext.servingName} first.');
      navigate(DesktopTab.queue);
      return;
    }
    if (!upNext.isNextInCallOrder) {
      say('Another token is ahead in the queue order. Call ${upNext.name} '
          'from the Queue screen.');
      navigate(DesktopTab.queue);
      return;
    }
    final repo = ref.read(queueRepositoryProvider);
    try {
      final called = await repo.callNext();
      await repo.startConsultation(called.id);
      say('Started consultation with ${upNext.name}.');
    } on QueueException catch (e) {
      say(e.message);
    } catch (e) {
      say('Could not start the consultation: $e');
    }
  }

  static Future<void> skip(BuildContext context, WidgetRef ref, UpNextData u) =>
      _run(context, () => ref.read(queueRepositoryProvider).skip(u.entryId),
          '${u.name} moved out of the line. Requeue from the Queue screen.');

  static Future<void> cancel(
          BuildContext context, WidgetRef ref, UpNextData u) =>
      _run(context, () => ref.read(queueRepositoryProvider).cancel(u.entryId),
          'Token cancelled for ${u.name}.');

  static Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      messenger?.showSnackBar(SnackBar(
        content: Text(done),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
        content: Text('$e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}
