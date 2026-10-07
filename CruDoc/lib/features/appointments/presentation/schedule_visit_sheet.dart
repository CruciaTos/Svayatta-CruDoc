import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/clinic/clinic_doctors_provider.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/core/widgets/places_autocomplete_field.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/appointments/presentation/desktop_schedule_visit_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
export 'package:doctor_management_app/features/appointments/presentation/desktop_schedule_visit_dialog.dart';

/// Opens a bottom sheet (or desktop dialog on desktop viewports) to schedule a visit for [patient].
/// Returns `true` when a visit was saved successfully.
Future<bool> showScheduleVisitSheet(
  BuildContext context, {
  required Patient patient,
  required VisitRepository visitRepository,
}) {
  if (MediaQuery.of(context).size.width >= 800) {
    return showDesktopScheduleVisitDialog(
      context,
      patient: patient,
      visitRepository: visitRepository,
    );
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.cru.surface,
    shape: const RoundedSuperellipseBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(CruRadius.card),
      ),
    ),
    builder: (_) => ScheduleVisitSheet(
      patient: patient,
      visitRepository: visitRepository,
    ),
  ).then((value) => value ?? false);
}

class ScheduleVisitSheet extends ConsumerStatefulWidget {
  const ScheduleVisitSheet({
    super.key,
    required this.patient,
    required this.visitRepository,
  });

  final Patient patient;
  final VisitRepository visitRepository;

  @override
  ConsumerState<ScheduleVisitSheet> createState() => _ScheduleVisitSheetState();
}

class _ScheduleVisitSheetState extends ConsumerState<ScheduleVisitSheet> {
  final _addressController = TextEditingController();
  final _mapsLinkController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  String _selectedDuration = '30 min';
  VisitType _selectedType = VisitType.clinic;
  String? _attendingDoctorUid;
  bool _isSaving = false;
  String? _errorText;

  // Coordinates resolved from Places Autocomplete — if non-null, the
  // repository can skip its separate geocoding call entirely.
  double? _resolvedLat;
  double? _resolvedLng;

  @override
  void dispose() {
    _addressController.dispose();
    _mapsLinkController.dispose();
    super.dispose();
  }

  static const _durations = [
    '15 min',
    '30 min',
    '45 min',
    '60 min',
    '90 min',
    '120 min',
  ];

