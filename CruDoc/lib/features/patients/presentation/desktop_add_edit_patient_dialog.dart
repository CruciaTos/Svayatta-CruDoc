import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/abdm/data/abdm_api.dart';
import 'package:doctor_management_app/features/abdm/domain/abha_input.dart';
import 'package:doctor_management_app/features/abdm/presentation/abha_flow_dialog.dart';
import 'package:doctor_management_app/features/abdm/presentation/abha_linked_dialog.dart';
import 'package:doctor_management_app/features/voice/domain/medical_conditions.dart';
import 'package:doctor_management_app/features/voice/presentation/voice_dialog_hook.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/domain/duplicate_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/features/messaging/data/providers/reminder_settings_providers.dart';
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
  ValueChanged<String>? onCreated,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DesktopAddEditPatientDialog(
      patient: patient,
      repository: repository,
      onCreated: onCreated,
    ),
  );
}

class DesktopAddEditPatientDialog extends ConsumerStatefulWidget {
  const DesktopAddEditPatientDialog({
    super.key,
    this.patient,
    this.repository,
    this.voiceFillService,
    this.onCreated,
  });

  final Patient? patient;
  final PatientRepository? repository;
  final ValueChanged<String>? onCreated;

  /// Injected in tests.
  final PatientVoiceFillService? voiceFillService;

  @override
  ConsumerState<DesktopAddEditPatientDialog> createState() =>
      _DesktopAddEditPatientDialogState();
}

