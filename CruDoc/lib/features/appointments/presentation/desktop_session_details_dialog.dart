import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';

/// Opens the desktop-specific Session Details modal popup dialog.
Future<void> showDesktopSessionDetailsDialog(
  BuildContext context,
  VisitWithPatient item,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 840,
          maxHeight: 740,
        ),
        child: DesktopSessionDetailsDialog(initial: item),
      ),
    ),
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
    _notesController = TextEditingController(
      text: _visit.therapistNotes ?? '',
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notes updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save note: $e')),
      );
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
        SnackBar(content: Text('Status updated to ${newStatus.name.toUpperCase()}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
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
        SnackBar(content: Text('Appointment checked into queue as Token #${created.tokenNumber}!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not check into queue: $e')),
      );
    } finally {
      if (mounted) setState(() => _checkingIntoQueue = false);
    }
  }

  Future<void> _deleteVisit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 8),
            Text('Cancel / Delete Appointment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'Are you sure you want to remove this appointment? It will be cancelled from the schedule.',
          style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Appointment'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final repo = ref.read(visitRepositoryProvider);
      await repo.softDeleteVisit(_visit.id);
      if (!mounted) return;
      ref.invalidate(visitsWithPatientsProvider);
      ref.invalidate(allVisitsWithPatientsProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment removed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  Future<void> _openWhatsApp() async {
    final patient = _patient;
    if (patient == null) return;
    if (!WhatsAppTemplateService.isValidWhatsAppPhone(patient.phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid WhatsApp mobile number for this patient.')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }

  Future<void> _openMaps() async {
    final urlStr = _visit.mapsLink ??
        (_visit.latitude != null && _visit.longitude != null
            ? 'https://www.google.com/maps/search/?api=1&query=${_visit.latitude},${_visit.longitude}'
            : null);
    if (urlStr == null) return;
    final uri = Uri.tryParse(urlStr);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patient = _patient;
    final patientName = patient?.fullName ?? 'Unknown Patient';
    final isQueueEnabled = ref.watch(isQueueFeatureEnabledProvider);
    final queueEntries = isQueueEnabled
        ? (ref.watch(todaysQueueWithPatientsProvider).value ?? const [])
        : const <QueueEntryWithPatient>[];
    final queueEntry = queueEntries.where((e) => e.entry.linkedVisitId == _visit.id).firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(patientName, queueEntry: queueEntry, isQueueEnabled: isQueueEnabled),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Patient Overview & Visit Schedule
                    Expanded(
                      flex: 10,
                      child: _buildLeftColumn(patient),
                    ),
                    const SizedBox(width: 24),
                    // Vertical separator
                    Container(
                      width: 1,
                      height: 480,
                      color: const Color(0xFFF1F5F9),
                    ),
                    const SizedBox(width: 24),
                    // Right Column: Treatment Details, Clinical Notes & Actions
                    Expanded(
                      flex: 11,
                      child: _buildRightColumn(queueEntry: queueEntry, isQueueEnabled: isQueueEnabled),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================
  Widget _buildHeader(
    String patientName, {
    required QueueEntryWithPatient? queueEntry,
    required bool isQueueEnabled,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.event_note_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      patientName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildStatusBadge(_visit.status),
                    const SizedBox(width: 6),
                    _buildTypeBadge(_visit.visitType),
                    if (isQueueEnabled && _visit.visitType == VisitType.clinic) ...[
                      const SizedBox(width: 6),
                      if (queueEntry != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.groups_rounded, size: 12, color: Color(0xFF6366F1)),
                              const SizedBox(width: 4),
                              Text(
                                queueEntry.entry.tokenNumber > 0
                                    ? 'Queue #${queueEntry.entry.tokenNumber}'
                                    : 'In Queue',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${DateFormat('EEEE, dd MMMM yyyy').format(_visit.scheduledStart)} at ${DateFormat('hh:mm a').format(_visit.scheduledStart)} (${_visit.durationMinutes} min)',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            splashRadius: 20,
            icon: const Icon(
              Icons.close_rounded,
              color: Color(0xFF64748B),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(VisitStatus status) {
    late final Color bg;
    late final Color text;
    switch (status) {
      case VisitStatus.scheduled:
        bg = const Color(0xFFEDE9FE);
        text = const Color(0xFF6D28D9);
        break;
      case VisitStatus.completed:
        bg = const Color(0xFFDCFCE7);
        text = const Color(0xFF15803D);
        break;
      case VisitStatus.cancelled:
      case VisitStatus.missed:
        bg = const Color(0xFFFEE2E2);
        text = const Color(0xFFB91C1C);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }

  Widget _buildTypeBadge(VisitType type) {
    final isHome = type == VisitType.home;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHome ? const Color(0xFFFEF3C7) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isHome ? 'HOME VISIT' : 'CLINIC',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isHome ? const Color(0xFFB45309) : const Color(0xFF1D4ED8),
        ),
      ),
    );
  }

  // ===========================================================================
  // LEFT COLUMN: Patient Details & Schedule Info
  // ===========================================================================
  Widget _buildLeftColumn(Patient? patient) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.person_outline_rounded,
          title: 'PATIENT PROFILE',
        ),
        const SizedBox(height: 12),

        // Patient Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF1F2937),
                    child: Text(
                      patient?.firstName.isNotEmpty == true
                          ? patient!.firstName[0].toUpperCase()
                          : 'P',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient?.fullName ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${patient?.gender ?? 'Unknown'} • DOB: ${patient?.dateOfBirth != null ? DateFormat('dd MMM yyyy').format(patient!.dateOfBirth) : 'N/A'}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 10),

              // Phone & WhatsApp Action
              Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text(
                    patient?.phone ?? 'No phone',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                  ),
                  const Spacer(),
                  if (patient != null && WhatsAppTemplateService.isValidWhatsAppPhone(patient.phone))
                    InkWell(
                      onTap: _openWhatsApp,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 14, color: Color(0xFF15803D)),
                            SizedBox(width: 4),
                            Text(
                              'WhatsApp',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _buildSectionHeader(
          icon: Icons.access_time_rounded,
          title: 'TIMING & LOCATION',
        ),
        const SizedBox(height: 12),

        // Timing Details
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _buildInfoRow(
                icon: Icons.calendar_today_rounded,
                label: 'Date',
                value: DateFormat('EEEE, dd MMMM yyyy').format(_visit.scheduledStart),
              ),
              const SizedBox(height: 10),
              _buildInfoRow(
                icon: Icons.schedule_rounded,
                label: 'Time Slot',
                value: '${DateFormat('hh:mm a').format(_visit.scheduledStart)} - ${DateFormat('hh:mm a').format(_visit.scheduledEnd)} (${_visit.durationMinutes} min)',
              ),
              const SizedBox(height: 10),
              _buildInfoRow(
                icon: _isHomeVisit ? Icons.home_rounded : Icons.apartment_rounded,
                label: 'Location',
                value: _isHomeVisit ? (_visit.address.isNotEmpty ? _visit.address : "Patient's Home") : 'Clinic Consultation Center',
              ),
              if (_isHomeVisit && (_visit.mapsLink != null || _visit.latitude != null)) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: _openMaps,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_rounded, size: 16, color: Color(0xFF2563EB)),
                        SizedBox(width: 6),
                        Text(
                          'Open Directions in Google Maps',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // RIGHT COLUMN: Treatment Details, Clinical Notes & Actions
  // ===========================================================================
  Widget _buildRightColumn({
    required QueueEntryWithPatient? queueEntry,
    required bool isQueueEnabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isQueueEnabled && _visit.visitType == VisitType.clinic) ...[
          _buildSectionHeader(
            icon: Icons.groups_rounded,
            title: 'OPD WALK-IN QUEUE',
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.confirmation_number_outlined, color: Color(0xFF2563EB), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        queueEntry != null
                            ? (queueEntry.entry.tokenNumber > 0
                                ? 'Token #${queueEntry.entry.tokenNumber} (${queueEntry.entry.status.name.toUpperCase()})'
                                : 'Checked In — Pending Token')
                            : 'Not Checked into Queue',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        queueEntry != null
                            ? 'Patient is registered in the clinic walk-in triage flow'
                            : 'Generate a token and send patient to live waiting queue',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                      ),
                    ],
                  ),
                ),
                if (queueEntry == null && _visit.status != VisitStatus.cancelled)
                  ElevatedButton.icon(
                    onPressed: _checkingIntoQueue ? null : _checkIntoQueue,
                    icon: _checkingIntoQueue
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Check In', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Treatment Type
        _buildSectionHeader(
          icon: Icons.assignment_outlined,
          title: 'SERVICE / TREATMENT',
        ),
        const SizedBox(height: 12),

        // Treatment Type
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Treatment / Purpose',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 4),
              Text(
                _visit.treatmentType?.isNotEmpty == true
                    ? _visit.treatmentType!
                    : 'Standard Consultation',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Clinical Notes Editor
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader(
              icon: Icons.edit_note_rounded,
              title: 'CLINICAL NOTES',
            ),
            if (_isNoteDirty)
              TextButton(
                onPressed: _savingNote ? null : _saveNote,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: _savingNote
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Save Note',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2563EB),
                        ),
                      ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _notesController,
          maxLines: 4,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
          decoration: InputDecoration(
            hintText: 'Enter clinical observations, prescription advice, or visit notes...',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),

        // Quick Status Actions
        _buildSectionHeader(
          icon: Icons.checklist_rounded,
          title: 'UPDATE STATUS',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _updatingStatus || _visit.status == VisitStatus.completed
                    ? null
                    : () => _changeStatus(VisitStatus.completed),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  side: BorderSide(
                    color: _visit.status == VisitStatus.completed
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFCBD5E1),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF16A34A)),
                label: const Text(
                  'Completed',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF16A34A)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _updatingStatus || _visit.status == VisitStatus.cancelled
                    ? null
                    : () => _changeStatus(VisitStatus.cancelled),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  side: BorderSide(
                    color: _visit.status == VisitStatus.cancelled
                        ? const Color(0xFFDC2626)
                        : const Color(0xFFCBD5E1),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFDC2626)),
                label: const Text(
                  'Cancelled',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _updatingStatus || _visit.status == VisitStatus.scheduled
                    ? null
                    : () => _changeStatus(VisitStatus.scheduled),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.schedule, size: 16, color: Color(0xFF6B7280)),
                label: const Text(
                  'Scheduled',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF4B5563)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            const SizedBox(height: 1),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // FOOTER
  // ===========================================================================
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _deleteVisit,
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Cancel & Remove', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F2937),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