  int get _durationMinutes =>
      int.tryParse(_selectedDuration.split(' ').first) ?? 30;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
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
      address: _addressController.text.trim(),
      latitude: _resolvedLat,
      longitude: _resolvedLng,
      mapsLink: _mapsLinkController.text.trim().isEmpty
          ? null
          : _mapsLinkController.text.trim(),
      visitType: _selectedType,
      status: VisitStatus.scheduled,
      attendingDoctorUid: _attendingDoctorUid ?? '',
      createdAt: now,
      updatedAt: now,
    );

    try {
      await widget.visitRepository.createVisit(
        visit,
        acknowledgeOverlap: acknowledgeOverlap,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on VisitOverlapWarning catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);

      final c = context.cru;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: c.surface,
          surfaceTintColor: c.surface.withValues(alpha: 0),
          shape: cruShape(
            CruRadius.card,
            side: BorderSide(color: c.cardBorder),
          ),
          title: Text(
            'Overlapping visit',
            style: CruType.title2.tint(c.label),
          ),
          content: Text(
            'This overlaps ${e.conflicts.length} existing visit(s) at this time. Save anyway?',
            style: CruType.text.tint(c.label2),
          ),
          actions: [
            CruButton(
              label: 'Cancel',
              kind: CruButtonKind.secondary,
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
            CruButton(
              label: 'Save anyway',
              onPressed: () => Navigator.pop(dialogContext, true),
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

  Widget _buildVisitTypeToggle(CruColors c) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.segmentOuter),
      ),
      child: Row(
        children: VisitType.values.map((type) {
          final selected = type == _selectedType;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              child: GestureDetector(
                onTap: _isSaving
                    ? null
                    : () => setState(() => _selectedType = type),
                child: AnimatedContainer( 
                  duration: CruMotion.of(context, CruMotion.fast),
                  curve: CruMotion.curve,
                  height: CruSize.segmentItem + CruSpace.s8,
                  decoration: ShapeDecoration(
                    color: selected
                        ? c.segmentSelected
                        : c.segmentSelected.withValues(alpha: 0),
                    shape: cruShape(CruRadius.segmentInner),
                    shadows: selected ? c.segmentShadow : const [],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    type == VisitType.clinic ? 'Clinic' : 'Home visit',
                    style: CruType.subhead.w600.tint(
                      selected ? c.label : c.label2,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final dateLabel = DateFormat('d MMM yyyy').format(_selectedDate);
    final timeLabel = _selectedTime.format(context);
    final whatsApp = WhatsAppTemplateService.isValidWhatsAppPhone(
      widget.patient.phone,
    );

    final doctorsAsync = ref.watch(clinicDoctorsProvider);
    final doctors = doctorsAsync.value ?? const [];
    if (doctors.length > 1 && _attendingDoctorUid == null) {
      final currentAuthUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final isDoctor = ClinicSession.instance.access?.kind == MemberKind.doctor;
      _attendingDoctorUid = (isDoctor && doctors.any((d) => d.uid == currentAuthUid))
          ? currentAuthUid
          : doctors.first.uid;
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s24,
          CruSpace.s12,
          CruSpace.s24,
          CruSpace.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: CruSpace.s20),
                decoration: ShapeDecoration(
                  color: c.track,
                  shape: cruShape(CruRadius.full),
                ),
              ),
            ),
            Text('Schedule session', style: CruType.title2.tint(c.label)),
            const SizedBox(height: CruSpace.s2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.patient.fullName,
                    style: CruType.subhead.w500.tint(c.label2),
                  ),
                ),
                if (whatsApp) ...[
                  CruIcon(CruIcons.whatsapp, size: 13, color: c.label3),
                  const SizedBox(width: CruSpace.s4),
                  Text(
                    'WhatsApp auto-notify',
                    style: CruType.caption.w500.tint(c.label3),
                  ),
                ] else
                  Text(
                    'No WhatsApp mobile',
                    style: CruType.caption.tint(c.label3),
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s16),
            _buildVisitTypeToggle(c),
            const SizedBox(height: CruSpace.s16),
            CruPickerField(
              label: 'Date',
              icon: CruIcons.calendar,
              value: dateLabel,
              placeholder: 'Pick a date',
              onTap: () {
                if (!_isSaving) _pickDate();
              },
            ),
            const SizedBox(height: CruSpace.s16),
            CruPickerField(
              label: 'Time',
              icon: CruIcons.clock,
              value: timeLabel,
              placeholder: 'Pick a time',
              onTap: () {
                if (!_isSaving) _pickTime();
              },
            ),
            const SizedBox(height: CruSpace.s16),
            CruDropdownField<String>(
              label: 'Duration',
              value: _selectedDuration,
              items: _durations,
              itemLabel: (d) => d,
              tabular: true,
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _selectedDuration = value),
            ),
            if (doctors.length > 1) ...[
              const SizedBox(height: CruSpace.s16),
              CruDropdownField<String>(
                label: 'Doctor',
                icon: CruIcons.user,
                value: _attendingDoctorUid,
                items: [for (final d in doctors) d.uid],
                itemLabel: (uid) => doctors
                    .firstWhere((d) => d.uid == uid, orElse: () => doctors.first)
                    .name,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _attendingDoctorUid = value),
              ),
            ],
            if (_selectedType == VisitType.home) ...[
              const SizedBox(height: CruSpace.s16),
              CruFieldFrame(
                label: 'Home address',
                optional: true,
                child: PlacesAutocompleteField(
                  controller: _addressController,
                  enabled: !_isSaving,
                  hint: 'Start typing to search places',
                  style: 'cru',
                  onPlaceSelected: (selection) {
                    setState(() {
                      _resolvedLat = selection.latitude;
                      _resolvedLng = selection.longitude;
                      _mapsLinkController.text = 'https://www.google.com/maps/search/?api=1&query=${selection.latitude},${selection.longitude}';
                    });
                  },
                ),
              ),
            ],
            const SizedBox(height: CruSpace.s16),
            CruTextField(
              label: 'Google Maps link',
              optional: true,
              controller: _mapsLinkController,
              enabled: !_isSaving,
              keyboardType: TextInputType.url,
              hint: 'https://maps.google.com/...',
            ),
            if (_errorText != null) CruFieldError(_errorText!),
            const SizedBox(height: CruSpace.s20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CruButton(
                  label: 'Cancel',
                  kind: CruButtonKind.secondary,
                  large: true,
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                ),
                const SizedBox(width: CruSpace.s8),
                CruButton(
                  label: _isSaving ? 'Scheduling…' : 'Schedule',
                  large: true,
                  onPressed: _isSaving ? null : _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
