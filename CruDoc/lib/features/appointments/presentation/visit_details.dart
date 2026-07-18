import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
// The providers — VisitWithPatient and visitsWithPatientsProvider now
// live in this same file (previously a separate broken import pointed
// at a directory instead of a file).
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_details.dart';

// ---------- Accent colours ----------
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

VisitWithPatient? _findById(List<VisitWithPatient> list, String id) {
  for (final item in list) {
    if (item.visit.id == id) return item;
  }
  return null;
}

// ---------- Reusable form helpers ----------
Widget _buildTextField(String label, TextEditingController controller,
    {String? hint, ValueChanged<String>? onChanged}) {
  return TextField(
    controller: controller,
    onChanged: onChanged,
    style: AppColors.bodyLarge,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: AppColors.bodyMedium,
      hintStyle: AppColors.bodySmall.copyWith(color: Colors.grey.shade600),
      filled: true,
      fillColor: AppColors.cardSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
  );
}

Widget _buildPickDateButton(
    BuildContext context, DateTime date, ValueChanged<DateTime?> onPicked) {
  final dateStr = DateFormat('d MMM yyyy').format(date);
  return InkWell(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.slateBlue,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.cardSurface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        ),
      );
      onPicked(picked);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.calendar_today, color: AppColors.silver, size: 20),
        const SizedBox(width: 10),
        Text(dateStr, style: AppColors.bodyLarge),
      ]),
    ),
  );
}

Widget _buildPickTimeButton(
    BuildContext context, TimeOfDay time, ValueChanged<TimeOfDay?> onPicked) {
  return InkWell(
    onTap: () async {
      final picked = await showTimePicker(
        context: context,
        initialTime: time,
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.slateBlue,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.cardSurface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        ),
      );
      onPicked(picked);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.access_time, color: AppColors.silver, size: 20),
        const SizedBox(width: 10),
        Text(time.format(context), style: AppColors.bodyLarge),
      ]),
    ),
  );
}

Widget _buildDurationDropdown(
    String currentValue, ValueChanged<String?> onChanged) {
  const durations = [
    '15 min',
    '30 min',
    '45 min',
    '60 min',
    '90 min',
    '120 min'
  ];
  return SizedBox(
    height: 48,
    width: double.infinity,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isExpanded: true,
          menuMaxHeight: 200,
          dropdownColor: AppColors.cardSurface,
          style: AppColors.bodyLarge,
          items: durations
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: onChanged,
          icon: const Icon(Icons.arrow_drop_down, color: AppColors.silver),
        ),
      ),
    ),
  );
}

// ---------- Edit Visit Dialog ----------
class _EditVisitDialog extends StatefulWidget {
  final Visit visit;
  const _EditVisitDialog({required this.visit});

  @override
  State<_EditVisitDialog> createState() => _EditVisitDialogState();
}

class _EditVisitDialogState extends State<_EditVisitDialog> {
  late final TextEditingController _addressController;
  late final TextEditingController _mapsLinkController;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late String _selectedDuration;

  @override
  void initState() {
    super.initState();
    _addressController =
        TextEditingController(text: widget.visit.address);
    _mapsLinkController =
        TextEditingController(text: widget.visit.mapsLink ?? '');
    _selectedDate = widget.visit.scheduledStart;
    _selectedTime = TimeOfDay.fromDateTime(widget.visit.scheduledStart);
    final mins = widget.visit.durationMinutes;
    const opts = [15, 30, 45, 60, 90, 120];
    final match = opts.firstWhere((o) => o == mins, orElse: () => 30);
    _selectedDuration = '$match min';
  }

  @override
  void dispose() {
    _addressController.dispose();
    _mapsLinkController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, {
      'address': _addressController.text.trim(),
      'mapsLink': _mapsLinkController.text.trim().isEmpty
          ? null
          : _mapsLinkController.text.trim(),
      'date': _selectedDate,
      'time': _selectedTime,
      'duration': _selectedDuration,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color.fromARGB(255, 140, 188, 255),
      title: const Text('Edit Visit', style: AppColors.sectionHeading),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPickDateButton(context, _selectedDate, (picked) {
              if (picked != null) setState(() => _selectedDate = picked);
            }),
            const SizedBox(height: 12),
            _buildPickTimeButton(context, _selectedTime, (picked) {
              if (picked != null) setState(() => _selectedTime = picked);
            }),
            const SizedBox(height: 12),
            _buildDurationDropdown(_selectedDuration, (value) {
              if (value != null) setState(() => _selectedDuration = value);
            }),
            const SizedBox(height: 12),
            _buildTextField('Address (optional)', _addressController),
            const SizedBox(height: 12),
            _buildTextField(
              'Google Maps Link (optional)',
              _mapsLinkController,
              hint: 'https://maps.google.com/...',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: AppColors.bodyLarge),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Save', style: TextStyle(fontSize: 17)),
        ),
      ],
    );
  }
}

