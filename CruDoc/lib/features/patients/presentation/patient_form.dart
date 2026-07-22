import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Data collected by [PatientForm], handed back to the caller on submit.
///
/// Keeping this as a plain value holder (rather than constructing a
/// Patient directly inside the form) lets the same form be reused for
/// both "add" and future "edit" flows without depending on Patient's
/// full shape (id, createdAt, updatedAt, isArchived, etc).
class PatientFormResult {
  final String firstName;
  final String lastName;
  final String phone;
  final String gender;
  final DateTime dateOfBirth;
  final List<String> diagnosis;
  final double packageBalance;

  const PatientFormResult({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.gender,
    required this.dateOfBirth,
    required this.diagnosis,
    required this.packageBalance,
  });
}

/// Reusable patient details form.
///
/// Renders the input fields and validates them, but does not know
/// anything about Firestore or navigation — the parent page owns the
/// submit button and decides what happens with the collected data via
/// [onSubmit], triggered by calling [PatientFormState.submit].
class PatientForm extends StatefulWidget {
  const PatientForm({
    super.key,
    required this.formKey,
    required this.onSubmit,
    this.initialFirstName,
    this.initialLastName,
    this.initialPhone,
    this.initialGender,
    this.initialDateOfBirth,
    this.initialDiagnoses,
    this.initialPackageBalance,
  });

  final GlobalKey<FormState> formKey;

  /// Called with the validated form data whenever the caller invokes
  /// [PatientFormState.submit] (typically from a "Save" button) and
  /// validation passes.
  final ValueChanged<PatientFormResult> onSubmit;

  final String? initialFirstName;
  final String? initialLastName;
  final String? initialPhone;
  final String? initialGender;
  final DateTime? initialDateOfBirth;

  /// Pre-fills the diagnosis fields (e.g. for a future edit flow).
  /// Capped at [Patient.maxDiagnoses] entries.
  final List<String>? initialDiagnoses;
  final double? initialPackageBalance;

  @override
  State<PatientForm> createState() => PatientFormState();
}

class PatientFormState extends State<PatientForm> {
  static const _genderOptions = ['Male', 'Female', 'Other'];
  static const _maxDiagnoses = Patient.maxDiagnoses;

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late List<TextEditingController> _diagnosisControllers;
  late final TextEditingController _packageBalanceController;

  late String _gender;
  DateTime? _dateOfBirth;

  @override
  void initState() {
    super.initState();
    _firstNameController =
        TextEditingController(text: widget.initialFirstName ?? '');
    _lastNameController =
        TextEditingController(text: widget.initialLastName ?? '');
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');

    final initialDiagnoses = widget.initialDiagnoses;
    _diagnosisControllers = (initialDiagnoses == null || initialDiagnoses.isEmpty)
        ? [TextEditingController()]
        : initialDiagnoses
            .take(_maxDiagnoses)
            .map((diagnosis) => TextEditingController(text: diagnosis))
            .toList();

    _packageBalanceController = TextEditingController(
      text: widget.initialPackageBalance != null
          ? widget.initialPackageBalance!.toStringAsFixed(0)
          : '',
    );
    _gender = widget.initialGender ?? _genderOptions.first;
    _dateOfBirth = widget.initialDateOfBirth;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    for (final controller in _diagnosisControllers) {
      controller.dispose();
    }
    _packageBalanceController.dispose();
    super.dispose();
  }

  void _addDiagnosisField() {
    if (_diagnosisControllers.length >= _maxDiagnoses) return;
    setState(() => _diagnosisControllers.add(TextEditingController()));
  }

  void _removeDiagnosisField(int index) {
    setState(() {
      final removed = _diagnosisControllers.removeAt(index);
      removed.dispose();
      if (_diagnosisControllers.isEmpty) {
        _diagnosisControllers.add(TextEditingController());
      }
    });
  }

  /// Validates the form and, if valid, invokes [PatientForm.onSubmit]
  /// with the collected data. Returns true if validation passed.
  bool submit() {
    final isValid = widget.formKey.currentState?.validate() ?? false;
    if (!isValid) return false;

    if (_dateOfBirth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date of birth')),
      );
      return false;
    }

    final diagnoses = _diagnosisControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .take(_maxDiagnoses)
        .toList();

