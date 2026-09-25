import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:doctor_management_app/features/chatbot/presentation/chatbot_screen.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_details_view.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/queue/presentation/check_in_dialog.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';

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

  /// Not in the sidebar: opened from the account menu.
  static const settings = 8;

  /// Dentists only.
  static const treatmentPlans = 9;
  static const sterilization = 10;
  static const procedures = 11;

  static bool isDental(int tab) =>
      tab == treatmentPlans ||
      tab == sterilization ||
      tab == procedures ||
      tab == recalls ||
      tab == perioPatients ||
      tab == rootCanals ||
      tab == dentalReferrals ||
      tab == pedoChildren ||
      tab == biopsies ||
      tab == oralMedLesions ||
      tab == oralMedForms ||
      tab == sedationCases ||
      tab == labCases ||
      tab == orthoPatients ||
      tab == healthCamps ||
      tab == population ||
      tab == surgeries ||
      tab == implants;

  /// Dentists: who should come back.
  static const recalls = 15;

  /// Periodontists only: their patient list, scoped to periodontal care.
  static const perioPatients = 16;

  /// Endodontists only.
  static const rootCanals = 17;
  static const dentalReferrals = 18;

  /// Pediatric dentists only.
  static const pedoChildren = 19;

  /// Oral & Maxillofacial Pathologists only.
  static const biopsies = 20;

  /// Oral Medicine Specialists only.
  static const oralMedLesions = 21;
  static const oralMedForms = 22;

  /// Dental Anesthesiologists only.
  static const sedationCases = 23;

  /// Prosthodontists only.
  static const labCases = 24;

  /// Orthodontists only.
  static const orthoPatients = 25;

  /// Public Health Dentists only.
  static const healthCamps = 26;
  static const population = 27;

  /// Oral & Maxillofacial Surgeons only.
  static const surgeries = 28;
  static const implants = 29;

  /// Oral & Maxillofacial Radiologists only.
  static const worklist = 12;
  static const reports = 13;
  static const referrers = 14;

  static bool isRadiology(int tab) =>
      tab == worklist || tab == reports || tab == referrers;

  /// Sidebar name, for "‹ Schedule" style back links.
  static String label(int tab) => switch (tab) {
        dashboard => 'Dashboard',
        patients => 'Patients',
        inventory => 'Inventory',
        revenue => 'Revenue',
        appointments || queue => 'Schedule',
        campaigns => 'Campaigns',
        scribe => 'Scribe',
        settings => 'Settings',
        treatmentPlans => 'Treatment plans',
        sterilization => 'Sterilization',
        procedures => 'Procedures',
        worklist => 'Worklist',
        reports => 'Reports',
        referrers => 'Referrers',
        recalls => 'Recalls',
        perioPatients => 'Perio patients',
        rootCanals => 'Root canals',
        dentalReferrals => 'Referrals',
        pedoChildren => 'Children',
        biopsies => 'Biopsies',
        oralMedLesions => 'Lesions',
        oralMedForms => 'Forms',
        sedationCases => 'Sedation cases',
        labCases => 'Lab cases',
        orthoPatients => 'Ortho patients',
        healthCamps => 'Camps',
        population => 'Population',
        surgeries => 'Surgeries',
        implants => 'Implants',
        _ => 'Back',
      };
}

/// The desktop shell's tab switch while it is on screen: returns false
/// once the shell is gone. Null outside the desktop shell (the phone).
final shellNavigatorProvider =
    StateProvider<bool Function(int tab)?>((ref) => null);

/// The tab the desktop shell is showing.
final shellCurrentTabProvider = StateProvider<int>((ref) => DesktopTab.dashboard);

/// Where patient details go back to when opened from another screen
/// ("Open patient" in Schedule); null when opened from the Patients list.
final patientDetailsReturnTabProvider = StateProvider<int?>((ref) => null);

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

  /// Patient details. On the desktop they open in the Patients tab with
  /// the sidebar kept (Back returns to the screen they came from); on the
  /// phone they are pushed as a page.
  static void openPatient(BuildContext context, Patient patient) {
    final container = ProviderScope.containerOf(context, listen: false);
    final navigate = container.read(shellNavigatorProvider);
    if (navigate != null) {
      final from = container.read(shellCurrentTabProvider);
      // Close any sheet or dialog the action came from.
      Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
      container.read(patientDetailsReturnTabProvider.notifier).state =
          from == DesktopTab.patients ? null : from;
      container
          .read(patientsListControllerProvider.notifier)
          .openDetails(patient.id);
      if (navigate(DesktopTab.patients)) return;
      container.read(patientDetailsReturnTabProvider.notifier).state = null;
    }
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => PatientDetailsScreen(patientId: patient.id),
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
