import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/core/widgets/visit_location_map.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_notification_log.dart';
import 'package:doctor_management_app/features/messaging/data/providers/whatsapp_providers.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_recording_sheet.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/revenue/presentation/bill_generation_sheet.dart';
import 'package:doctor_management_app/features/scribe/presentation/prescription_generation_sheet.dart';
import 'package:doctor_management_app/features/appointments/presentation/desktop_session_details_dialog.dart';
import 'package:doctor_management_app/features/therapy/presentation/physio_photos_dialog.dart';
export 'package:doctor_management_app/features/appointments/presentation/desktop_session_details_dialog.dart';

Color _colorForStatus(VisitStatus status, CruColors c) {
  switch (status) {
    case VisitStatus.scheduled:
      return c.accent;
    case VisitStatus.completed:
      return c.green;
    case VisitStatus.cancelled:
      return c.redText;
    case VisitStatus.missed:
      return c.amber;
  }
}

String _labelForStatus(VisitStatus status) {
  switch (status) {
    case VisitStatus.scheduled:
      return 'Scheduled';
    case VisitStatus.completed:
      return 'Completed';
    case VisitStatus.cancelled:
      return 'Cancelled';
    case VisitStatus.missed:
      return 'Missed';
  }
}

/// Opens the session-details bottom sheet for [vw].
///
/// Shows the Appointment Details layout for clinic visits
/// ([VisitType.clinic]) or the Visitation Details layout for home visits
/// ([VisitType.home]) — whichever matches the underlying visit. Pops up
/// from the bottom on mobile, or shows a dedicated desktop dialog on desktop.
Future<void> showSessionDetailsSheet(
  BuildContext context,
  VisitWithPatient vw,
) {
  if (MediaQuery.of(context).size.width >= 800) {
    return showDesktopSessionDetailsDialog(context, vw);
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    backgroundColor: context.cru.surface,
    builder: (_) => _SessionDetailsSheet(initial: vw),
  );
}

class _SessionDetailsSheet extends ConsumerStatefulWidget {
  final VisitWithPatient initial;
  const _SessionDetailsSheet({required this.initial});

  @override
  ConsumerState<_SessionDetailsSheet> createState() =>
      _SessionDetailsSheetState();
}

class _SessionDetailsSheetState extends ConsumerState<_SessionDetailsSheet> {
  late Visit _visit;
  late final TextEditingController _notesController;
  bool _savingNote = false;

  Patient? get _patient => widget.initial.patient;
  bool get _isVisitation => _visit.visitType == VisitType.home;

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