class _DesktopAddEditPatientDialogState
    extends ConsumerState<DesktopAddEditPatientDialog>
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

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _age;
  late final TextEditingController _notes;

  String? _sex;
  DateTime? _dateOfBirth;

  /// True when [_dateOfBirth] was worked out from a typed age.
  bool _dobFromAge = false;

  int _revealName = 0;
  int _revealDob = 0;
  int _revealAge = 0;
  int _revealPhone = 0;
  int _revealEmail = 0;
  int _revealConditions = 0;
  int _revealNotes = 0;

  bool _pendingName = false;
  bool _pendingDob = false;
  bool _pendingAge = false;
  bool _pendingPhone = false;
  bool _pendingEmail = false;
  bool _pendingConditions = false;
  bool _pendingNotes = false;

  late List<String> _conditions;
  List<String> _baseConditions = const [];

  bool _dirty = false;
  bool _saving = false;
  bool _submitted = false;
  String? _notice;

  AbhaResult? _abhaResult;
  bool _lockName = false;
  bool _lockSex = false;
  bool _lockDob = false;

  bool get _isEditing => widget.patient != null;

  /// Conditions and notes, for people who may hold them. The front desk
  /// enters them when registering someone, but doesn't see a patient's
  /// existing ones (see ClinicSession.holdsClinicalFields).
  bool get _showsClinical =>
      !_isEditing || ClinicSession.instance.holdsClinicalFields;

  @override
  void initState() {
    super.initState();
    final p = widget.patient;
    _name = TextEditingController(text: p?.fullName.trim() ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
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
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _age.dispose();
    _notes.dispose();
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

  String get _fullName => _name.text.trim();

  static String? _mapAbdmGender(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'M':
      case 'MALE':
        return 'Male';
      case 'F':
      case 'FEMALE':
        return 'Female';
      case 'O':
      case 'OTHER':
      case 'T':
        return 'Other';
      default:
        return null;
    }
  }

  Future<void> _fillFromAbha() async {
    final res = await showAbhaFlowDialog(context);
    if (res == null || !mounted) return;

    if (res.existingPatientId != null && res.existingPatientId!.isNotEmpty) {
      final existingList =
          ref.read(patientsStreamProvider).value ?? const <Patient>[];
      final existing = existingList
          .where((p) => p.id == res.existingPatientId)
          .firstOrNull;
      final openExisting = await showAbhaLinkedDialog(
        context,
        profile: res.profile,
        patientId: res.existingPatientId!,
        existing: existing,
      );
      if (!mounted) return;
      if (openExisting == true) {
        widget.onCreated?.call(res.existingPatientId!);
        Navigator.of(context).pop(true);
      }
      return;
    }

    setState(() {
      _abhaResult = res;
      _dirty = true;
      _notice = null;
      _lockName = false;
      _lockSex = false;
      _lockDob = false;
      if (res.profile.name.isNotEmpty) {
        _name.text = res.profile.name;
        _lockName = true;
      }
      final mappedSex = _mapAbdmGender(res.profile.gender);
      if (mappedSex != null) {
        _sex = mappedSex;
        _lockSex = true;
      }
      if (res.profile.dateOfBirth != null) {
        _dateOfBirth = res.profile.dateOfBirth;
        _dobFromAge = false;
        _age.text = '${_ageOn(_dateOfBirth)}';
        _lockDob = true;
      }
      final rawMobile = res.unmaskedMobile ?? res.profile.mobile;
      if (!rawMobile.contains('*') && isValidMobile(rawMobile)) {
        _phone.text = digitsOnly(rawMobile);
      }
    });
  }

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
        if (_name.text.isEmpty) _pendingName = true;
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

      if (!_lockName && movedPastName) {
        final spokenName = [f.firstName, f.lastName]
            .where((s) => s != null && s.trim().isNotEmpty)
            .map((s) => s!.trim())
            .join(' ');
        if (spokenName.isNotEmpty && _name.text != spokenName) {
          _name.text = spokenName;
          _pendingName = false;
          _revealName++;
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
      if (!_lockSex &&
          f.gender != null &&
          _sexes.contains(f.gender) &&
          _sex != f.gender) {
        _sex = f.gender;
      }
      if (!_lockDob &&
          f.dateOfBirth != null &&
          _dateOfBirth != f.dateOfBirth) {
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
      } else if (!_lockDob && f.age != null && _age.text != '${f.age}') {
        _age.text = '${f.age}';
        _onAgeChanged(_age.text);
        _pendingAge = false;
        _revealAge++;
      }
      // The careful reading replaces what this utterance's live passes
      // added ("Sneha, migraine" read as a condition and a name).
      if (f.corrected) {
        final keep = {for (final c in f.conditions) c.toLowerCase()};
        final kept = _conditions
            .where(
              (c) =>
                  !_utteranceConditions.contains(c.toLowerCase()) ||
                  keep.contains(c.toLowerCase()),
            )
            .toList();
        if (kept.length != _conditions.length) {
          _conditions = kept;
          _revealConditions++;
        }
        _baseConditions = List.of(_conditions);
        _utteranceConditions.clear();
      } else {
        final had = {for (final c in _conditions) c.toLowerCase()};
        _utteranceConditions.addAll(
          f.conditions
              .map((c) => c.toLowerCase())
              .where((c) => !had.contains(c)),
        );
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
      // 3. FINAL CLEANUP (When spacebar is finally released):
      if (f.isFinal) {
        _pendingName = false;
        _pendingDob = false;
        _pendingAge = false;
        _pendingPhone = false;
        _pendingEmail = false;
        _pendingConditions = false;
        _pendingNotes = false;
      }
    });
    _edited();
  }

  /// Notes typed before voice started adding to them.
  String? _voiceNotesBase;

  /// Conditions the current utterance's live passes added, lower case.
  final _utteranceConditions = <String>{};

  @override
  List<String> voiceMissing() => [
    if (_name.text.trim().isEmpty) 'name',
    if (_sex == null) 'sex',
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

  /// Never throws: the patient is already saved, so a failed link must not
  /// make Save create them twice.
  Future<void> _linkAbha(String id, AbhaResult abha) async {
    String? problem;
    try {
      final r = await AbdmApi.instance.link(flowId: abha.flowId, patientId: id);
      if (r.linked) {
        await _repository.updatePatient(id, {
          'abhaNumber': abha.profile.abhaNumber,
          'abhaAddress': abha.profile.abhaAddress,
          'abhaVerifiedAt': DateTime.now(),
        });
      } else {
        problem = 'This ABHA is already linked to another patient.';
      }
    } on AbdmException catch (e) {
      problem = e.message;
    } catch (_) {
      problem = "Couldn't link the ABHA.";
    }
    if (problem != null && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Patient saved. $problem')),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    final fieldsOk = _formKey.currentState!.validate();
    if (!fieldsOk || _sex == null) return;

    setState(() {
      _saving = true;
      _notice = null;
    });

    final now = DateTime.now();
    final nameParts = _name.text.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    final dob =
        _dateOfBirth ?? (_isEditing ? widget.patient!.dateOfBirth : now);
    final phone = _phone.text.trim();

    try {
      if (_isEditing) {
        await _repository.updatePatient(widget.patient!.id, {
          'firstName': firstName,
          'lastName': lastName,
          'phone': phone,
          'email': _email.text.trim(),
          'gender': _sex,
          'dateOfBirth': dob,
          'diagnosis': List<String>.from(_conditions),
          'notes': _notes.text.trim(),
        });
      } else {
        if (phone.isNotEmpty) {
          final existing =
              ref.read(patientsStreamProvider).value ?? const <Patient>[];
          final dup = duplicateByPhone(existing, phone);
          if (dup != null) {
            final useExisting = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (dContext) => PatientDialog(
                title: '${dup.fullName} already has this number',
                body: Text(
                  '${dup.phone} · ${dup.age}',
                  style: CruType.text.tabular.tint(dContext.cru.label2),
                ),
                cancelLabel: 'Add anyway',
                confirmLabel: 'Use ${dup.fullName}',
                onConfirm: () => Navigator.of(dContext).pop(true),
              ),
            );
            if (!mounted) return;
            if (useExisting == true) {
              if (_abhaResult != null) {
                final existingNum = digitsOnly(dup.abhaNumber);
                final newNum = digitsOnly(_abhaResult!.profile.abhaNumber);
                if (existingNum.isNotEmpty && existingNum != newNum) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'That patient already has a different ABHA.',
                      ),
                    ),
                  );
                } else {
                  await _linkAbha(dup.id, _abhaResult!);
                }
              }
              if (!mounted) return;
              widget.onCreated?.call(dup.id);
              Navigator.of(context).pop(true);
              return;
            }
          }
        }

        final id = await _repository.createPatient(
          Patient(
            id: '',
            firstName: firstName,
            lastName: lastName,
            phone: phone,
            email: _email.text.trim(),
            gender: _sex!,
            dateOfBirth: dob,
            diagnosis: List.unmodifiable(_conditions),
            notes: _notes.text.trim(),
            packageBalance: 0,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (_abhaResult != null) {
          await _linkAbha(id, _abhaResult!);
        }
        widget.onCreated?.call(id);
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
      subtitle: _isEditing ? widget.patient!.fullName : null,
      leading: name.isEmpty
          ? const CruIconTile(
              icon: CruIcons.userPlus,
              tone: CruTileTone.neutral,
            )
          : CruMonogram(name: name, size: CruSize.iconTile),
      submitLabel: _isEditing ? 'Save changes' : 'Add patient',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      body: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isEditing) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PatientVoiceFillBar(
                  onFill: _applyVoiceFill,
                  service: widget.voiceFillService,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CruButton(
                    label: _abhaResult == null
                        ? 'Fill from ABHA'
                        : 'ABHA: ${_abhaResult!.profile.abhaNumber}',
                    kind: CruButtonKind.secondary,
                    onPressed: _saving ? null : _fillFromAbha,
                  ),
                ),
              ),
            ],
            CruFormSection(
              first: true,
              title: 'Patient',
              children: [
                CruTextField(
                  label: 'Name',
                  hint: 'e.g. Maya Patel',
                  controller: _name,
                  enabled: !_lockName,
                  autofocus: !_isEditing,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => _required(v, 'Add a name.'),
                  onChanged: _edited,
                  aiRevealKey: _revealName,
                  aiPending: _pendingName,
                ),
                CruFieldFrame(
                  label: 'Sex',
                  error: _submitted && _sex == null ? 'Choose one.' : null,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CruSegmentedControl<String?>(
                      semanticLabel: 'Sex',
                      segments: [
                        for (final s in _sexes)
                          CruSegment(s, s, enabled: !_lockSex || s == _sex),
                      ],
                      selected: _sex,
                      onChanged: (v) {
                        if (_lockSex) return;
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
                      optional: true,
                      icon: CruIcons.calendar,
                      value: _dateOfBirth == null || _dobFromAge
                          ? null
                          : DateFormat('d MMM yyyy').format(_dateOfBirth!),
                      placeholder: _dobFromAge
                          ? 'Not known, using age'
                          : 'Pick a date',
                      onTap: () {
                        if (!_lockDob) _pickDateOfBirth();
                      },
                      aiRevealKey: _revealDob,
                      aiPending: _pendingDob,
                    ),
                    CruTextField(
                      label: 'Age',
                      optional: true,
                      controller: _age,
                      enabled: !_lockDob,
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
                _ReminderNotice(patientId: widget.patient?.id),
                CruMoreFields(
                  label: 'Email',
                  open: _email.text.isNotEmpty || _pendingEmail,
                  children: [
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
            if (_showsClinical)
              CruFormSection(
                title: 'Clinical',
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
                  CruMoreFields(
                    label: 'Notes',
                    open: _notes.text.isNotEmpty || _pendingNotes,
                    children: [
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
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Tells the patient, where they hand over their number, what it will be used
/// for.
///
/// This is the consent the reminders rest on: the number is given for
/// appointments, and the person giving it is told in the same breath that
/// reminders come by WhatsApp and how to stop them. Shown only when this
/// clinic actually has reminders switched on, so it never promises a message
/// that will not arrive.
class _ReminderNotice extends ConsumerWidget {
  const _ReminderNotice({this.patientId});

  /// Set when editing, which adds this patient's own on/off switch.
  final String? patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(whatsAppRemindersAvailableProvider);
    final enabled = ref.watch(whatsAppRemindersEnabledProvider);
    if (!available || !enabled) return const SizedBox.shrink();

    final c = context.cru;
    final id = patientId;
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (id != null) ...[
            _SendRemindersSwitch(patientId: id),
            const SizedBox(height: CruSpace.s12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: CruSpace.s2),
                child: CruIcon(CruIcons.whatsapp, size: 14, color: c.label3),
              ),
              const SizedBox(width: CruSpace.s8),
              Expanded(
                child: Text(
                  'Appointment reminders will be sent on WhatsApp. '
                  'Reply STOP to opt out.',
                  style: CruType.caption.tint(c.label2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Whether this patient gets automatic reminders and recalls. Writes
/// `remindersOptOut` on the patient (absent or false means on), which the
/// server reads before every message, on any channel.
class _SendRemindersSwitch extends StatelessWidget {
  const _SendRemindersSwitch({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final ref = FirebaseFirestore.instance
        .collection('patients')
        .doc(patientId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final on = snap.data?.data()?['remindersOptOut'] != true;
        return Row(
          children: [
            Expanded(
              child: Text('Send reminders', style: CruType.row.tint(c.label)),
            ),
            CruSegmentedControl<bool>(
              semanticLabel: 'Send reminders',
              segments: const [
                CruSegment(false, 'Off'),
                CruSegment(true, 'On'),
              ],
              selected: on,
              onChanged: (v) =>
                  ref.set({'remindersOptOut': !v}, SetOptions(merge: true)),
            ),
          ],
        );
      },
    );
  }
}
