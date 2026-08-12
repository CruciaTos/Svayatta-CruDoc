import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';
import 'package:doctor_management_app/features/shell/components/animated_background.dart';

// ==============================================================================
// 1. PATIENT FORM RESULT & FORM WIDGET
// ==============================================================================

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
  final String email;
  final String gender;
  final DateTime dateOfBirth;
  final List<String> diagnosis;
  final double packageBalance;

  const PatientFormResult({
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.email = '',
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
    this.initialEmail,
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
  final String? initialEmail;
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
  late final TextEditingController _emailController;
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
    _emailController = TextEditingController(text: widget.initialEmail ?? '');

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
    _emailController.dispose();
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
        email: _emailController.text.trim(),
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
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
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
          _FormField(
            label: 'Email (optional)',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) return null; // optional field
              final emailRegex = RegExp(r'^[\w.-]+@[\w.-]+\.[a-zA-Z]{2,}$');
              if (!emailRegex.hasMatch(trimmed)) {
                return 'Enter a valid email address';
              }
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
            fillColor: const Color(0xFFF8FAFC),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
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
                  color: const Color(0xFF94A3B8),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
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
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Color(0xFFEF4444),
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
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 16, color: Color(0xFF2563EB)),
            const SizedBox(width: 6),
            Text(
              'Add another diagnosis',
              style: AppColors.bodyMeta.copyWith(
                color: const Color(0xFF2563EB),
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
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  option,
                  style: AppColors.bodyMeta.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : const Color(0xFF475569),
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
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                color: const Color(0xFF2563EB).withValues(alpha: 0.7), size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: AppColors.bodyMedium.copyWith(
                color: date == null
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// 2. TOP-LEVEL SHEET FUNCTIONS
// ==============================================================================

/// Shows the bottom sheet for adding a new patient.
Future<bool?> showAddPatientSheet(
  BuildContext context, {
  PatientRepository? repository,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => AddPatientSheet(repository: repository),
  );
}

/// Shows the bottom sheet for editing an existing patient.
Future<bool?> showEditPatientSheet(
  BuildContext context, {
  required Patient patient,
  PatientRepository? repository,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => EditPatientSheet(patient: patient, repository: repository),
  );
}

// ==============================================================================
// 3. ADD PATIENT SHEET
// ==============================================================================

class AddPatientSheet extends StatefulWidget {
  const AddPatientSheet({super.key, PatientRepository? repository})
      : _repository = repository;

  final PatientRepository? _repository;

  @override
  State<AddPatientSheet> createState() => _AddPatientSheetState();
}

class _AddPatientSheetState extends State<AddPatientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _formStateKey = GlobalKey<PatientFormState>();

  late final PatientRepository _repository =
      widget._repository ?? PatientRepository();

  bool _isSaving = false;

  Future<void> _handleSubmit(PatientFormResult result) async {
    setState(() => _isSaving = true);

    final now = DateTime.now();
    final patient = Patient(
      id: '',
      firstName: result.firstName,
      lastName: result.lastName,
      phone: result.phone,
      gender: result.gender,
      dateOfBirth: result.dateOfBirth,
      diagnosis: result.diagnosis,
      notes: '',
      packageBalance: result.packageBalance,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _repository.createPatient(patient);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient added successfully')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save patient: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onSavePressed() {
    _formStateKey.currentState?.submit();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.person_add_alt_1_rounded,
                                color: Color(0xFF2563EB), size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Add New Patient',
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF64748B),
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 20, color: Color(0xFFE2E8F0)),
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: PatientForm(
                          key: _formStateKey,
                          formKey: _formKey,
                          onSubmit: _handleSubmit,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _onSavePressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          disabledBackgroundColor:
                              const Color(0xFF2563EB).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Patient',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// 4. ADD PATIENT FULL PAGE (used elsewhere, kept for completeness)
// ==============================================================================

class AddPatientPage extends StatefulWidget {
  const AddPatientPage({super.key, PatientRepository? repository})
      : _repository = repository;

  final PatientRepository? _repository;

  @override
  State<AddPatientPage> createState() => _AddPatientPageState();
}

class _AddPatientPageState extends State<AddPatientPage> {
  final _formKey = GlobalKey<FormState>();
  final _formStateKey = GlobalKey<PatientFormState>();

  late final PatientRepository _repository =
      widget._repository ?? PatientRepository();

  bool _isSaving = false;

  Future<void> _handleSubmit(PatientFormResult result) async {
    setState(() => _isSaving = true);

    final now = DateTime.now();
    final patient = Patient(
      id: '', // Firestore assigns the id on create.
      firstName: result.firstName,
      lastName: result.lastName,
      phone: result.phone,
      gender: result.gender,
      dateOfBirth: result.dateOfBirth,
      diagnosis: result.diagnosis,
      notes: '',
      packageBalance: result.packageBalance,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _repository.createPatient(patient);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient added successfully')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save patient: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onSavePressed() {
    _formStateKey.currentState?.submit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              children: [
                const _TopBar(),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: PatientForm(
                      key: _formStateKey,
                      formKey: _formKey,
                      onSubmit: _handleSubmit,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _onSavePressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.slateBlue,
                      disabledBackgroundColor:
                          AppColors.slateBlue.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.textPrimary,
                            ),
                          )
                        : const Text(
                            'Save Patient',
                            style: TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Top Bar for AddPatientPage ----------
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 10),
        const Text(
          'Add Patient',
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ==============================================================================
// 5. EDIT PATIENT SHEET
// ==============================================================================

class EditPatientSheet extends StatefulWidget {
  const EditPatientSheet({
    super.key,
    required this.patient,
    PatientRepository? repository,
  }) : _repository = repository;

  final Patient patient;
  final PatientRepository? _repository;

  @override
  State<EditPatientSheet> createState() => _EditPatientSheetState();
}

class _EditPatientSheetState extends State<EditPatientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _formStateKey = GlobalKey<PatientFormState>();

  late final PatientRepository _repository =
      widget._repository ?? PatientRepository();

  bool _isSaving = false;

  Future<void> _handleSubmit(PatientFormResult result) async {
    setState(() => _isSaving = true);

    try {
      await _repository.updatePatient(widget.patient.id, {
        'firstName': result.firstName,
        'lastName': result.lastName,
        'phone': result.phone,
        'email': result.email,
        'gender': result.gender,
        'dateOfBirth': result.dateOfBirth,
        'diagnosis': result.diagnosis,
        'packageBalance': result.packageBalance,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient updated successfully')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update patient: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onSavePressed() {
    _formStateKey.currentState?.submit();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.edit_note,
                                color: Color(0xFF2563EB),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Edit Patient',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF64748B),
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 20, color: Color(0xFFE2E8F0)),
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: PatientForm(
                          key: _formStateKey,
                          formKey: _formKey,
                          initialFirstName: widget.patient.firstName,
                          initialLastName: widget.patient.lastName,
                          initialPhone: widget.patient.phone,
                          initialEmail: widget.patient.email,
                          initialGender: widget.patient.gender,
                          initialDateOfBirth: widget.patient.dateOfBirth,
                          initialDiagnoses: widget.patient.diagnosis,
                          initialPackageBalance: widget.patient.packageBalance,
                          onSubmit: _handleSubmit,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _onSavePressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          disabledBackgroundColor:
                              const Color(0xFF2563EB).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Update Patient',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}