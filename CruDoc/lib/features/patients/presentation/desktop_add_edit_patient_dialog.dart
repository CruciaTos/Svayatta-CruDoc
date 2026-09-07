import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';

/// Opens the desktop-specific Add/Edit Patient modal popup dialog.
///
/// If [patient] is provided, fields are pre-populated for editing.
/// If [patient] is null, a blank form is presented to create a new patient.
Future<bool?> showDesktopAddEditPatientDialog(
  BuildContext context, {
  Patient? patient,
  PatientRepository? repository,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 880,
          maxHeight: 740,
        ),
        child: DesktopAddEditPatientDialog(
          patient: patient,
          repository: repository,
        ),
      ),
    ),
  );
}

class DesktopAddEditPatientDialog extends StatefulWidget {
  const DesktopAddEditPatientDialog({
    super.key,
    this.patient,
    this.repository,
  });

  final Patient? patient;
  final PatientRepository? repository;

  @override
  State<DesktopAddEditPatientDialog> createState() =>
      _DesktopAddEditPatientDialogState();
}

class _DesktopAddEditPatientDialogState
    extends State<DesktopAddEditPatientDialog> {
  final _formKey = GlobalKey<FormState>();
  late final PatientRepository _repository =
      widget.repository ?? PatientRepository();

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _notesController;
  late final TextEditingController _packageBalanceController;
  late final TextEditingController _diagnosisInputController;

  late String _gender;
  DateTime? _dateOfBirth;
  final List<String> _diagnoses = [];

  bool _isSaving = false;
  String? _errorText;

  bool get _isEditing => widget.patient != null;

  static const List<String> _commonDiagnoses = [
    'Hypertension',
    'Type 2 Diabetes',
    'Acute Bronchitis',
    'Allergic Rhinitis',
    'Routine Consultation',
    'Gingivitis',
    'Dental Caries',
    'Migraine',
    'Gastritis',
    'General Health Checkup',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.patient;
    _firstNameController = TextEditingController(text: p?.firstName ?? '');
    _lastNameController = TextEditingController(text: p?.lastName ?? '');
    _phoneController = TextEditingController(text: p?.phone ?? '');
    _emailController = TextEditingController(text: p?.email ?? '');
    _notesController = TextEditingController(text: p?.notes ?? '');
    _packageBalanceController = TextEditingController(
      text: p?.packageBalance != null && p!.packageBalance > 0
          ? p.packageBalance.toStringAsFixed(0)
          : '',
    );
    _diagnosisInputController = TextEditingController();

    _gender = p?.gender.isNotEmpty == true ? p!.gender : 'Male';
    _dateOfBirth = p?.dateOfBirth;

    if (p != null && p.diagnosis.isNotEmpty) {
      _diagnoses.addAll(p.diagnosis);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _packageBalanceController.dispose();
    _diagnosisInputController.dispose();
    super.dispose();
  }

  int? get _calculatedAge {
    if (_dateOfBirth == null) return null;
    final today = DateTime.now();
    int age = today.year - _dateOfBirth!.year;
    if (today.month < _dateOfBirth!.month ||
        (today.month == _dateOfBirth!.month && today.day < _dateOfBirth!.day)) {
      age--;
    }
    return age >= 0 ? age : 0;
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initialDate = _dateOfBirth ?? DateTime(now.year - 30, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
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
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  void _addDiagnosis(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (_diagnoses.length >= Patient.maxDiagnoses) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 4 diagnoses allowed per patient record.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (!_diagnoses.any((d) => d.toLowerCase() == trimmed.toLowerCase())) {
      setState(() {
        _diagnoses.add(trimmed);
        _diagnosisInputController.clear();
      });
    }
  }

  void _removeDiagnosis(String item) {
    setState(() => _diagnoses.remove(item));
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final now = DateTime.now();
    final balance = double.tryParse(_packageBalanceController.text.trim()) ?? 0.0;
    final dob = _dateOfBirth ?? DateTime(now.year - 25, 1, 1);

    try {
      if (_isEditing) {
        final current = widget.patient!;
        await _repository.updatePatient(current.id, {
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'gender': _gender,
          'dateOfBirth': dob,
          'diagnosis': List<String>.from(_diagnoses),
          'notes': _notesController.text.trim(),
          'packageBalance': balance,
        });
      } else {
        final newPatient = Patient(
          id: '',
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          gender: _gender,
          dateOfBirth: dob,
          diagnosis: List.unmodifiable(_diagnoses),
          notes: _notesController.text.trim(),
          packageBalance: balance,
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        );
        await _repository.createPatient(newPatient);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = 'Failed to save patient: $e';
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
                      // Left Column: Personal & Contact Details
                      Expanded(
                        flex: 11,
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
                      // Right Column: Clinical Profile & Account Info
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
            child: Icon(
              _isEditing ? Icons.person_outline_rounded : Icons.person_add_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Edit Patient Profile' : 'Register New Patient',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isEditing
                      ? 'Update demographic and clinical details for ${widget.patient!.fullName}'
                      : 'Add complete patient record to your medical clinic directory',
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
  // LEFT COLUMN: Personal Info & Contact
  // ===========================================================================
  Widget _buildLeftColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.badge_outlined,
          title: 'PERSONAL INFORMATION',
        ),
        const SizedBox(height: 16),

        // First Name & Last Name in a Row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildFormField(
                controller: _firstNameController,
                label: 'First Name',
                hint: 'e.g. Rahul',
                prefixIcon: Icons.person_outline,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildFormField(
                controller: _lastNameController,
                label: 'Last Name',
                hint: 'e.g. Sharma',
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Phone & Email in a Row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildFormField(
                controller: _phoneController,
                label: 'Mobile Number',
                hint: 'e.g. 9876543210',
                keyboardType: TextInputType.phone,
                prefixIcon: Icons.phone_outlined,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildFormField(
                controller: _emailController,
                label: 'Email Address (Optional)',
                hint: 'e.g. rahul@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.email_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Gender Selector
        const Text(
          'Gender',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: ['Male', 'Female', 'Other'].map((option) {
            final isSelected = _gender.toLowerCase() == option.toLowerCase();
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                onTap: () => setState(() => _gender = option),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF1F2937) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        option == 'Male'
                            ? Icons.male_rounded
                            : (option == 'Female' ? Icons.female_rounded : Icons.transgender_rounded),
                        size: 16,
                        color: isSelected ? Colors.white : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        option,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Date of Birth & Age
        const Text(
          'Date of Birth & Age',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickDateOfBirth,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF64748B)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _dateOfBirth != null
                        ? DateFormat('dd MMMM yyyy').format(_dateOfBirth!)
                        : 'Select date of birth',
                    style: TextStyle(
                      fontSize: 14,
                      color: _dateOfBirth != null
                          ? const Color(0xFF1F2937)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                if (_calculatedAge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Text(
                      '$_calculatedAge yrs',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // RIGHT COLUMN: Clinical Profile & Financials
  // ===========================================================================
  Widget _buildRightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.medical_services_outlined,
          title: 'CLINICAL PROFILE & DIAGNOSES',
        ),
        const SizedBox(height: 16),

        // Diagnoses tag chips
        Row(
          children: [
            const Text(
              'Diagnoses / Conditions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const Spacer(),
            Text(
              '${_diagnoses.length}/${Patient.maxDiagnoses} added',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Input to add a diagnosis
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _diagnosisInputController,
                decoration: InputDecoration(
                  hintText: 'Add condition (e.g. Hypertension)',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                onFieldSubmitted: _addDiagnosis,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _addDiagnosis(_diagnosisInputController.text),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1F2937),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Active diagnosis tags
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _diagnoses.map((item) {
            return Chip(
              label: Text(item),
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
              backgroundColor: const Color(0xFFF1F5F9),
              deleteIcon: const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
              onDeleted: () => _removeDiagnosis(item),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
            );
          }).toList(),
        ),

        // Quick suggestions
        if (_diagnoses.length < Patient.maxDiagnoses) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _commonDiagnoses
                .where((d) => !_diagnoses.contains(d))
                .take(4)
                .map((d) {
              return ActionChip(
                label: Text('+ $d', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                backgroundColor: const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                onPressed: () => _addDiagnosis(d),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 18),

        // Medical Notes / Clinical Summary
        _buildFormField(
          controller: _notesController,
          label: 'Clinical Notes & Medical History',
          hint: 'Allergies, chronic conditions, regular medications, or surgical history...',
          maxLines: 3,
        ),
        const SizedBox(height: 16),

        // Package Balance / Advance Credit
        _buildFormField(
          controller: _packageBalanceController,
          label: 'Account Credit / Package Balance (₹)',
          hint: '0',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          prefixIcon: Icons.currency_rupee_rounded,
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
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
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
          keyboardType: keyboardType,
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
          validator: validator,
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
          const Icon(Icons.lock_outline_rounded, size: 15, color: Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          const Text(
            'Securely stored in practice database',
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
            onPressed: _isSaving ? null : _handleSave,
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
                : Text(
                    _isEditing ? 'Save Changes' : 'Register Patient',
                    style: const TextStyle(
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
