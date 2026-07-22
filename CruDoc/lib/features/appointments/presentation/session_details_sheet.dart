import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

// ---------- Accent colours (mirrors visit_details.dart) ----------
const Color _accentBlue = Color(0xFF5DADE2);
const Color _accentTeal = Color(0xFF48C9B0);
const Color _accentAmber = Color(0xFFF2B84B);
const Color _accentRed = Color(0xFFE57373);

Color _colorForStatus(VisitStatus status) {
  switch (status) {
    case VisitStatus.scheduled:
      return _accentBlue;
    case VisitStatus.completed:
      return _accentTeal;
    case VisitStatus.cancelled:
      return _accentRed;
    case VisitStatus.missed:
      return _accentAmber;
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
/// from the bottom, same presentation as the "Add Transaction" sheet on
/// the Revenue screen, rather than pushing a full-screen page.
Future<void> showSessionDetailsSheet(
  BuildContext context,
  VisitWithPatient vw,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    backgroundColor: AppColors.cardSurface,
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
    _notesController = TextEditingController(
      text: _visit.therapistNotes ?? '',
    );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open the link')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open link. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final patient = _patient;
    final statusColor = _colorForStatus(_visit.status);
    final isPaid = _visit.isPaid;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: 24 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.silver.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isVisitation ? 'Visitation Details' : 'Appointment Details',
              style: AppColors.sectionHeading.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 14),

            // ----- Patient name (the only place it appears) -----
            Text(
              patient?.fullName ?? 'Unknown patient',
              style: AppColors.bodyLarge.copyWith(
                fontFamily: AppColors.headingFontFamily,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),

            // ----- Pills: status / age & gender / payment -----
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
                  iconColor: isPaid ? _accentTeal : _accentAmber,
                  label: isPaid ? 'Paid' : 'Payment Pending',
                ),
              ],
            ),
            const SizedBox(height: 24),

            const _SectionLabel(text: 'SCHEDULE'),
            const SizedBox(height: 10),
            _ScheduleInfo(visit: _visit),
            const SizedBox(height: 20),

            const _SectionLabel(text: 'PHONE'),
            const SizedBox(height: 10),
            _PhoneRow(phone: patient?.phone, onTap: _callPatient),

            if (_isVisitation) ...[
              const SizedBox(height: 20),
              const _SectionLabel(text: 'LOCATION'),
              const SizedBox(height: 10),
              _LocationInfo(address: _visit.address, onOpenMaps: _openMaps),
            ],

            const SizedBox(height: 20),
            const _SectionLabel(text: 'SESSION NOTE'),
            const SizedBox(height: 10),
            _buildNoteField(),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _notesController,
          enabled: !_savingNote,
          maxLines: 4,
          minLines: 3,
          style: AppColors.bodyMedium,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Add a note about this session…',
            hintStyle: AppColors.bodySmall,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: (_noteDirty && !_savingNote) ? _saveNote : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.slateBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
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
          const SizedBox(width: 6),
          Text(
            label,
            style: AppColors.bodySmall.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardSurfaceAlt.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.cardSurfaceAlt.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor ?? AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppColors.bodySmall.copyWith(fontWeight: FontWeight.w500),
          ),
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
    return Text(
      text,
      style: AppColors.bodySmall.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: AppColors.textSecondary.withValues(alpha: 0.85),
      ),
    );
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_today,
                size: 16,
                color: AppColors.slateBlue,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(dateStr, style: AppColors.bodyMedium)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.access_time,
                size: 16,
                color: AppColors.slateBlue,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(timeStr, style: AppColors.bodyMedium)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.timelapse,
                size: 16,
                color: AppColors.slateBlue,
              ),
              const SizedBox(width: 10),
              Text('${visit.durationMinutes} min', style: AppColors.bodyMedium),
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
    final trimmed = phone?.trim();
    final hasPhone = trimmed != null && trimmed.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: hasPhone ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.call_outlined,
              size: 16,
              color: AppColors.slateBlue,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasPhone ? trimmed : 'No phone number on file',
                style: AppColors.bodyMedium,
              ),
            ),
            if (hasPhone)
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

class _LocationInfo extends StatelessWidget {
  final String address;
  final VoidCallback onOpenMaps;
  const _LocationInfo({required this.address, required this.onOpenMaps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: AppColors.slateBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  address.trim().isNotEmpty ? address : 'No address on file',
                  style: AppColors.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenMaps,
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Open in Google Maps'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(
                  color: AppColors.slateBlue.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
