import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_voice_fill_bar.dart';
import 'package:doctor_management_app/features/patients/services/patient_voice_fill_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens the desktop Add/Edit Patient form.
///
/// If [patient] is provided, fields are pre-populated for editing.
/// If [patient] is null, a blank form is presented to create a new patient.
/// Returns true when the patient was saved.
Future<bool?> showDesktopAddEditPatientDialog(
  BuildContext context, {
  Patient? patient,
  PatientRepository? repository,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DesktopAddEditPatientDialog(
      patient: patient,
      repository: repository,
    ),
  );
}

class DesktopAddEditPatientDialog extends StatefulWidget {
  const DesktopAddEditPatientDialog({
    super.key,
    this.patient,
    this.repository,
    this.voiceFillService,
  });

  final Patient? patient;
  final PatientRepository? repository;

  /// Injected in tests.
  final PatientVoiceFillService? voiceFillService;

  @override
  State<DesktopAddEditPatientDialog> createState() =>
      _DesktopAddEditPatientDialogState();
}

class _DesktopAddEditPatientDialogState
    extends State<DesktopAddEditPatientDialog> {
  static const _sexes = ['Male', 'Female', 'Other'];

  static const _commonConditions = [
    'Hypertension',
    'Type 2 Diabetes',
    'Migraine',
    'Gastritis',
    'Allergic Rhinitis',
    'Acute Bronchitis',
    'Gingivitis',
    'Dental Caries',
  ];

  final _formKey = GlobalKey<FormState>();
  late final PatientRepository _repository =
      widget.repository ?? PatientRepository();

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _age;
  late final TextEditingController _notes;
  late final TextEditingController _balance;

  String? _sex;
  DateTime? _dateOfBirth;

  /// True when [_dateOfBirth] was worked out from a typed age.
  bool _dobFromAge = false;
  late List<String> _conditions;

  bool _dirty = false;
  bool _saving = false;
  bool _submitted = false;
  String? _notice;

  bool get _isEditing => widget.patient != null;

  @override
  void initState() {
    super.initState();
    final p = widget.patient;
    _firstName = TextEditingController(text: p?.firstName ?? '');
    _lastName = TextEditingController(text: p?.lastName ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
    _balance = TextEditingController(
      text: p != null && p.packageBalance > 0
          ? p.packageBalance.toStringAsFixed(0)
          : '',
    );
    _dateOfBirth = p?.dateOfBirth;
    final age = _ageOn(_dateOfBirth);
    _age = TextEditingController(text: age == null ? '' : '$age');
    final g = p?.gender.trim().toLowerCase() ?? '';
    _sex = _sexes.where((s) => s.toLowerCase() == g).firstOrNull;
    _conditions = List.of(p?.diagnosis ?? const <String>[]);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _age.dispose();
    _notes.dispose();
    _balance.dispose();
    super.dispose();
  }

  static int? _ageOn(DateTime? dob) {
    if (dob == null) return null;
    final today = DateTime.now();
    var age = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  String get _fullName =>
      '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim();

  void _edited([Object? _]) {
    setState(() {
      _dirty = true;
      _notice = null;
    });
  }

  /// Puts what was heard into the form. Only fields that were heard are
  /// changed; heard conditions are added to the ones already entered, and
  /// heard notes are appended.
  void _applyVoiceFill(PatientVoiceFill fill) {
    if (fill.firstName.isNotEmpty) _firstName.text = fill.firstName;
    if (fill.lastName.isNotEmpty) _lastName.text = fill.lastName;
    if (fill.phone.isNotEmpty) _phone.text = fill.phone;
    if (fill.email.isNotEmpty) _email.text = fill.email;
    if (fill.gender != null && _sexes.contains(fill.gender)) _sex = fill.gender;
    if (fill.dateOfBirth != null) {
      _dateOfBirth = fill.dateOfBirth;
      _dobFromAge = false;
      _age.text = '${_ageOn(_dateOfBirth)}';
    } else if (fill.ageYears != null) {
      _age.text = '${fill.ageYears}';
      _onAgeChanged(_age.text);
    }
    if (fill.conditions.isNotEmpty) {
      final seen = <String>{};
      _conditions = [..._conditions, ...fill.conditions]
          .where((c) => seen.add(c.toLowerCase()))
          .take(Patient.maxDiagnoses)
          .toList();
    }
    if (fill.notes.isNotEmpty) {
      final existing = _notes.text.trim();
      _notes.text = existing.isEmpty ? fill.notes : '$existing\n${fill.notes}';
    }
    if (fill.packageBalance != null) {
      _balance.text = fill.packageBalance!.toStringAsFixed(0);
    }
    _edited();
  }

  void _onAgeChanged(String value) {
    final years = int.tryParse(value.trim());
    final now = DateTime.now();
    setState(() {
      _dirty = true;
      if (years == null) {
        if (_dobFromAge) _dateOfBirth = null;
      } else {
        _dateOfBirth = DateTime(now.year - years, now.month, now.day);
        _dobFromAge = true;
      }
    });
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dirty = true;
      _dateOfBirth = picked;
      _dobFromAge = false;
      _age.text = '${_ageOn(picked)}';
    });
  }

  String? _required(String? v, String message) =>
      (v == null || v.trim().isEmpty) ? message : null;

  String? _validatePhone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Add a mobile number.';
    if (digits.length < 10) return 'Enter a 10-digit mobile number.';
    return null;
  }

  String? _validateEmail(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
        ? null
        : 'This email looks incomplete.';
  }

  String? _validateAge(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return (n == null || n > 120) ? 'Enter an age up to 120.' : null;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    final fieldsOk = _formKey.currentState!.validate();
    if (!fieldsOk || _sex == null || _dateOfBirth == null) return;

    setState(() {
      _saving = true;
      _notice = null;
    });

    final now = DateTime.now();
    final balance =
        double.tryParse(_balance.text.replaceAll(RegExp(r'[₹,\s]'), '')) ?? 0;
    final phone = _phone.text.trim();

    try {
      if (_isEditing) {
        await _repository.updatePatient(widget.patient!.id, {
          'firstName': _firstName.text.trim(),
          'lastName': _lastName.text.trim(),
          'phone': phone,
          'email': _email.text.trim(),
          'gender': _sex,
          'dateOfBirth': _dateOfBirth,
          'diagnosis': List<String>.from(_conditions),
          'notes': _notes.text.trim(),
          'packageBalance': balance,
        });
      } else {
        await _repository.createPatient(
          Patient(
            id: '',
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            phone: phone,
            email: _email.text.trim(),
            gender: _sex!,
            dateOfBirth: _dateOfBirth!,
            diagnosis: List.unmodifiable(_conditions),
            notes: _notes.text.trim(),
            packageBalance: balance,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = "Couldn't save ${_isEditing ? 'the changes' : 'this patient'}. "
            'Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _fullName;
    return CruFormDialog(
      title: _isEditing ? 'Edit patient' : 'New patient',
      subtitle: _isEditing
          ? widget.patient!.fullName
          : 'Add them to your patient list',
      leading: name.isEmpty
          ? const CruIconTile(icon: CruIcons.userPlus, tone: CruTileTone.neutral)
          : CruMonogram(name: name, size: CruSize.iconTile),
      submitLabel: _isEditing ? 'Save changes' : 'Add patient',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isEditing)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: PatientVoiceFillBar(
                  onFill: _applyVoiceFill,
                  service: widget.voiceFillService,
                ),
              ),
            CruFormSection(
              first: true,
              title: 'Patient',
              description: 'As it will appear on the record and on bills.',
              children: [
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'First name',
                      controller: _firstName,
                      autofocus: !_isEditing,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => _required(v, 'Add a first name.'),
                      onChanged: _edited,
                    ),
                    CruTextField(
                      label: 'Last name',
                      controller: _lastName,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => _required(v, 'Add a last name.'),
                      onChanged: _edited,
                    ),
                  ],
                ),
                CruFieldFrame(
                  label: 'Sex',
                  error: _submitted && _sex == null ? 'Choose one.' : null,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CruSegmentedControl<String?>(
                      semanticLabel: 'Sex',
                      segments: [for (final s in _sexes) CruSegment(s, s)],
                      selected: _sex,
                      onChanged: (v) {
                        _sex = v;
                        _edited();
                      },
                    ),
                  ),
                ),
                CruFieldRow(
                  flex: const [3, 1],
                  children: [
                    CruPickerField(
                      label: 'Date of birth',
                      icon: CruIcons.calendar,
                      value: _dateOfBirth == null || _dobFromAge
                          ? null
                          : DateFormat('d MMM yyyy').format(_dateOfBirth!),
                      placeholder: _dobFromAge
                          ? 'Not known, using age'
                          : 'Pick a date',
                      onTap: _pickDateOfBirth,
                      error: _submitted && _dateOfBirth == null
                          ? 'Add a date of birth or an age.'
                          : null,
                    ),
                    CruTextField(
                      label: 'Age',
                      controller: _age,
                      hint: 'Years',
                      tabular: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      validator: _validateAge,
                      onChanged: _onAgeChanged,
                    ),
                  ],
                ),
              ],
            ),
            CruFormSection(
              title: 'Contact',
              description: 'Used for visit reminders and WhatsApp.',
              children: [
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Mobile',
                      controller: _phone,
                      icon: CruIcons.phone,
                      hint: '98765 43210',
                      tabular: true,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                        LengthLimitingTextInputFormatter(16),
                      ],
                      validator: _validatePhone,
                      onChanged: _edited,
                    ),
                    CruTextField(
                      label: 'Email',
                      optional: true,
                      controller: _email,
                      hint: 'name@example.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                      onChanged: _edited,
                    ),
                  ],
                ),
              ],
            ),
            CruFormSection(
              title: 'Clinical',
              description: 'Shown on the profile and at every visit.',
              children: [
                CruTagField(
                  label: 'Conditions',
                  optional: true,
                  values: _conditions,
                  max: Patient.maxDiagnoses,
                  hint: 'Type a condition and press Enter',
                  suggestions: _commonConditions,
                  onChanged: (v) {
                    _conditions = v;
                    _edited();
                  },
                ),
                CruTextField(
                  label: 'Notes',
                  optional: true,
                  controller: _notes,
                  maxLines: 4,
                  hint: 'Allergies, regular medicines, past surgeries…',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: _edited,
                ),
              ],
            ),
            CruFormSection(
              title: 'Account',
              description: 'Prepaid package or advance paid by the patient.',
              children: [
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Package balance',
                      optional: true,
                      controller: _balance,
                      prefix: '₹',
                      hint: '0',
                      tabular: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      onChanged: _edited,
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
