import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/core/widgets/places_autocomplete_field.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';

/// Opens the desktop-specific Schedule Visit / Appointment modal popup dialog.
///
/// Returns `true` if a visit was successfully scheduled.
Future<bool> showDesktopScheduleVisitDialog(
  BuildContext context, {
  required Patient patient,
  required VisitRepository visitRepository,
  DateTime? initialDate,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 840,
          maxHeight: 740,
        ),
        child: DesktopScheduleVisitDialog(
          patient: patient,
          visitRepository: visitRepository,
          initialDate: initialDate,
        ),
      ),
    ),
  );
  return result ?? false;
}

class DesktopScheduleVisitDialog extends ConsumerStatefulWidget {
  const DesktopScheduleVisitDialog({
    super.key,
    required this.patient,
    required this.visitRepository,
    this.initialDate,
  });

  final Patient patient;
  final VisitRepository visitRepository;
  final DateTime? initialDate;

  @override
  ConsumerState<DesktopScheduleVisitDialog> createState() =>
      _DesktopScheduleVisitDialogState();
}

class _DesktopScheduleVisitDialogState
    extends ConsumerState<DesktopScheduleVisitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _treatmentController = TextEditingController();
  final _addressController = TextEditingController();
  final _mapsLinkController = TextEditingController();
  final _notesController = TextEditingController();

  late DateTime _selectedDate;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  String _selectedDuration = '30 min';
  VisitType _selectedType = VisitType.clinic;
  bool _sendWhatsAppReminder = true;
  bool _addToQueue = true;
  bool _isSaving = false;
  String? _errorText;

  double? _resolvedLat;
  double? _resolvedLng;

  static const List<String> _durationOptions = [
    '15 min',
    '30 min',
    '45 min',
    '60 min',
    '90 min',
  ];

  static const List<String> _quickTreatments = [
    'General Consultation',
    'Follow-up Visit',
    'Dental Scaling & Polishing',
    'Root Canal Treatment',
    'Blood Pressure & Vitals Check',
    'Home Healthcare Visit',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _treatmentController.dispose();
    _addressController.dispose();
    _mapsLinkController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _durationMinutes =>
      int.tryParse(_selectedDuration.split(' ').first) ?? 30;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1F2937),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1F2937),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1F2937),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1F2937),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _submit({bool acknowledgeOverlap = false}) async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final scheduledStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final now = DateTime.now();

    final visit = Visit(
      id: '',
      patientId: widget.patient.id,
      scheduledStart: scheduledStart,
      durationMinutes: _durationMinutes,
      address: _selectedType == VisitType.home ? _addressController.text.trim() : 'Clinic',
      latitude: _resolvedLat,
      longitude: _resolvedLng,
      mapsLink: _mapsLinkController.text.trim().isEmpty
          ? null
          : _mapsLinkController.text.trim(),
      visitType: _selectedType,
      status: VisitStatus.scheduled,
      treatmentType: _treatmentController.text.trim().isEmpty
          ? null
          : _treatmentController.text.trim(),
      therapistNotes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      createdAt: now,
      updatedAt: now,
    );

    try {
      final visitId = await widget.visitRepository.createVisit(
        visit,
        acknowledgeOverlap: acknowledgeOverlap,
      );

      final isQueueEnabled = ref.read(isQueueFeatureEnabledProvider);
      if (isQueueEnabled && _addToQueue && _selectedType == VisitType.clinic) {
        try {
          final savedVisit = visit.copyWith(id: visitId);
          final queueRepo = ref.read(queueRepositoryProvider);
          await queueRepo.checkInVisit(savedVisit);
        } catch (e) {
          debugPrint('Could not auto-add appointment to queue: $e');
        }
      }

      if (!mounted) return;

      if (_sendWhatsAppReminder &&
          WhatsAppTemplateService.isValidWhatsAppPhone(widget.patient.phone)) {
        final message = WhatsAppTemplateService.buildConfirmationMessage(
          visit: visit,
          patient: widget.patient,
          doctorName: 'Doctor',
        );
        final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(
          rawPhone: widget.patient.phone,
          message: message,
        );
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on VisitOverlapWarning catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);

      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
              SizedBox(width: 8),
              Text(
                'Schedule Overlap Warning',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Text(
            'This appointment overlaps with ${e.conflicts.length} other scheduled visit(s). Would you like to schedule it anyway?',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1F2937),
              ),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );

      if (proceed == true) {
        await _submit(acknowledgeOverlap: true);
      }
    } on VisitException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = 'Failed to schedule session: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            _buildHeader(),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Type & Time
                      Expanded(
                        flex: 10,
                        child: _buildLeftColumn(),
                      ),
                      const SizedBox(width: 24),
                      // Vertical separator
                      Container(
                        width: 1,
                        height: 520,
                        color: const Color(0xFFF1F5F9),
                      ),
                      const SizedBox(width: 24),
                      // Right Column: Details, Reason & Location
                      Expanded(
                        flex: 11,
                        child: _buildRightColumn(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_errorText != null) _buildErrorBanner(),
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
  Widget _buildHeader() {
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
              Icons.calendar_month_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Schedule Consultation / Visit',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Booking appointment for ${widget.patient.fullName} • ${widget.patient.phone}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(false),
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

  // ===========================================================================
  // LEFT COLUMN: Visit Type, Date, Time & Duration
  // ===========================================================================
  Widget _buildLeftColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.access_time_rounded,
          title: 'SESSION FORMAT & TIMING',
        ),
        const SizedBox(height: 16),

        // Visit Type Cards (Clinic vs Home Visit)
        Row(
          children: [
            Expanded(
              child: _buildTypeCard(
                type: VisitType.clinic,
                title: 'Clinic Visit',
                subtitle: 'At your practice center',
                icon: Icons.local_hospital_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTypeCard(
                type: VisitType.home,
                title: 'Home Visit',
                subtitle: "At patient's residence",
                icon: Icons.home_work_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Date Picker Card
        const Text(
          'Date',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF64748B)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Time Picker Card
        const Text(
          'Time of Consultation',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _pickTime,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 18, color: Color(0xFF64748B)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedTime.format(context),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Duration Pills
        const Text(
          'Estimated Duration',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _durationOptions.map((d) {
            final isSelected = _selectedDuration == d;
            return InkWell(
              onTap: () => setState(() => _selectedDuration = d),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1F2937) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  d,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTypeCard({
    required VisitType type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedType == type;
    return InkWell(
      onTap: () => setState(() => _selectedType = type),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                ),
                const Spacer(),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Color(0xFF2563EB),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // RIGHT COLUMN: Treatment Type, Location & Notes
  // ===========================================================================
  Widget _buildRightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.assignment_outlined,
          title: 'CONSULTATION DETAILS & REASON',
        ),
        const SizedBox(height: 16),

        // Treatment Type Input
        _buildFormField(
          controller: _treatmentController,
          label: 'Service / Treatment Reason',
          hint: 'e.g. Regular Follow-up, Dental Consultation...',
          prefixIcon: Icons.medical_services_outlined,
        ),
        const SizedBox(height: 6),

        // Quick suggestions for treatment
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _quickTreatments.take(3).map((item) {
            return ActionChip(
              label: Text(item, style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
              backgroundColor: const Color(0xFFF8FAFC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              onPressed: () {
                setState(() => _treatmentController.text = item);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Location / Address (Prominent for Home Visit)
        if (_selectedType == VisitType.home) ...[
          const Text(
            "Patient's Destination Address *",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          PlacesAutocompleteField(
            controller: _addressController,
            hint: 'Enter street address, landmark or apartment...',
            label: 'Destination Address',
            onPlaceSelected: (prediction) {
              setState(() {
                _resolvedLat = prediction.latitude;
                _resolvedLng = prediction.longitude;
              });
            },
          ),
          const SizedBox(height: 12),
          _buildFormField(
            controller: _mapsLinkController,
            label: 'Google Maps Link (Optional)',
            hint: 'https://maps.app.goo.gl/...',
            prefixIcon: Icons.link_rounded,
          ),
          const SizedBox(height: 16),
        ],

        // Notes
        _buildFormField(
          controller: _notesController,
          label: 'Pre-visit Clinical Notes & Instructions',
          hint: 'Patient complaints, required equipment, or preparation...',
          maxLines: 3,
        ),
        const SizedBox(height: 16),

        // WhatsApp Reminder Toggle Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF16A34A), size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WhatsApp Booking Confirmation',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF166534),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Ready instant appointment alert for patient phone',
                      style: TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _sendWhatsAppReminder,
                activeThumbColor: const Color(0xFF16A34A),
                onChanged: (val) => setState(() => _sendWhatsAppReminder = val),
              ),
            ],
          ),
        ),

        // Walk-in Queue Integration Toggle Card (guarded by Super Admin feature flag)
        Consumer(
          builder: (context, ref, _) {
            final isQueueEnabled = ref.watch(isQueueFeatureEnabledProvider);
            if (!isQueueEnabled || _selectedType != VisitType.clinic) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.groups_rounded, color: Color(0xFF2563EB), size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add to OPD Walk-in Queue',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E40AF),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Automatically reserves a token in the clinic live queue for this appointment',
                            style: TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _addToQueue,
                      activeThumbColor: const Color(0xFF2563EB),
                      onChanged: (val) => setState(() => _addToQueue = val),
                    ),
                  ],
                ),
              ),
            );
          },
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

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? prefixIcon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 18, color: const Color(0xFF64748B))
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
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
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      color: const Color(0xFFFEF2F2),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorText!,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
            ),
          ),
        ],
      ),
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
          const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          const Text(
            'Overlapping schedule detection is enabled',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _isSaving ? null : () => _submit(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F2937),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Confirm Appointment',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
