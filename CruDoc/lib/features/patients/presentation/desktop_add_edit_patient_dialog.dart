import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/voice/domain/medical_conditions.dart';
import 'package:doctor_management_app/features/voice/presentation/voice_dialog_hook.dart';

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
    builder: (_) =>
        DesktopAddEditPatientDialog(patient: patient, repository: repository),
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
    extends State<DesktopAddEditPatientDialog>
    with VoiceDialogHook<DesktopAddEditPatientDialog> {
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

  int _revealFirstName = 0;
  int _revealLastName = 0;
  int _revealDob = 0;
  int _revealAge = 0;
  int _revealPhone = 0;
  int _revealEmail = 0;
  int _revealConditions = 0;
  int _revealNotes = 0;
  int _revealBalance = 0;

  bool _pendingFirstName = false;
  bool _pendingLastName = false;
  bool _pendingDob = false;
  bool _pendingAge = false;
  bool _pendingPhone = false;
  bool _pendingEmail = false;
  bool _pendingConditions = false;
  bool _pendingNotes = false;
  bool _pendingBalance = false;

  late List<String> _conditions;
  List<String> _baseConditions = const [];

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
    _baseConditions = List.of(_conditions);
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
    onVoiceFill(
      VoiceFill(
        isFinal: true,
        firstName: fill.firstName.isEmpty ? null : fill.firstName,
        lastName: fill.lastName.isEmpty ? null : fill.lastName,
        phone: fill.phone.isEmpty ? null : fill.phone,
        email: fill.email.isEmpty ? null : fill.email,
        gender: fill.gender,
        dateOfBirth: fill.dateOfBirth,
        age: fill.ageYears,
        conditions: fill.conditions,
        notes: fill.notes.isEmpty ? null : fill.notes,
        balance: fill.packageBalance,
      ),
    );
  }

  @override
  void onVoiceFill(VoiceFill f) {
    final raw = (f.rawText ?? '').toLowerCase();

    setState(() {
      // 1. FAST STREAM FIELD DETECTION (Dissolve into smoke):
      // If a field was mentioned in speech but hasn't received its value yet,
      // dissolve it into smoke immediately so it is waiting in fog.
      if (f.firstName == null &&
          f.lastName == null &&
          (raw.contains('name') ||
              raw.contains('called') ||
              raw.contains('patient') ||
              raw.contains('mr ') ||
              raw.contains('mrs '))) {
        if (_firstName.text.isEmpty) _pendingFirstName = true;
        if (_lastName.text.isEmpty) _pendingLastName = true;
      }

      if (f.dateOfBirth == null &&
          (raw.contains('birth') ||
              raw.contains('born') ||
              raw.contains('dob'))) {
        if (_dateOfBirth == null) {
          _pendingDob = true;
          _pendingAge = true;
        }
      } else if (f.age == null &&
          (raw.contains('age') ||
              raw.contains('years old') ||
              raw.contains('year old'))) {
        if (_age.text.isEmpty) _pendingAge = true;
      }

      if (f.phone == null &&
          (raw.contains('phone') ||
              raw.contains('mobile') ||
              raw.contains('contact') ||
              raw.contains('number'))) {
        if (_phone.text.isEmpty) _pendingPhone = true;
      }

      if (f.email == null &&
          (raw.contains('email') ||
              raw.contains('mail') ||
              raw.contains('@'))) {
        if (_email.text.isEmpty) _pendingEmail = true;
      }

      if (f.conditions.isEmpty &&
          (raw.contains('suffer') ||
              raw.contains('condition') ||
              raw.contains('diagnos') ||
              raw.contains('pain') ||
              raw.contains('complains'))) {
        _pendingConditions = true;
      }

      if (f.notes == null &&
          (raw.contains('note') ||
              raw.contains('allerg') ||
              raw.contains('medicine') ||
              raw.contains('surger'))) {
        _pendingNotes = true;
      }

      if (f.balance == null &&
          (raw.contains('balance') ||
              raw.contains('package') ||
              raw.contains('advance') ||
              raw.contains('paid') ||
              raw.contains('rupees'))) {
        if (_balance.text.isEmpty) _pendingBalance = true;
      }

      // 2. LIVE PROGRESSIVE FIELD POPULATION (Emergence while user is STILL speaking):
      // As soon as ANY field value is recognized, populate it immediately! Do NOT wait for key-up!
      // But for names, wait until the user finishes speaking or moves past the name
      // to prevent flickering and stuttering on intermediate syllable guesses.
      final movedPastName =
          f.isFinal ||
          f.gender != null ||
          f.dateOfBirth != null ||
          f.age != null ||
          f.phone != null ||
          f.email != null ||
          f.conditions.isNotEmpty ||
          f.notes != null ||
          f.balance != null ||
          raw.contains('years') ||
          raw.contains('year old') ||
          raw.contains('age') ||
          raw.contains('born') ||
          raw.contains('dob') ||
          raw.contains('male') ||
          raw.contains('female') ||
          raw.contains('phone') ||
          raw.contains('contact') ||
          raw.contains('email') ||
          raw.contains('note') ||
          raw.contains('allerg') ||
          raw.contains('diagnos') ||
          raw.contains('suffer');

      if (movedPastName) {
        if (f.firstName != null &&
            f.firstName!.isNotEmpty &&
            _firstName.text != f.firstName!) {
          _firstName.text = f.firstName!;
          _pendingFirstName = false;
          _revealFirstName++;
        }
        if (f.lastName != null &&
            f.lastName!.isNotEmpty &&
            _lastName.text != f.lastName!) {
          _lastName.text = f.lastName!;
          _pendingLastName = false;
          _revealLastName++;
        }
      }
      if (f.phone != null && f.phone!.isNotEmpty && _phone.text != f.phone!) {
        _phone.text = f.phone!;
        _pendingPhone = false;
        _revealPhone++;
      }
      if (f.email != null && f.email!.isNotEmpty && _email.text != f.email!) {
        _email.text = f.email!;
        _pendingEmail = false;
        _revealEmail++;
      }
      // Sex is toggled directly without blur or disappearing animation
      if (f.gender != null && _sexes.contains(f.gender) && _sex != f.gender) {
        _sex = f.gender;
      }
      if (f.dateOfBirth != null && _dateOfBirth != f.dateOfBirth) {
        _dateOfBirth = f.dateOfBirth;
        _dobFromAge = false;
        _pendingDob = false;
        _revealDob++;
        final aStr = '${_ageOn(_dateOfBirth)}';
        if (_age.text != aStr) {
          _age.text = aStr;
          _pendingAge = false;
          _revealAge++;
        }
      } else if (f.age != null && _age.text != '${f.age}') {
        _age.text = '${f.age}';
        _onAgeChanged(_age.text);
        _pendingAge = false;
        _revealAge++;
      }
      if (f.conditions.isNotEmpty) {
        final seen = <String>{};
        final newConds = [..._baseConditions, ...f.conditions]
            .where((c) => seen.add(c.toLowerCase()))
            .take(Patient.maxDiagnoses)
            .toList();
        if (_conditions.length != newConds.length) {
          _conditions = newConds;
          _baseConditions = List.of(_conditions);
          _pendingConditions = false;
          _revealConditions++;
        }
      }
      if (f.notes != null && f.notes!.trim().isNotEmpty) {
        _voiceNotesBase ??= _notes.text.trim();
        final base = _voiceNotesBase!;
        final combined = base.isEmpty
            ? f.notes!.trim()
            : joinBulletNotes(base, f.notes!);
        if (_notes.text != combined) {
          _notes.text = combined;
          _pendingNotes = false;
          _revealNotes++;
        }
      }
      if (f.balance != null) {
        final balStr = f.balance!.toStringAsFixed(0);
        if (_balance.text != balStr) {
          _balance.text = balStr;
          _pendingBalance = false;
          _revealBalance++;
        }
      }

      // 3. FINAL CLEANUP (When spacebar is finally released):
      if (f.isFinal) {
        _pendingFirstName = false;
        _pendingLastName = false;
        _pendingDob = false;
        _pendingAge = false;
        _pendingPhone = false;
        _pendingEmail = false;
        _pendingConditions = false;
        _pendingNotes = false;
        _pendingBalance = false;
      }
    });
    _edited();
  }

  /// Notes typed before voice started adding to them.
  String? _voiceNotesBase;

  @override
  List<String> voiceMissing() => [
    if (_firstName.text.trim().isEmpty) 'first name',
    if (_lastName.text.trim().isEmpty) 'last name',
    if (_sex == null) 'sex',
    if (_dateOfBirth == null) 'age',
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 10) 'mobile',
  ];

  @override
  void onVoiceConfirm() => _save();

  @override
  String get voiceKind => widget.patient == null ? 'addPatient' : 'editPatient';

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
        _notice =
            "Couldn't save ${_isEditing ? 'the changes' : 'this patient'}. "
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
          ? const CruIconTile(
              icon: CruIcons.userPlus,
              tone: CruTileTone.neutral,
            )
          : CruMonogram(
              name: name,
              size: CruSize.iconTile,
            ),
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
                      hint: 'e.g. Maya',
                      controller: _firstName,
                      autofocus: !_isEditing,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => _required(v, 'Add a first name.'),
                      onChanged: _edited,
                      aiRevealKey: _revealFirstName,
                      aiPending: _pendingFirstName,
                    ),
                    CruTextField(
                      label: 'Last name',
                      hint: 'e.g. Patel',
                      controller: _lastName,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => _required(v, 'Add a last name.'),
                      onChanged: _edited,
                      aiRevealKey: _revealLastName,
                      aiPending: _pendingLastName,
                      aiStagger: const Duration(milliseconds: 60),
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
                      aiRevealKey: _revealDob,
                      aiPending: _pendingDob,
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
                      aiRevealKey: _revealAge,
                      aiPending: _pendingAge,
                      aiStagger: const Duration(milliseconds: 180),
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
                      aiRevealKey: _revealPhone,
                      aiPending: _pendingPhone,
                      aiStagger: const Duration(milliseconds: 240),
                    ),
                    CruTextField(
                      label: 'Email',
                      optional: true,
                      controller: _email,
                      hint: 'name@example.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                      onChanged: _edited,
                      aiRevealKey: _revealEmail,
                      aiPending: _pendingEmail,
                      aiStagger: const Duration(milliseconds: 300),
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
                    _baseConditions = List.of(_conditions);
                    _edited();
                  },
                  aiRevealKey: _revealConditions,
                  aiPending: _pendingConditions,
                  aiStagger: const Duration(milliseconds: 360),
                ),
                CruTextField(
                  label: 'Notes',
                  optional: true,
                  controller: _notes,
                  maxLines: 4,
                  hint: 'Allergies, regular medicines, past surgeries…',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: _edited,
                  aiRevealKey: _revealNotes,
                  aiPending: _pendingNotes,
                  aiStagger: const Duration(milliseconds: 420),
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
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      onChanged: _edited,
                      aiRevealKey: _revealBalance,
                      aiPending: _pendingBalance,
                      aiStagger: const Duration(milliseconds: 480),
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
