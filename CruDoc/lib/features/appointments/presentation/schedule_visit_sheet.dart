import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Opens a bottom sheet to schedule a visit for [patient].
/// Returns `true` when a visit was saved successfully.
Future<bool> showScheduleVisitSheet(
  BuildContext context, {
  required Patient patient,
  required VisitRepository visitRepository,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => ScheduleVisitSheet(
      patient: patient,
      visitRepository: visitRepository,
    ),
  ).then((value) => value ?? false);
}

class ScheduleVisitSheet extends StatefulWidget {
  const ScheduleVisitSheet({
    super.key,
    required this.patient,
    required this.visitRepository,
  });

  final Patient patient;
  final VisitRepository visitRepository;

  @override
  State<ScheduleVisitSheet> createState() => _ScheduleVisitSheetState();
}

class _ScheduleVisitSheetState extends State<ScheduleVisitSheet> {
  final _addressController = TextEditingController();
  final _mapsLinkController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  String _selectedDuration = '30 min';
  VisitType _selectedType = VisitType.clinic;
  bool _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _addressController.dispose();
    _mapsLinkController.dispose();
    super.dispose();
  }

  int get _durationMinutes =>
      int.tryParse(_selectedDuration.split(' ').first) ?? 30;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.slateBlue,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.cardSurface,
              onSurface: AppColors.textPrimary,
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
            colorScheme: const ColorScheme.dark(
              primary: AppColors.slateBlue,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.cardSurface,
              onSurface: AppColors.textPrimary,
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
      address: _addressController.text.trim(),
      mapsLink: _mapsLinkController.text.trim().isEmpty
          ? null
          : _mapsLinkController.text.trim(),
      visitType: _selectedType,
      status: VisitStatus.scheduled,
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

      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.cardSurface,
          title: Text(
            'Overlapping visit',
            style: AppColors.sectionHeading.copyWith(fontSize: 18),
          ),
          content: Text(
            'This overlaps ${e.conflicts.length} existing visit(s) at this time. Save anyway?',
            style: AppColors.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
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

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppColors.bodyMedium.copyWith(color: AppColors.textSecondary),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontFamily: AppColors.bodyFontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      );

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _isSaving ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.chartBarLight),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: AppColors.bodyMedium),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisitTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: VisitType.values.map((type) {
          final selected = type == _selectedType;
          return Expanded(
            child: GestureDetector(
              onTap: _isSaving ? null : () => setState(() => _selectedType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.chartBarLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  type == VisitType.clinic ? 'Clinic' : 'Home Visit',
                  style: AppColors.bodyMedium.copyWith(
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
    final dateLabel = DateFormat('d MMM yyyy').format(_selectedDate);
    final timeLabel = _selectedTime.format(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.silver.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              'Schedule Session',
              style: AppColors.sectionHeading.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 6),
            Text(
              widget.patient.fullName,
              style: AppColors.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildVisitTypeToggle(),
            const SizedBox(height: 14),
            _label('Date'),
            const SizedBox(height: 8),
            _pickerTile(
              icon: Icons.calendar_today_outlined,
              label: dateLabel,
              onTap: _pickDate,
            ),
            const SizedBox(height: 14),
            _label('Time'),
            const SizedBox(height: 8),
            _pickerTile(
              icon: Icons.access_time,
              label: timeLabel,
              onTap: _pickTime,
            ),
            const SizedBox(height: 14),
            _label('Duration'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedDuration,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: '15 min', child: Text('15 min')),
                    DropdownMenuItem(value: '30 min', child: Text('30 min')),
                    DropdownMenuItem(value: '45 min', child: Text('45 min')),
                    DropdownMenuItem(value: '60 min', child: Text('60 min')),
                    DropdownMenuItem(value: '90 min', child: Text('90 min')),
                    DropdownMenuItem(value: '120 min', child: Text('120 min')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _selectedDuration = value);
                          }
                        },
                ),
              ),
            ),
            if (_selectedType == VisitType.home) ...[
              const SizedBox(height: 14),
              _label('Home Address (optional)'),
              const SizedBox(height: 8),
              TextField(
                controller: _addressController,
                enabled: !_isSaving,
                style: AppColors.bodyMedium,
                decoration: _fieldDecoration('Patient home address'),
              ),
            ],
            const SizedBox(height: 14),
            _label('Google Maps Link (optional)'),
            const SizedBox(height: 8),
            TextField(
              controller: _mapsLinkController,
              enabled: !_isSaving,
              style: AppColors.bodyMedium,
              decoration: _fieldDecoration('https://maps.google.com/...'),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.slateBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isSaving ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    backgroundColor: AppColors.chartBarLight,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Schedule',
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