  bool get _noteDirty =>
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note saved.')));
    } on VisitException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the note. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  /// Runs the AI scribe for this session, then reloads the visit so the
  /// note field shows what the confirmed scribe note appended.
  Future<void> _openScribe() async {
    // Keep unsaved typing: the refresh below replaces the field's text.
    if (_noteDirty) await _saveNote();
    if (!mounted) return;
    final confirmed = await showScribeFlow(
      context,
      visit: _visit,
      patient: _patient,
    );
    if (!confirmed || !mounted) return;
    final refreshed = await ref
        .read(visitRepositoryProvider)
        .getVisit(_visit.id);
    if (!mounted || refreshed == null) return;
    setState(() {
      _visit = refreshed;
      _notesController.text = refreshed.therapistNotes ?? '';
    });
  }

  Future<void> _deleteVisit() async {
    final c = context.cru;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CruRadius.card),
        ),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: c.redText, size: 24),
            const SizedBox(width: CruSpace.s8),
            Expanded(
              child: Text(
                'Delete Appointment',
                style: CruType.headline.w700.tint(c.label),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this appointment? It will be removed permanently.',
          style: CruType.text.tint(c.label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.redText,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CruRadius.control),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final repo = ref.read(visitRepositoryProvider);
        await repo.softDeleteVisit(_visit.id);
        if (!mounted) return;
        ref.invalidate(visitsForPatientProvider(_visit.patientId));
        ref.invalidate(upcomingVisitsProvider);
        ref.invalidate(lastVisitPerPatientProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Appointment deleted.')));
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete appointment: $e')),
        );
      }
    }
  }

  Future<void> _callPatient() async {
    final phone = _patient?.phone.trim();
    if (phone == null || phone.isEmpty) return;
    try {
      final uri = Uri(scheme: 'tel', path: phone);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the dialer')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to place the call. Please try again.'),
        ),
      );
    }
  }

  String get _destinationUrl {
    final link = _visit.mapsLink?.trim();
    if (link != null && link.isNotEmpty) {
      return (link.startsWith('http://') || link.startsWith('https://'))
          ? link
          : 'https://$link';
    }
    final query = (_visit.latitude != null && _visit.longitude != null)
        ? '${_visit.latitude},${_visit.longitude}'
        : _visit.address;
    return 'https://www.google.com/maps/search/?api=1'
        '&query=${Uri.encodeComponent(query)}';
  }

  Future<void> _openMaps() async {
    try {
      final uri = Uri.parse(_destinationUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open link. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final patient = _patient;
    final statusColor = _colorForStatus(_visit.status, c);
    final isPaid = _visit.isPaid;

    return Padding(
      padding: EdgeInsets.only(
        left: CruSpace.s24,
        right: CruSpace.s24,
        top: CruSpace.s16,
        bottom: CruSpace.s24 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.label3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: CruSpace.s20),
            Text(
              _isVisitation ? 'Visitation Details' : 'Appointment Details',
              style: CruType.title2.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s14),
            Text(
              patient?.fullName ?? 'Unknown patient',
              style: CruType.headline.w700.tint(c.label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: CruSpace.s10),
            Wrap(
              spacing: CruSpace.s8,
              runSpacing: CruSpace.s8,
              children: [
                _StatusPill(
                  color: statusColor,
                  label: _labelForStatus(_visit.status),
                ),
                if (patient != null)
                  _InfoPill(
                    icon: Icons.person_outline,
                    label: '${patient.gender}, ${patient.age} yrs',
                  ),
                _InfoPill(
                  icon: isPaid
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  iconColor: isPaid ? c.green : c.amber,
                  label: isPaid ? 'Paid' : 'Payment Pending',
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s24),
            const _SectionLabel(text: 'SCHEDULE'),
            const SizedBox(height: CruSpace.s10),
            _ScheduleInfo(visit: _visit),
            const SizedBox(height: CruSpace.s20),
            const _SectionLabel(text: 'PHONE'),
            const SizedBox(height: CruSpace.s10),
            _PhoneRow(phone: patient?.phone, onTap: _callPatient),
            const SizedBox(height: CruSpace.s14),
            _WhatsAppNotificationSection(visit: _visit, patient: patient),

            if (_isVisitation) ...[
              const SizedBox(height: CruSpace.s20),
              const _SectionLabel(text: 'LOCATION'),
              const SizedBox(height: CruSpace.s10),
              _LocationInfo(
                address: _visit.address,
                latitude: _visit.latitude,
                longitude: _visit.longitude,
                onOpenMaps: _openMaps,
              ),
            ],

            const SizedBox(height: CruSpace.s20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionLabel(text: 'SESSION NOTE'),
                TextButton.icon(
                  onPressed: _openScribe,
                  icon: Icon(
                    Icons.mic_none_rounded,
                    size: 16,
                    color: c.ai,
                  ),
                  label: Text(
                    'AI Voice Scribe',
                    style: CruType.caption.w700.tint(c.ai),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s12,
                      vertical: CruSpace.s6,
                    ),
                    backgroundColor: c.aiTint,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CruRadius.full),
                      side: BorderSide(
                        color: c.ai.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s10),
            _buildNoteField(),
            const SizedBox(height: CruSpace.s20),
            const _SectionLabel(text: 'CLINICAL & BILLING DOCUMENTS'),
            const SizedBox(height: CruSpace.s10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final cfg = DoctorLetterheadConfig.fromProfileData(
                        null,
                        null,
                      );
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => BillGenerationSheet(
                          letterheadConfig: cfg,
                          initialVisit: _visit,
                          initialPatient: _patient,
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.receipt_long_rounded,
                      size: 16,
                      color: c.tealText,
                    ),
                    label: Text(
                      'Generate Bill',
                      style: CruType.subhead.w700.tint(c.tealText),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: CruSpace.s12,
                      ),
                      side: BorderSide(color: c.tealText.withValues(alpha: 0.3)),
                      backgroundColor: c.tealTint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(CruRadius.control),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: CruSpace.s10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final cfg = DoctorLetterheadConfig.fromProfileData(
                        null,
                        null,
                      );
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => PrescriptionGenerationSheet(
                          letterheadConfig: cfg,
                          initialVisit: _visit,
                          initialPatient: _patient,
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.medication_rounded,
                      size: 16,
                      color: c.accentText,
                    ),
                    label: Text(
                      'Generate Rx',
                      style: CruType.subhead.w700.tint(c.accentText),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: CruSpace.s12,
                      ),
                      side: BorderSide(
                        color: c.accentText.withValues(alpha: 0.3),
                      ),
                      backgroundColor: c.accentTint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(CruRadius.control),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _deleteVisit,
                icon: Icon(
                  Icons.delete_outline,
                  color: c.redText,
                  size: 20,
                ),
                label: Text(
                  'Delete Appointment',
                  style: CruType.row.tint(c.redText),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.redText, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CruRadius.control),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteField() {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _notesController,
          enabled: !_savingNote,
          maxLines: 4,
          minLines: 3,
          style: CruType.text.tint(c.label),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Add a note about this session…',
            hintStyle: CruType.caption.tint(c.label3),
            filled: true,
            fillColor: c.inset,
            contentPadding: const EdgeInsets.all(CruSpace.s14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CruRadius.control),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: CruSpace.s10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_patient != null)
              OutlinedButton.icon(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => PhysioPhotosDialog(
                      patient: _patient!,
                      initialVisitId: _visit.id,
                    ),
                  );
                },
                icon: const Icon(Icons.camera_alt_outlined, size: 16),
                label: const Text('Session Photos'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CruRadius.iconTile),
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
            ElevatedButton(
              onPressed: (_noteDirty && !_savingNote) ? _saveNote : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: CruSpace.s20,
                  vertical: CruSpace.s10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CruRadius.iconTile),
                ),
              ),
              child: _savingNote
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save Note'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------- Shared small pieces ----------

class _StatusPill extends StatelessWidget {
  final Color color;
  final String label;
  const _StatusPill({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s10,
        vertical: CruSpace.s6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(CruRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: CruSpace.s6),
          Text(label, style: CruType.caption.w700.tint(color)),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  const _InfoPill({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s10,
        vertical: CruSpace.s6,
      ),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CruRadius.full),
        border: Border.all(color: c.separator),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor ?? c.label2),
          const SizedBox(width: CruSpace.s4),
          Text(label, style: CruType.caption.w500.tint(c.label2)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: CruType.groupLabel.tint(context.cru.label3));
  }
}

class _ScheduleInfo extends StatelessWidget {
  final Visit visit;
  const _ScheduleInfo({required this.visit});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat(
      'EEEE, MMM d, yyyy',
    ).format(visit.scheduledStart);
    final timeStr =
        '${DateFormat('h:mm a').format(visit.scheduledStart)} – '
        '${DateFormat('h:mm a').format(visit.scheduledEnd)}';

    final c = context.cru;
    return Container(
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CruRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: c.label2),
              const SizedBox(width: CruSpace.s10),
              Expanded(child: Text(dateStr, style: CruType.text.tint(c.label))),
            ],
          ),
          const SizedBox(height: CruSpace.s10),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: c.label2),
              const SizedBox(width: CruSpace.s10),
              Expanded(child: Text(timeStr, style: CruType.text.tint(c.label))),
            ],
          ),
          const SizedBox(height: CruSpace.s10),
          Row(
            children: [
              Icon(Icons.timelapse, size: 16, color: c.label2),
              const SizedBox(width: CruSpace.s10),
              Text(
                '${visit.durationMinutes} min',
                style: CruType.text.tint(c.label),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhoneRow extends StatelessWidget {
  final String? phone;
  final VoidCallback onTap;
  const _PhoneRow({required this.phone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final trimmed = phone?.trim();
    final hasPhone = trimmed != null && trimmed.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(CruRadius.card),
      onTap: hasPhone ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CruSpace.s16),
        decoration: BoxDecoration(
          color: c.inset,
          borderRadius: BorderRadius.circular(CruRadius.card),
        ),
        child: Row(
          children: [
            Icon(Icons.call_outlined, size: 16, color: c.label2),
            const SizedBox(width: CruSpace.s10),
            Expanded(
              child: Text(
                hasPhone ? trimmed : 'No phone number on file',
                style: CruType.text.tint(c.label),
              ),
            ),
            if (hasPhone)
              Icon(Icons.chevron_right, size: 18, color: c.label3),
          ],
        ),
      ),
    );
  }
}

class _LocationInfo extends StatelessWidget {
  final String address;
  final double? latitude;
  final double? longitude;
  final VoidCallback onOpenMaps;
  const _LocationInfo({
    required this.address,
    this.latitude,
    this.longitude,
    required this.onOpenMaps,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CruRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VisitLocationMap(
            latitude: latitude,
            longitude: longitude,
            height: 140,
            lite: true,
            onOpenMaps: onOpenMaps,
          ),
          const SizedBox(height: CruSpace.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on_outlined, size: 16, color: c.label2),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text(
                  address.trim().isNotEmpty ? address : 'No address on file',
                  style: CruType.text.tint(c.label),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenMaps,
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Open in Google Maps'),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.label,
                side: BorderSide(color: c.separator),
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CruRadius.iconTile),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhatsAppNotificationSection extends ConsumerWidget {
  final Visit visit;
  final Patient? patient;

  const _WhatsAppNotificationSection({
    required this.visit,
    required this.patient,
  });

  Future<void> _openDirectWhatsApp(BuildContext context) async {
    final rawPhone = patient?.phone;
    if (rawPhone == null ||
        !WhatsAppTemplateService.isValidWhatsAppPhone(rawPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid WhatsApp mobile number for this patient.'),
        ),
      );
      return;
    }

    final message = WhatsAppTemplateService.buildConfirmationMessage(
      visit: visit,
      patient:
          patient ??
          Patient(
            id: '',
            firstName: 'Valued',
            lastName: 'Patient',
            phone: rawPhone,
            gender: 'Other',
            dateOfBirth: DateTime(2000),
            diagnosis: const [],
            packageBalance: 0,
            isArchived: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
      doctorName: 'Doctor',
    );

    final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(
      rawPhone: rawPhone,
      message: message,
    );

    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not launch WhatsApp. Please check if WhatsApp is installed.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(visitWhatsAppStatusProvider(visit.id));
    final log = statusAsync.asData?.value;

    final hasPhone =
        patient?.phone != null &&
        WhatsAppTemplateService.isValidWhatsAppPhone(patient?.phone);

    Color badgeColor = const Color(0xFF25D366);
    IconData badgeIcon = Icons.check_circle_outline;
    String badgeLabel = 'WhatsApp Notified';

    if (log != null) {
      switch (log.status) {
        case WhatsAppNotificationStatus.delivered:
          badgeColor = const Color(0xFF10B981);
          badgeIcon = Icons.done_all_rounded;
          badgeLabel = 'WhatsApp: Delivered';
          break;
        case WhatsAppNotificationStatus.read:
          badgeColor = const Color(0xFF2D9CDB);
          badgeIcon = Icons.done_all_rounded;
          badgeLabel = 'WhatsApp: Read by Patient';
          break;
        case WhatsAppNotificationStatus.sent:
          badgeColor = const Color(0xFF25D366);
          badgeIcon = Icons.check_rounded;
          badgeLabel = 'WhatsApp: Sent';
          break;
        case WhatsAppNotificationStatus.pending:
          badgeColor = const Color(0xFFF59E0B);
          badgeIcon = Icons.hourglass_top_rounded;
          badgeLabel = 'WhatsApp: Sending...';
          break;
        case WhatsAppNotificationStatus.failed:
          badgeColor = const Color(0xFFEF4444);
          badgeIcon = Icons.error_outline_rounded;
          badgeLabel = 'WhatsApp: Delivery Failed';
          break;
        case WhatsAppNotificationStatus.skipped:
          badgeColor = const Color(0xFF6B7280);
          badgeIcon = Icons.phone_disabled_outlined;
          badgeLabel = 'WhatsApp: Skipped (No Mobile)';
          break;
      }
    } else if (!hasPhone) {
      badgeColor = const Color(0xFF6B7280);
      badgeIcon = Icons.phone_disabled_outlined;
      badgeLabel = 'WhatsApp: No Mobile Number';
    }

    final c = context.cru;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CruRadius.card),
        border: Border.all(color: c.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CruSpace.s10,
                  vertical: CruSpace.s4,
                ),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CruRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 14, color: badgeColor),
                    const SizedBox(width: CruSpace.s6),
                    Text(
                      badgeLabel,
                      style: CruType.caption.w600.tint(badgeColor),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (log?.recipientPhone != null && log!.recipientPhone.isNotEmpty)
                Text(
                  WhatsAppTemplateService.formatDisplayPhone(
                    log.recipientPhone,
                  ),
                  style: CruType.caption.tint(c.label2),
                ),
            ],
          ),
          if (hasPhone) ...[
            const SizedBox(height: CruSpace.s12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openDirectWhatsApp(context),
                icon: const Icon(
                  Icons.chat_outlined,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  'Chat / Resend via WhatsApp',
                  style: CruType.subhead.w600.tint(Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CruRadius.control),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