// ---------- Visit Details Page ----------
class VisitDetailsPage extends ConsumerWidget {
  final VisitWithPatient initial;

  const VisitDetailsPage({super.key, required this.initial});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveList = ref
        .watch(visitsWithPatientsProvider)
        .maybeWhen(data: (list) => list, orElse: () => null);
    final current = liveList == null
        ? initial
        : (_findById(liveList, initial.visit.id) ?? initial);

    final visit = current.visit;
    final patient = current.patient;

    final hasNotes = (visit.treatmentType?.trim().isNotEmpty ?? false) ||
        (visit.therapistNotes?.trim().isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ----- Top bar -----
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: AppColors.textPrimary, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 2),
                    const Expanded(
                      child: Text(
                        'Visit Details',
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_note,
                          color: AppColors.textPrimary, size: 22),
                      tooltip: 'Edit visit',
                      onPressed: () =>
                          _showEditDialog(context, ref, visit),
                    ),
                  ],
                ),
              ),
              // ----- Content -----
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  physics: const ClampingScrollPhysics(),
                  children: [
                    _VisitHeader(visit: visit, patient: patient),
                    const SizedBox(height: 24),
                    const _SectionLabel(text: 'SCHEDULE'),
                    const SizedBox(height: 12),
                    _ScheduleCard(visit: visit),
                    const SizedBox(height: 24),
                    const _SectionLabel(text: 'LOCATION'),
                    const SizedBox(height: 12),
                    _LocationCard(visit: visit),
                    const SizedBox(height: 24),
                    const _SectionLabel(text: 'PATIENT'),
                    const SizedBox(height: 12),
                    _PatientCard(patient: patient),
                    if (hasNotes) ...[
                      const SizedBox(height: 24),
                      const _SectionLabel(text: 'TREATMENT NOTES'),
                      const SizedBox(height: 12),
                      _TreatmentNotesCard(visit: visit),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _BottomActionBar(visit: visit),
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, WidgetRef ref, Visit visit) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => _EditVisitDialog(visit: visit),
    );
    if (result == null || !context.mounted) return;

    final String address = result['address'] as String;
    final String? mapsLink = result['mapsLink'] as String?;
    final DateTime date = result['date'] as DateTime;
    final TimeOfDay time = result['time'] as TimeOfDay;
    final String durationLabel = result['duration'] as String;
    final int durationMinutes =
        int.tryParse(durationLabel.split(' ').first) ?? 30;

    final scheduledStart = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    final repo = ref.read(visitRepositoryProvider);
    try {
      // updateVisit expects (String visitId, Map<String, dynamic> data) —
      // not a Visit object. repo.updateVisit sets updatedAt itself and
      // re-geocodes only if the address actually changed.
      await repo.updateVisit(visit.id, {
        'address': address,
        'mapsLink': mapsLink,
        'scheduledStart': scheduledStart,
        'durationMinutes': durationMinutes,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visit updated successfully')),
        );
      }
    } on VisitException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Something went wrong')),
        );
      }
    }
  }
}

// ---------- Visit Header ----------
class _VisitHeader extends StatelessWidget {
  final Visit visit;
  final Patient? patient;

  const _VisitHeader({required this.visit, required this.patient});

