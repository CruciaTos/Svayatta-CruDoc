import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/utils/search_normalisation.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/schedule_visit_sheet.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/desktop_add_edit_patient_dialog.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_recording_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the Patients list, preview pane and Patient details can do to a
/// patient. Every action goes through an existing repository, sheet or
/// dialog; nothing here touches SQLite or Firestore directly.
abstract final class PatientActions {
  /// Dials the patient's phone.
  static Future<void> call(BuildContext context, Patient p) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final digits = normalizePhoneDigits(p.phone);
    if (digits.isEmpty) {
      _say(messenger, 'No phone number on file for ${p.fullName}.');
      return;
    }
    var ok = false;
    try {
      ok = await launchUrl(Uri(scheme: 'tel', path: digits));
    } catch (_) {
      ok = false;
    }
    if (!ok) _say(messenger, "Couldn't start a call on this device.");
  }

  /// Opens a WhatsApp chat with the patient, optionally with [message]
  /// already typed.
  static Future<void> whatsApp(
    BuildContext context,
    Patient p, {
    String? message,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(
      rawPhone: p.phone,
      message: message ?? '',
    );
    if (uri == null) {
      _say(messenger, "${p.fullName}'s phone number can't be used for WhatsApp.");
      return;
    }
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) _say(messenger, "Couldn't open WhatsApp.");
  }

  /// Books a visit for the patient.
  static Future<void> newVisit(
    BuildContext context,
    WidgetRef ref,
    Patient p,
  ) async {
    await showScheduleVisitSheet(
      context,
      patient: p,
      visitRepository: ref.read(visitRepositoryProvider),
    );
  }

  /// Records a payment against the package balance: lowers
  /// `Patient.packageBalance` and adds an income entry to Revenue.
  static Future<void> recordPayment(
    BuildContext context,
    WidgetRef ref,
    PatientSummary s,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final patients = ref.read(patientRepositoryProvider);
    final revenue = ref.read(revenueRepositoryProvider);
    final result = await showDialog<PaymentInput>(
      context: context,
      builder: (_) => RecordPaymentDialog(summary: s),
    );
    if (result == null) return;
    final now = DateTime.now();
    try {
      await revenue.createRevenueEntry(RevenueEntry(
        id: '',
        date: now,
        description: result.note.isEmpty
            ? 'Package payment'
            : 'Package payment · ${result.note}',
        amount: result.amount,
        type: RevenueType.miscellaneous,
        payer: s.name,
        patientId: s.id,
        createdAt: now,
        updatedAt: now,
      ));
      await patients.updatePatient(s.id, {
        'packageBalance': math.max(0, s.balance - result.amount).toDouble(),
      });
      _say(messenger,
          'Recorded ${PatientFormat.rupees(result.amount)} from ${s.name}.');
    } catch (e) {
      _say(messenger, "Couldn't record the payment: $e");
    }
  }

  static Future<void> addPatient(BuildContext context, WidgetRef ref) async {
    await showDesktopAddEditPatientDialog(
      context,
      repository: ref.read(patientRepositoryProvider),
    );
  }

  static Future<void> edit(
    BuildContext context,
    WidgetRef ref,
    Patient p,
  ) async {
    await showDesktopAddEditPatientDialog(
      context,
      patient: p,
      repository: ref.read(patientRepositoryProvider),
    );
  }

  /// Opens the session sheet so a past visit can be marked done, missed
  /// or cancelled.
  static Future<void> updateVisit(
    BuildContext context,
    Visit v,
    Patient p,
  ) =>
      showSessionDetailsSheet(context, VisitWithPatient(visit: v, patient: p));

  /// Asks, then soft-deletes the patient. True when deleted.
  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref,
    Patient p,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repo = ref.read(patientRepositoryProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => PatientDialog(
        title: 'Delete ${p.fullName}?',
        body: Text(
          'Their record and visits are removed from your patient list.',
          style: CruType.text.tint(ctx.cru.label2),
        ),
        cancelLabel: 'Keep patient',
        confirmLabel: 'Delete patient',
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (confirmed != true) return false;
    try {
      await repo.deletePatient(p.id);
      _say(messenger, '${p.fullName} deleted.');
      return true;
    } catch (e) {
      _say(messenger, "Couldn't delete ${p.fullName}: $e");
      return false;
    }
  }

  /// Opens Scribe for today's visit. Scribe records against a visit, so
  /// without one today it says how to get one.
  static Future<void> dictate(
    BuildContext context,
    PatientSummary s,
    DateTime now,
  ) async {
    final visit = todaysVisit(s, now);
    if (visit == null) {
      _say(ScaffoldMessenger.maybeOf(context),
          "Scribe records against a visit. Add today's visit with New visit first.");
      return;
    }
    await showScribeFlow(context, visit: visit, patient: s.patient);
  }

  /// Today's visit for the patient (not cancelled), if any.
  static Visit? todaysVisit(PatientSummary s, DateTime now) {
    for (final v in s.visits) {
      if (v.status == VisitStatus.cancelled) continue;
      if (PatientsBuilder.daysSince(v.scheduledStart, now) == 0) return v;
    }
    return null;
  }

  static String paymentReminderText(PatientSummary s, {String? clinicName}) =>
      'Hello ${_firstName(s)}, a friendly reminder from ${_clinic(clinicName)} '
      'that ${PatientFormat.rupees(s.balance)} is due. Thank you.';

  static String followUpReminderText(PatientSummary s, {String? clinicName}) =>
      'Hello ${_firstName(s)}, this is ${_clinic(clinicName)}. It is time for '
      'your follow-up visit. Please reply to book a time that suits you. '
      'Thank you.';

  static void importUnavailable(BuildContext context) => _say(
        ScaffoldMessenger.maybeOf(context),
        "Import and export aren't available yet.",
      );

  static String _firstName(PatientSummary s) {
    final f = s.patient.firstName.trim();
    return f.isNotEmpty ? f : s.name.trim();
  }

  static String _clinic(String? name) {
    final n = name?.trim();
    return n == null || n.isEmpty ? 'your clinic' : n;
  }

  static void _say(ScaffoldMessengerState? messenger, String text) =>
      messenger?.showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
}
