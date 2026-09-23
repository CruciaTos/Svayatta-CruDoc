import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/desktop_schedule_visit_dialog.dart';
import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/appointments/presentation/reschedule_visit_dialog.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';

/// Entry points shared by the Day, Week, Month and Agenda views.
abstract final class ApptActions {
  /// Existing dialogs were built for the Day palette, so they open from
  /// the root navigator (as the dashboard does).
  static BuildContext _root(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).context;

  /// Opens New appointment (patient picker, then the schedule dialog).
  /// [start] prefills date and time (empty-time click, open-slot chip);
  /// [day] prefills only the date (Month "Book on this day").
  static Future<void> newAppointment(
    BuildContext context,
    WidgetRef ref, {
    DateTime? day,
    DateTime? start,
  }) async {
    final root = _root(context);
    final patient = await showPatientPickerDialog(
      root,
      title: 'Choose a patient',
    );
    if (patient == null || !root.mounted) return;
    await showDesktopScheduleVisitDialog(
      root,
      patient: patient,
      visitRepository: ref.read(visitRepositoryProvider),
      initialDate: start != null
          ? ApptsBuilder.dateOnly(start)
          : (day == null ? null : ApptsBuilder.dateOnly(day)),
      initialStart: start,
    );
  }

  /// Opens the existing visit details screen for [item].
  static Future<void> openVisit(BuildContext context, ApptItem item) =>
      showSessionDetailsSheet(
        _root(context),
        VisitWithPatient(visit: item.visit, patient: item.patient),
      );

  /// Opens Reschedule for [item] (inline 4-at-once error + next free slot).
  static Future<void> reschedule(
    BuildContext context,
    WidgetRef ref,
    ApptItem item,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final moved = await showRescheduleVisitDialog(context, item: item);
    if (moved == null) return;
    final when = ApptsBuilder.sameDay(moved, item.start)
        ? ApptFormat.time(moved)
        : '${ApptFormat.time(moved)}, ${ApptFormat.dateLine(moved)}';
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Moved ${item.name} to $when'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