  @override
  Widget build(BuildContext context) {
    final statusColor = _colorForStatus(visit.status);
    final patient = this.patient; // promote

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          patient?.fullName ?? 'Unknown patient',
          style: const TextStyle(
            fontFamily: AppColors.headingFontFamily,
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _labelForStatus(visit.status),
                    style: AppColors.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            if (patient != null)
              _InfoPill(
                icon: Icons.person_outline,
                label: '${patient.gender}, ${patient.age} yrs',
              ),
          ],
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style:
                AppColors.bodySmall.copyWith(fontWeight: FontWeight.w500),
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

class _ScheduleCard extends StatelessWidget {
  final Visit visit;
  const _ScheduleCard({required this.visit});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('EEEE, MMM d, yyyy').format(visit.scheduledStart);
    final timeStr =
        '${DateFormat('h:mm a').format(visit.scheduledStart)} – '
        '${DateFormat('h:mm a').format(visit.scheduledEnd)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today,
                  size: 16, color: AppColors.silver),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(dateStr, style: AppColors.bodyMedium)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.access_time,
                  size: 16, color: AppColors.silver),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(timeStr, style: AppColors.bodyMedium)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.timelapse,
                  size: 16, color: AppColors.silver),
              const SizedBox(width: 10),
              Text('${visit.durationMinutes} min',
                  style: AppColors.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final Visit visit;
  const _LocationCard({required this.visit});

  String get _destinationUrl {
    final link = visit.mapsLink?.trim();
    if (link != null && link.isNotEmpty) {
      return (link.startsWith('http://') || link.startsWith('https://'))
          ? link
          : 'https://$link';
    }
    final query = (visit.latitude != null && visit.longitude != null)
        ? '${visit.latitude},${visit.longitude}'
        : visit.address;
    return 'https://www.google.com/maps/search/?api=1'
        '&query=${Uri.encodeComponent(query)}';
  }

  Future<void> _openMaps(BuildContext context) async {
    try {
      final uri = Uri.parse(_destinationUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Unable to open link. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 16, color: AppColors.silver),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  visit.address.isNotEmpty
                      ? visit.address
                      : 'No address on file',
                  style: AppColors.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openMaps(context),
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Open in Google Maps'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.2)),
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

class _PatientCard extends StatelessWidget {
  final Patient? patient;
  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    final patient = this.patient;

    if (patient == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_off_outlined,
                color: AppColors.silver, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Patient record not found — it may have been removed.',
                style: AppColors.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PatientDetailsPage(patient: patient),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_outline,
                color: AppColors.silver, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.fullName,
                    style: AppColors.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    patient.phone.isNotEmpty
                        ? patient.phone
                        : 'No phone number',
                    style: AppColors.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.silver, size: 20),
          ],
        ),
      ),
    );
  }
}

class _TreatmentNotesCard extends StatelessWidget {
  final Visit visit;
  const _TreatmentNotesCard({required this.visit});

  @override
  Widget build(BuildContext context) {
    final hasType = visit.treatmentType?.trim().isNotEmpty ?? false;
    final hasNotes = visit.therapistNotes?.trim().isNotEmpty ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasType) ...[
            Text(
              visit.treatmentType!,
              style: AppColors.bodyMedium
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            if (hasNotes) const SizedBox(height: 8),
          ],
          if (hasNotes)
            Text(
              visit.therapistNotes!,
              style: AppColors.bodyMeta,
            ),
        ],
      ),
    );
  }
}

// ---------- Bottom Action Bar ----------
class _BottomActionBar extends ConsumerStatefulWidget {
  final Visit visit;
  const _BottomActionBar({required this.visit});

  @override
  ConsumerState<_BottomActionBar> createState() =>
      _BottomActionBarState();
}

class _BottomActionBarState extends ConsumerState<_BottomActionBar> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function() action, {
    required String successMessage,
    bool popOnSuccess = false,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      if (popOnSuccess) Navigator.pop(context);
    } on VisitException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this visit?'),
        content: const Text(
          "This removes it from every list, but it's never permanently "
          'erased — the record is kept behind the scenes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: _accentRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repo = ref.read(visitRepositoryProvider);
    await _run(
      () => repo.softDeleteVisit(widget.visit.id),
      successMessage: 'Visit deleted.',
      popOnSuccess: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(visitRepositoryProvider);
    final status = widget.visit.status;

    late final Widget leftButton;
    late final Widget rightButton;

    if (status == VisitStatus.scheduled) {
      leftButton = OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => _run(
                  () => repo.cancelVisit(widget.visit.id),
                  successMessage: 'Visit cancelled.',
                ),
        icon: const Icon(Icons.event_busy, size: 18),
        label: const Text('Cancel Visit'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accentRed,
          side: BorderSide(color: _accentRed.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
      rightButton = ElevatedButton.icon(
        onPressed: _busy
            ? null
            : () => _run(
                  () => repo.updateStatus(
                    widget.visit.id,
                    VisitStatus.completed,
                  ),
                  successMessage: 'Marked as completed.',
                ),
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Mark Completed'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentTeal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      leftButton = OutlinedButton.icon(
        onPressed: _busy ? null : _confirmDelete,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('Delete Visit'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accentRed,
          side: BorderSide(color: _accentRed.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
      rightButton = ElevatedButton.icon(
        onPressed: _busy
            ? null
            : () => _run(
                  () => repo.updateStatus(
                    widget.visit.id,
                    VisitStatus.scheduled,
                  ),
                  successMessage: 'Reopened as scheduled.',
                ),
        icon: const Icon(Icons.event_repeat, size: 18),
        label: const Text('Reopen'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(child: leftButton),
            const SizedBox(width: 12),
            Expanded(child: rightButton),
          ],
        ),
      ),
    );
  }
}