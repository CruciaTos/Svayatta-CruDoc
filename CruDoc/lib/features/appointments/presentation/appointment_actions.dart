import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/desktop_schedule_visit_dialog.dart';
import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/appointments/presentation/reschedule_visit_dialog.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/visits/home_visit_links.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';

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
    VisitType type = VisitType.clinic,
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
      initialType: type,
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
    // Read before awaiting: the caller may be gone when the dialog closes.
    final repo = ref.read(visitRepositoryProvider);
    final moved = await showRescheduleVisitDialog(context, item: item);
    if (moved == null) return;
    // Seen together: everyone moves with the lead.
    for (final m in item.members) {
      if (m.id == item.id) continue;
      try {
        await repo.rescheduleVisit(m.id, newStart: moved, acknowledgeOverlap: true);
      } catch (_) {}
    }
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

  static bool canReschedule(ApptItem item) =>
      item.status == ApptStatus.booked ||
      item.status == ApptStatus.waiting ||
      item.status == ApptStatus.missed;

  static bool canCancel(ApptItem item) =>
      item.status == ApptStatus.booked || item.status == ApptStatus.waiting;

  /// Asks, then cancels [item] and clears the selection.
  static Future<void> cancel(
    BuildContext context,
    WidgetRef ref,
    ApptItem item,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Read before awaiting: the caller may be gone when the dialog closes.
    final repo = ref.read(visitRepositoryProvider);
    final controller = ref.read(apptsControllerProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PatientDialog(
        title: item.isGroup
            ? 'Cancel this appointment for everyone?'
            : 'Cancel this appointment?',
        cancelLabel: 'Keep it',
        confirmLabel: 'Cancel appointment',
        onConfirm: () => Navigator.of(ctx).pop(true),
        body: Text(
          '${item.name} · ${ApptFormat.range(item.start, item.end)}, '
          '${ApptFormat.dateLine(item.start)}',
          style: CruType.text.tabular.tint(ctx.cru.label2),
        ),
      ),
    );
    if (ok != true) return;
    try {
      for (final v in item.visits) {
        await repo.cancelVisit(v.id);
      }
      controller.select(null);
      messenger?.showSnackBar(
        SnackBar(
          content: Text("Cancelled ${item.name}'s appointment"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text("Couldn't cancel the appointment. Try again."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// "Who else is coming?": adds a patient to [item]'s appointment (same
  /// slot, place and queue token), with their own reason.
  static Future<void> addPatient(
    BuildContext context,
    WidgetRef ref,
    ApptItem item,
  ) async {
    final root = _root(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repo = ref.read(visitRepositoryProvider);
    final queue = ref.read(queueRepositoryProvider);
    final patient = await showPatientPickerDialog(root, title: 'Who else is coming?');
    if (patient == null || !root.mounted) return;
    if (item.visits.any((v) => v.patientId == patient.id)) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('${patient.firstName} is already on this appointment'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final reason = await _askReason(root, patient.firstName);
    if (reason == null) return;
    final now = DateTime.now();
    try {
      final added = await repo.addToGroup(
        item.visit,
        Visit(
          id: '',
          patientId: patient.id,
          scheduledStart: item.start,
          durationMinutes: item.visit.durationMinutes,
          address: item.visit.address,
          visitType: item.visit.visitType,
          status: VisitStatus.scheduled,
          treatmentType: reason.trim().isEmpty ? null : reason.trim(),
          createdAt: now,
          updatedAt: now,
        ),
      );
      // Already in today's queue: the new patient shares that token.
      await queue.adoptVisitGroup(
        [for (final v in item.visits) v.id],
        added.groupId,
      );
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Added ${patient.firstName} to ${item.firstName}\'s appointment'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text("Couldn't add ${patient.firstName}: $e"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Takes [member] off [group]'s appointment: their visit is cancelled;
  /// everyone else stays booked.
  static Future<void> removeFromAppointment(
    BuildContext context,
    WidgetRef ref,
    ApptItem group,
    ApptItem member,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repo = ref.read(visitRepositoryProvider);
    final queue = ref.read(queueRepositoryProvider);
    final others = [for (final v in group.visits) if (v.id != member.id) v];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PatientDialog(
        title: 'Take ${member.firstName} off this appointment?',
        cancelLabel: 'Keep',
        confirmLabel: 'Take off',
        onConfirm: () => Navigator.of(ctx).pop(true),
        body: Text(
          "${member.firstName}'s visit is cancelled. The others stay booked.",
          style: CruType.text.tint(ctx.cru.label2),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await queue.leaveTokenForVisit(member.id);
      await repo.leaveGroup(member.visit, others);
      await repo.cancelVisit(member.id);
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text("Couldn't change the appointment. Try again."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Separately booked visits of patients seen together become one
  /// appointment (the overlap card's "Combine").
  static Future<void> combine(
    BuildContext context,
    WidgetRef ref,
    List<ApptItem> items,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repo = ref.read(visitRepositoryProvider);
    final queue = ref.read(queueRepositoryProvider);
    final visits = [for (final i in items) ...i.visits];
    if (visits.length > kMaxGroupPatients) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('One appointment can hold at most $kMaxGroupPatients patients.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      final groupId = await repo.combineVisits(visits);
      await queue.adoptVisitGroup([for (final v in visits) v.id], groupId);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Combined into one appointment'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text("Couldn't combine them: $e"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// One invoice for everyone on a group appointment, billed to the first
  /// patient; each patient is billed on their own visit otherwise.
  static Future<void> billTogether(BuildContext context, ApptItem item) {
    final names = [for (final m in item.members) m.name];
    return showDesktopCreateInvoiceDialog(
      _root(context),
      initialPatient: item.patient,
      initialTreatmentName: 'Consultation · ${names.join(', ')}',
      initialNotes: 'Seen together on ${ApptFormat.dateLine(item.start)}: '
          '${names.join(', ')}.',
    );
  }

  /// "What is Priya coming in for?": null when cancelled, '' when skipped.
  static Future<String?> _askReason(BuildContext context, String firstName) {
    final text = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.cru;
        return Dialog(
          backgroundColor: c.surface,
          surfaceTintColor: c.surface.withValues(alpha: 0),
          shape: cruShape(CruRadius.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: CruSize.dialog),
            child: Padding(
              padding: const EdgeInsets.all(CruSpace.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'What is $firstName coming in for?',
                    style: CruType.headline.tint(c.label),
                  ),
                  const SizedBox(height: CruSpace.s16),
                  CruTextField(
                    label: 'Reason',
                    optional: true,
                    controller: text,
                    autofocus: true,
                    hint: 'Knee pain, follow-up…',
                    onSubmitted: (_) => Navigator.of(ctx).pop(text.text),
                  ),
                  const SizedBox(height: CruSpace.s24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CruButton(
                        label: 'Cancel',
                        kind: CruButtonKind.inset,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                      const SizedBox(width: CruSpace.s10),
                      CruButton(
                        label: 'Add to appointment',
                        onPressed: () => Navigator.of(ctx).pop(text.text),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(text.dispose);
  }

  /// Long-press (touch) or right-click (mouse) on an appointment: its
  /// actions, opened where the finger or pointer is.
  static Future<void> showActionsMenu(
    BuildContext context,
    WidgetRef ref,
    ApptItem item,
    Offset globalPosition,
  ) async {
    final c = context.cru;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = overlay.globalToLocal(globalPosition);
    final directions =
        item.isHomeVisit ? homeVisitDirections(item.visit) : null;
    final patient = item.patient;

    PopupMenuItem<VoidCallback> entry(
      CruIconData icon,
      String label,
      VoidCallback action,
    ) =>
        PopupMenuItem<VoidCallback>(
          value: action,
          // Touch-sized rows: this menu is how tablets reach these actions.
          height: CruSize.actionButton,
          child: Row(
            children: [
              CruIcon(icon, size: 18, color: c.label2),
              const SizedBox(width: CruSpace.s10),
              Text(label, style: CruType.text.tint(c.label)),
            ],
          ),
        );

    final chosen = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
      constraints: const BoxConstraints(minWidth: 220),
      items: [
        entry(CruIcons.arrowUpRight, 'Open details', () => openVisit(context, item)),
        if (canReschedule(item))
          entry(CruIcons.calendar, 'Reschedule', () => reschedule(context, ref, item)),
        if (canReschedule(item) && item.patientCount < kMaxGroupPatients)
          entry(CruIcons.userPlus, 'Add a patient', () => addPatient(context, ref, item)),
        if (item.isGroup)
          entry(CruIcons.rupee, 'Bill together', () => billTogether(context, item)),
        if (directions != null)
          entry(CruIcons.home, 'Directions', () => openHomeVisitLink(directions)),
        if (item.isGroup)
          for (final m in item.members)
            if (m.patient != null)
              entry(
                CruIcons.user,
                'Open ${m.firstName}',
                () => DashboardActions.openPatient(context, m.patient!),
              ),
        if (!item.isGroup && patient != null)
          entry(
            CruIcons.user,
            'Open patient',
            () => DashboardActions.openPatient(context, patient),
          ),
        if (canCancel(item)) ...[
          const PopupMenuDivider(),
          entry(
            CruIcons.close,
            item.isGroup ? 'Cancel for everyone' : 'Cancel appointment',
            () => cancel(context, ref, item),
          ),
        ],
      ],
    );
    if (chosen != null && context.mounted) chosen();
  }
}
