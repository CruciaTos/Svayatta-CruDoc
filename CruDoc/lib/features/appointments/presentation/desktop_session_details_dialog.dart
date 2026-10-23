import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/therapy/presentation/physio_photos_dialog.dart';

/// Opens the desktop-specific Session Details modal popup dialog.
Future<void> showDesktopSessionDetailsDialog(
  BuildContext context,
  VisitWithPatient item,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => DesktopSessionDetailsDialog(initial: item),
  );
}

class DesktopSessionDetailsDialog extends ConsumerStatefulWidget {
  const DesktopSessionDetailsDialog({super.key, required this.initial});

  final VisitWithPatient initial;

  @override
  ConsumerState<DesktopSessionDetailsDialog> createState() =>
      _DesktopSessionDetailsDialogState();
}

class _DesktopSessionDetailsDialogState
    extends ConsumerState<DesktopSessionDetailsDialog> {
  late Visit _visit;
  late final TextEditingController _notesController;
  bool _savingNote = false;
  bool _updatingStatus = false;
  bool _checkingIntoQueue = false;

  Patient? get _patient => widget.initial.patient;
  bool get _isHomeVisit => _visit.visitType == VisitType.home;

  @override
  void initState() {
    super.initState();
    _visit = widget.initial.visit;
    _notesController = TextEditingController(text: _visit.therapistNotes ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool get _isNoteDirty =>
      _notesController.text.trim() != (_visit.therapistNotes ?? '').trim();

  Future<void> _saveNote() async {
    final text = _notesController.text.trim();
    setState(() => _savingNote = true);
    try {
      final repo = ref.read(visitRepositoryProvider);
      await repo.updateVisit(_visit.id, {
        'therapistNotes': text.isEmpty ? null : text,
      });
      final refreshed = await repo.getVisit(_visit.id);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _visit = refreshed;
      });
      ref.invalidate(visitsWithPatientsProvider);
      ref.invalidate(allVisitsWithPatientsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save note: $e')));
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _changeStatus(VisitStatus newStatus) async {
    setState(() => _updatingStatus = true);
    try {
      final repo = ref.read(visitRepositoryProvider);
      await repo.updateStatus(_visit.id, newStatus);
      final refreshed = await repo.getVisit(_visit.id);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _visit = refreshed;
      });
      ref.invalidate(visitsWithPatientsProvider);
      ref.invalidate(allVisitsWithPatientsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (newStatus) {
            VisitStatus.completed => 'Marked as done',
            VisitStatus.cancelled => 'Visit cancelled',
            VisitStatus.missed => 'Marked as missed',
            VisitStatus.scheduled => 'Marked as booked',
          }),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  Future<void> _checkIntoQueue() async {
    setState(() => _checkingIntoQueue = true);
    try {
      final repo = ref.read(queueRepositoryProvider);
      final created = await repo.checkInVisit(_visit);
      if (!mounted) return;
      ref.invalidate(todaysQueueWithPatientsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checked in as token ${created.tokenNumber}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not check into queue: $e')));
    } finally {
      if (mounted) setState(() => _checkingIntoQueue = false);
    }
  }

  Future<void> _deleteVisit() async {
    final confirm = await confirmDental(
      context,
      title: 'Remove this visit?',
      body: 'It is cancelled and taken off the schedule.',
      action: 'Remove',
    );

    if (!confirm) return;

    try {
      final repo = ref.read(visitRepositoryProvider);
      await repo.softDeleteVisit(_visit.id);
      if (!mounted) return;
      ref.invalidate(visitsWithPatientsProvider);
      ref.invalidate(allVisitsWithPatientsProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Appointment removed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _openWhatsApp() async {
    final patient = _patient;
    if (patient == null) return;
    if (!WhatsAppTemplateService.isValidWhatsAppPhone(patient.phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid WhatsApp mobile number for this patient.'),
        ),
      );
      return;
    }
    final message = WhatsAppTemplateService.buildConfirmationMessage(
      visit: _visit,
      patient: patient,
      doctorName: 'Doctor',
    );
    final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(
      rawPhone: patient.phone,
      message: message,
    );
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp.')));
    }
  }

  Future<void> _openMaps() async {
    final urlStr =
        _visit.mapsLink ??
        (_visit.latitude != null && _visit.longitude != null
            ? 'https://www.google.com/maps/search/?api=1&query=${_visit.latitude},${_visit.longitude}'
            : null);
    if (urlStr == null) return;
    final uri = Uri.tryParse(urlStr);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ===========================================================================
  // UI (Calm Clinical; follows Day and Evening)
  // ===========================================================================

  static final _date = DateFormat('EEEE, d MMMM yyyy');
  static final _time = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final patient = _patient;
    final isQueueEnabled = ref.watch(isQueueFeatureEnabledProvider);
    final queueEntries = isQueueEnabled
        ? (ref.watch(todaysQueueWithPatientsProvider).value ?? const [])
        : const <QueueEntryWithPatient>[];
    final queueEntry = queueEntries
        .where((e) => e.entry.linkedVisitId == _visit.id)
        .firstOrNull;
    final showQueue = isQueueEnabled && _visit.visitType == VisitType.clinic;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label('Patient'),
        _panel(_patientPanel(patient)),
        const SizedBox(height: CruSpace.s20),
        _label('When and where'),
        _panel(_whenPanel()),
      ],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showQueue) ...[
          _label('Queue'),
          _panel(_queuePanel(queueEntry)),
          const SizedBox(height: CruSpace.s20),
        ],
        _label('Treatment'),
        _panel(
          Text(
            _visit.treatmentType?.isNotEmpty == true
                ? _visit.treatmentType!
                : 'Consultation',
            style: CruType.callout.tint(c.label),
          ),
        ),
        const SizedBox(height: CruSpace.s20),
        Row(
          children: [
            Expanded(child: _label('Notes')),
            if (_isNoteDirty)
              Padding(
                padding: const EdgeInsets.only(bottom: CruSpace.s8),
                child: CruLink(
                  label: _savingNote ? 'Saving…' : 'Save note',
                  onPressed: _savingNote ? null : _saveNote,
                ),
              ),
          ],
        ),
        TextField(
          controller: _notesController,
          minLines: 3,
          maxLines: 5,
          style: CruType.text.tint(c.label),
          decoration: const InputDecoration(
            hintText: 'Observations, advice or anything to remember',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: CruSpace.s20),
        _label('Status'),
        CruSegmentedControl<VisitStatus>(
          semanticLabel: 'Visit status',
          segments: [
            const CruSegment(VisitStatus.scheduled, 'Booked'),
            const CruSegment(VisitStatus.completed, 'Done'),
            const CruSegment(VisitStatus.cancelled, 'Cancelled'),
            if (_visit.status == VisitStatus.missed)
              const CruSegment(VisitStatus.missed, 'Missed'),
          ],
          selected: _visit.status,
          onChanged: (s) {
            if (_updatingStatus || s == _visit.status) return;
            _changeStatus(s);
          },
        ),
      ],
    );

    return DentalPanelDialog(
      title: patient?.fullName ?? 'Unknown patient',
      subtitle:
          '${_date.format(_visit.scheduledStart)} · '
          '${_time.format(_visit.scheduledStart)} · ${_visit.durationMinutes} min',
      // Patient avatars are grey monograms, never coloured.
      leading: CruMonogram(
        name: patient?.fullName ?? '?',
        background: c.track,
        foreground: c.label2,
      ),
      width: CruSize.formDialog,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s8,
          CruSpace.s16,
          CruSpace.s8,
          CruSpace.s8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                _statusPill(_visit.status),
                CruPill(
                  text: _isHomeVisit ? 'Home visit' : 'In clinic',
                  icon: _isHomeVisit ? CruIcons.home : null,
                  background: c.inset,
                  foreground: c.label2,
                ),
                if (showQueue && queueEntry != null)
                  CruPill(
                    text: queueEntry.entry.tokenNumber > 0
                        ? 'Token ${queueEntry.entry.tokenNumber}'
                        : 'In the queue',
                    icon: CruIcons.queue,
                    background: c.accentTint,
                    foreground: c.accentText,
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s20),
            LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 640
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: left),
                        const SizedBox(width: CruSpace.s24),
                        Expanded(child: right),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        left,
                        const SizedBox(height: CruSpace.s20),
                        right,
                      ],
                    ),
            ),
          ],
        ),
      ),
      footer: Row(
        children: [
          CruButton(
            label: 'Remove visit',
            kind: CruButtonKind.inset,
            onPressed: _deleteVisit,
          ),
          const Spacer(),
          if (patient != null) ...[
            CruButton(
              label: 'Session photos',
              kind: CruButtonKind.secondary,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PhysioPhotosDialog(
                  patient: patient,
                  initialVisitId: _visit.id,
                ),
              ),
            ),
            const SizedBox(width: CruSpace.s8),
          ],
          CruButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Booked is neutral, done is green; cancelled and missed stay neutral
  /// (red is only for allergies).
  Widget _statusPill(VisitStatus status) {
    final c = context.cru;
    final (String text, Color bg, Color fg) = switch (status) {
      VisitStatus.scheduled => ('Booked', c.inset, c.label2),
      VisitStatus.completed => ('Done', c.greenTint, c.greenText),
      VisitStatus.cancelled => ('Cancelled', c.inset, c.label2),
      VisitStatus.missed => ('Missed', c.amberTint, c.amberText),
    };
    return CruPill(text: text, background: bg, foreground: fg);
  }

  Widget _label(String text) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s8),
      child: Text(text, style: CruType.groupLabel.tint(c.label3)),
    );
  }

  /// An inset panel inside the card (radius 12).
  Widget _panel(Widget child) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.all(CruSpace.s14),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: child,
    );
  }

  Widget _patientPanel(Patient? patient) {
    final c = context.cru;
    final hasWhatsApp =
        patient != null &&
        WhatsAppTemplateService.isValidWhatsAppPhone(patient.phone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          patient?.fullName ?? 'Unknown',
          style: CruType.callout.tint(c.label),
        ),
        const SizedBox(height: CruSpace.s2),
        Text(
          patient == null
              ? '—'
              : '${patient.gender} · born ${DateFormat('d MMM yyyy').format(patient.dateOfBirth)}',
          style: CruType.subhead.tabular.tint(c.label2),
        ),
        const SizedBox(height: CruSpace.s12),
        Row(
          children: [
            CruIcon(CruIcons.phone, size: 16, color: c.label2),
            const SizedBox(width: CruSpace.s8),
            Expanded(
              child: Text(
                patient?.phone ?? 'No phone',
                style: CruType.subhead.tabular.tint(c.label),
              ),
            ),
            if (hasWhatsApp)
              CruCapsuleButton(
                label: 'WhatsApp',
                icon: CruIcons.whatsapp,
                kind: CruCapsuleKind.surface,
                onPressed: _openWhatsApp,
              ),
          ],
        ),
      ],
    );
  }

  Widget _whenPanel() {
    final c = context.cru;
    final start = _visit.scheduledStart;
    final place = _isHomeVisit
        ? (_visit.address.isNotEmpty ? _visit.address : "Patient's home")
        : 'At the clinic';
    final hasMap =
        _isHomeVisit && (_visit.mapsLink != null || _visit.latitude != null);
    Widget fact(CruIconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CruIcon(icon, size: 16, color: c.label2),
          const SizedBox(width: CruSpace.s8),
          Expanded(
            child: Text(text, style: CruType.subhead.tabular.tint(c.label)),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fact(CruIcons.calendar, _date.format(start)),
        fact(
          CruIcons.clock,
          '${_time.format(start)} – ${_time.format(_visit.scheduledEnd)} '
          '(${_visit.durationMinutes} min)',
        ),
        fact(_isHomeVisit ? CruIcons.home : CruIcons.dashboard, place),
        if (hasMap)
          CruLink(
            label: 'Directions in Google Maps',
            trailing: CruIcon(
              CruIcons.arrowUpRight,
              size: 14,
              color: c.accentText,
            ),
            onPressed: _openMaps,
          ),
      ],
    );
  }

  Widget _queuePanel(QueueEntryWithPatient? entry) {
    final c = context.cru;
    final String title;
    final String detail;
    if (entry == null) {
      title = 'Not checked in';
      detail = 'Check in to give a token and add them to the waiting list.';
    } else {
      title = entry.entry.tokenNumber > 0
          ? 'Token ${entry.entry.tokenNumber}'
          : 'Checked in';
      detail = 'In today’s queue.';
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: CruType.callout.tabular.tint(c.label)),
              const SizedBox(height: CruSpace.s2),
              Text(detail, style: CruType.subhead.tint(c.label2)),
            ],
          ),
        ),
        if (entry == null && _visit.status != VisitStatus.cancelled) ...[
          const SizedBox(width: CruSpace.s12),
          CruCapsuleButton(
            label: _checkingIntoQueue ? 'Checking in…' : 'Check in',
            icon: CruIcons.userCheck,
            kind: CruCapsuleKind.surface,
            onPressed: _checkingIntoQueue ? null : _checkIntoQueue,
          ),
        ],
      ],
    );
  }
}
