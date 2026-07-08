import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

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
  final String diagnosis;
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
    this.initialDiagnosis,
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
  final String? initialDiagnosis;
  final double? initialPackageBalance;

  @override
  State<PatientForm> createState() => PatientFormState();
}

class PatientFormState extends State<PatientForm> {
  static const _genderOptions = ['Male', 'Female', 'Other'];

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _diagnosisController;
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
    _diagnosisController =
        TextEditingController(text: widget.initialDiagnosis ?? '');
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
    _diagnosisController.dispose();
    _packageBalanceController.dispose();
    super.dispose();
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

    widget.onSubmit(
      PatientFormResult(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        gender: _gender,
        dateOfBirth: _dateOfBirth!,
        diagnosis: _diagnosisController.text.trim(),
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
          _FormField(
            label: 'Diagnosis',
            controller: _diagnosisController,
            maxLines: 3,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Required'
                : null,
          ),
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
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
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
    this.maxLines = 1,
    this.validator,
  });

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
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.cardSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.slateBlue),
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
                      : AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColors.slateBlue : AppColors.divider,
                  ),
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                color: AppColors.silver, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: date == null
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}