    if (diagnoses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one diagnosis')),
      );
      return false;
    }

    widget.onSubmit(
      PatientFormResult(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        gender: _gender,
        dateOfBirth: _dateOfBirth!,
        diagnosis: diagnoses,
        packageBalance:
            double.tryParse(_packageBalanceController.text.trim()) ?? 0.0,
      ),
    );
    return true;
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.slateBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _FormField(
                  label: 'First Name',
                  controller: _firstNameController,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Required'
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FormField(
                  label: 'Last Name',
                  controller: _lastNameController,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Required'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FormField(
            label: 'Phone Number',
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) return 'Required';
              if (trimmed.length < 7) return 'Enter a valid phone number';
              return null;
            },
          ),
          const SizedBox(height: 16),
          const _SectionLabel(text: 'Gender'),
          const SizedBox(height: 8),
          _GenderSelector(
            options: _genderOptions,
            selected: _gender,
            onChanged: (value) => setState(() => _gender = value),
          ),
          const SizedBox(height: 16),
          const _SectionLabel(text: 'Date of Birth'),
          const SizedBox(height: 8),
          _DateOfBirthField(
            date: _dateOfBirth,
            onTap: _pickDateOfBirth,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _SectionLabel(text: 'Diagnosis'),
              Text(
                '${_diagnosisControllers.length}/$_maxDiagnoses',
                style: AppColors.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _diagnosisControllers.length; i++)
            _DiagnosisFieldRow(
              index: i,
              controller: _diagnosisControllers[i],
              canRemove: _diagnosisControllers.length > 1,
              onRemove: () => _removeDiagnosisField(i),
            ),
          if (_diagnosisControllers.length < _maxDiagnoses) ...[
            const SizedBox(height: 4),
            _AddDiagnosisButton(onTap: _addDiagnosisField),
          ],
          const SizedBox(height: 16),
          _FormField(
            label: 'Package Balance',
            controller: _packageBalanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) return null; // optional, defaults to 0
              if (double.tryParse(trimmed) == null) {
                return 'Enter a valid number';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}

// ---------- SHARED FIELD LABEL ----------
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppColors.bodyMeta.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

// ---------- TEXT FORM FIELD ----------
class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;

  const _FormField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.validator,
  }) : maxLines = 1;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(text: label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          style: AppColors.bodyMedium,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.75),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.slateBlue.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.slateBlue.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.slateBlue, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- DIAGNOSIS FIELD ROW ----------
// One of up to Patient.maxDiagnoses diagnosis inputs. Every row beyond the
// first shows a remove button so the doctor can back out an entry they
// added by mistake.
class _DiagnosisFieldRow extends StatelessWidget {
  final int index;
  final TextEditingController controller;
  final bool canRemove;
  final VoidCallback onRemove;

  const _DiagnosisFieldRow({
    required this.index,
    required this.controller,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              style: AppColors.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Diagnosis ${index + 1}',
                hintStyle: AppColors.bodyMedium.copyWith(
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.75),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.slateBlue.withValues(alpha: 0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.slateBlue.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.slateBlue, width: 1.5),
                ),
              ),
            ),
          ),
          if (canRemove) ...[
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slateBlue.withValues(alpha: 0.2)),
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------- ADD DIAGNOSIS BUTTON ----------
class _AddDiagnosisButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddDiagnosisButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.slateBlue.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 16, color: AppColors.slateBlue),
            const SizedBox(width: 6),
            Text(
              'Add another diagnosis',
              style: AppColors.bodyMeta.copyWith(
                color: AppColors.slateBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- GENDER SELECTOR ----------
class _GenderSelector extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  const _GenderSelector({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((option) {
        final isSelected = option == selected;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: option == options.last ? 0 : 8,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(option),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.slateBlue
                      : Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.slateBlue
                        : AppColors.slateBlue.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  option,
                  style: AppColors.bodyMeta.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------- DATE OF BIRTH FIELD ----------
class _DateOfBirthField extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onTap;

  const _DateOfBirthField({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = date == null
        ? 'Select date of birth'
        : '${date!.day.toString().padLeft(2, '0')}/'
            '${date!.month.toString().padLeft(2, '0')}/'
            '${date!.year}';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.slateBlue.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                color: AppColors.slateBlue.withValues(alpha: 0.7), size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: AppColors.bodyMedium.copyWith(
                color: date == null
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
