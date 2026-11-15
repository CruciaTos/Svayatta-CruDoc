import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_billing_provider.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/features/voice/domain/name_matcher.dart';

import '../core/ai_tool.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

String? _str(Map<String, Object?> args, String key) {
  final v = args[key];
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Compact patient row for the model: id, name, phone last 4, age.
Map<String, Object?> patientBrief(Patient p) {
  final d = _digits(p.phone);
  return {
    'id': p.id,
    'name': p.fullName.trim(),
    if (d.length >= 4) 'phoneLast4': d.substring(d.length - 4),
    'age': p.age,
  };
}

/// Client-side patient search used by find_patient and search_everything.
/// Matches CruDoc ID, phone digits, name words, then sound-alike names.
List<Patient> matchPatientsForAi(List<Patient> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final byId = all.where((p) => p.id.toLowerCase() == q).toList();
  if (byId.isNotEmpty) return byId;
  final qd = _digits(q);
  if (qd.length >= 3 && qd.length >= q.replaceAll(' ', '').length - 2) {
    return all.where((p) => _digits(p.phone).contains(qd)).toList();
  }
  final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final direct = all.where((p) {
    final n = p.fullName.toLowerCase();
    return words.every(n.contains);
  }).toList();
  if (direct.isNotEmpty) return direct;
  final m = matchPatient(query, all);
  if (m.best == null || m.score < 0.6) return const [];
  return m.tied;
}

Future<Patient?> _load(AiToolContext ctx, String id) =>
    ctx.read(patientRepositoryProvider).getPatient(id);

DateTime? _parseDate(String? s) => s == null ? null : DateTime.tryParse(s);

String? _gender(String? g) {
  switch (g?.trim().toLowerCase()) {
    case 'male':
    case 'm':
      return 'Male';
    case 'female':
    case 'f':
      return 'Female';
    case null:
    case '':
      return null;
    default:
      return 'Other';
  }
}

String _archiveText(Map<String, Object?> args) {
  final reason = _str(args, 'reason');
  return reason == null
      ? 'Archive this patient?'
      : 'Archive this patient? Reason: $reason';
}

List<AiTool> patientTools() => [
  AiTool(
    name: 'find_patient',
    description:
        'Look up patients by name, phone number or CruDoc ID. Use this first '
        'whenever the user mentions a patient. If more than one match comes '
        'back, ask the user which one before doing anything else.',
    group: AiToolGroup.patients,
    risk: AiToolRisk.read,
    permission: ClinicPermission.patientsView,
    phoneSafe: true,
    params: const {
      'query': AiParam.string('Name, phone number or CruDoc ID'),
      'limit': AiParam.integer(
        'Max matches (default 5)',
        required: false,
        min: 1,
        max: 10,
      ),
    },
    run: (ctx, args) async {
      final query = _str(args, 'query');
      if (query == null) return AiToolResult.error('Give a name or phone.');
      final limit = ((args['limit'] as num?)?.toInt() ?? 5).clamp(1, 10);
      final all = await ctx.read(patientsStreamProvider.future);
      final hits = matchPatientsForAi(all, query);
      if (hits.isEmpty) {
        return AiToolResult.error('No patient found for "$query".');
      }
      final shown = hits.take(limit).map(patientBrief).toList();
      return AiToolResult.ok(
        {
          'matches': shown,
          'total': hits.length,
          if (hits.length > 1)
            'note': 'More than one match: ask the user which patient.',
        },
        summary: hits.length == 1
            ? 'Found ${hits.first.fullName.trim()}'
            : '${hits.length} patients match "$query"',
      );
    },
  ),
  AiTool(
    name: 'get_patient_summary',
    description:
        'Short overview of one patient: age, contact, conditions, last visit, '
        'next visit and money still owed. Needs a patientId from find_patient.',
    group: AiToolGroup.patients,
    risk: AiToolRisk.read,
    permission: ClinicPermission.patientsView,
    params: const {'patientId': AiParam.string('Patient id')},
    run: (ctx, args) async {
      final id = _str(args, 'patientId');
      if (id == null) return AiToolResult.error('patientId is required.');
      final p = await _load(ctx, id);
      if (p == null) return AiToolResult.error('Patient not found.');
      List<Visit> visits = const [];
      try {
        visits = await ctx.read(visitsForPatientProvider(id).future);
      } catch (_) {}
      var owed = 0.0;
      try {
        await ctx.read(pendingPaymentsProvider.future);
        await ctx.read(invoicesStreamProvider.future);
        final b = ctx.read(patientBillingProvider(id));
        owed = b.unpaidTotal + b.openBillsTotal;
      } catch (_) {}
      final now = DateTime.now();
      final live = visits.where((v) => !v.isDeleted).toList()
        ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
      Visit? last;
      Visit? next;
      for (final v in live) {
        if (v.status == VisitStatus.completed &&
            v.scheduledStart.isBefore(now)) {
          last = v;
        }
        if (next == null &&
            v.status == VisitStatus.scheduled &&
            v.scheduledStart.isAfter(now)) {
          next = v;
        }
      }
      return AiToolResult.ok({
        ...patientBrief(p),
        'gender': p.gender,
        'phone': p.phone,
        if (p.email.isNotEmpty) 'email': p.email,
        'conditions': p.diagnosis,
        'visitCount': live
            .where((v) => v.status == VisitStatus.completed)
            .length,
        if (last != null) 'lastVisit': _ymd(last.scheduledStart),
        if (next != null) 'nextVisit': next.scheduledStart.toIso8601String(),
        'amountOwed': owed,
      });
    },
  ),
  AiTool(
    name: 'get_patient_medical_alerts',
    description:
        "A patient's recorded medical conditions and whether a doctor's note "
        'exists. Use before suggesting treatment or when asked about alerts.',
    group: AiToolGroup.patients,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {'patientId': AiParam.string('Patient id')},
    run: (ctx, args) async {
      final id = _str(args, 'patientId');
      if (id == null) return AiToolResult.error('patientId is required.');
      final p = await _load(ctx, id);
      if (p == null) return AiToolResult.error('Patient not found.');
      final note = p.notes.trim();
      return AiToolResult.ok({
        'patientId': p.id,
        'name': p.fullName.trim(),
        'conditions': p.diagnosis,
        'hasDoctorsNote': note.isNotEmpty,
        if (note.isNotEmpty)
          'doctorsNote': note.length > 300
              ? '${note.substring(0, 300)}...'
              : note,
        'note':
            "CruDoc has no separate allergy field; allergies appear in "
            "conditions or the doctor's note only if someone wrote them.",
      });
    },
  ),
  AiTool(
    name: 'get_patient_history',
    description:
        "A patient's most recent visits (date, status, treatment, notes), "
        'newest first. Use when asked what was done before.',
    group: AiToolGroup.patients,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {
      'patientId': AiParam.string('Patient id'),
      'limit': AiParam.integer(
        'How many visits (default 5)',
        required: false,
        min: 1,
        max: 10,
      ),
    },
    run: (ctx, args) async {
      final id = _str(args, 'patientId');
      if (id == null) return AiToolResult.error('patientId is required.');
      final limit = ((args['limit'] as num?)?.toInt() ?? 5).clamp(1, 10);
      final visits = await ctx.read(visitsForPatientProvider(id).future);
      final live = visits.where((v) => !v.isDeleted).toList()
        ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
      String cut(String? s) {
        final t = (s ?? '').trim();
        return t.length > 200 ? '${t.substring(0, 200)}...' : t;
      }

      return AiToolResult.ok({
        'total': live.length,
        'visits': [
          for (final v in live.take(limit))
            {
              'visitId': v.id,
              'date': _ymd(v.scheduledStart),
              'status': v.status.value,
              if ((v.treatmentType ?? '').trim().isNotEmpty)
                'treatment': v.treatmentType!.trim(),
              if ((v.therapistNotes ?? '').trim().isNotEmpty)
                'notes': cut(v.therapistNotes),
            },
        ],
      });
    },
  ),
  AiTool(
    name: 'create_patient',
    description:
        'Register a new patient. Needs a first name plus either a date of '
        'birth or an age. Call find_duplicate_patients first if the person '
        'may already exist.',
    group: AiToolGroup.patients,
    risk: AiToolRisk.write,
    permission: ClinicPermission.patientsEdit,
    params: const {
      'firstName': AiParam.string('First name'),
      'lastName': AiParam.string('Last name', required: false),
      'phone': AiParam.string('Phone number', required: false),
      'dob': AiParam.date('Date of birth', required: false),
      'age': AiParam.integer(
        'Age in years, if DOB unknown',
        required: false,
        min: 0,
        max: 120,
      ),
      'gender': AiParam.enumOf(
        ['Male', 'Female', 'Other'],
        'Gender',
        required: false,
      ),
      'email': AiParam.string('Email', required: false),
      'conditions': AiParam.list(
        AiParam.string('A medical condition'),
        'Known medical conditions (max 4)',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final first = _str(args, 'firstName');
      if (first == null) return AiToolResult.error('First name is required.');
      var dob = _parseDate(_str(args, 'dob'));
      final age = (args['age'] as num?)?.toInt();
      if (dob == null && age != null) {
        final n = DateTime.now();
        dob = DateTime(n.year - age, n.month, n.day);
      }
      if (dob == null) {
        return AiToolResult.error(
          'Ask the user for the date of birth or age before creating.',
        );
      }
      final conds = [
        for (final c in (args['conditions'] as List? ?? const []))
          if (c.toString().trim().isNotEmpty) c.toString().trim(),
      ].take(Patient.maxDiagnoses).toList();
      final now = DateTime.now();
      final repo = ctx.read(patientRepositoryProvider);
      final String id;
      try {
        id = await repo.createPatient(
          Patient(
            id: '',
            firstName: first,
            lastName: _str(args, 'lastName') ?? '',
            phone: _str(args, 'phone') ?? '',
            email: _str(args, 'email') ?? '',
            gender: _gender(_str(args, 'gender')) ?? 'Other',
            dateOfBirth: dob,
            diagnosis: conds,
            packageBalance: 0,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } catch (e) {
        return AiToolResult.error('Could not create patient: $e');
      }
      final name = '$first ${_str(args, 'lastName') ?? ''}'.trim();
      return AiToolResult.ok(
        {'patientId': id, 'name': name},
        summary: 'Added patient $name',
        undo: () => repo.deletePatient(id),
      );
    },
  ),
  AiTool(
    name: 'update_patient',
    description:
        "Change a patient's name, phone, email, date of birth or gender. Put "
        'only the fields to change in `fields`. Needs patientId from '
        'find_patient.',
    group: AiToolGroup.patients,
    risk: AiToolRisk.write,
    permission: ClinicPermission.patientsEdit,
    params: const {
      'patientId': AiParam.string('Patient id'),
      'fields': AiParam.object({
        'firstName': AiParam.string('New first name', required: false),
        'lastName': AiParam.string('New last name', required: false),
        'phone': AiParam.string('New phone', required: false),
        'email': AiParam.string('New email', required: false),
        'dob': AiParam.date('New date of birth', required: false),
        'gender': AiParam.enumOf(
          ['Male', 'Female', 'Other'],
          'New gender',
          required: false,
        ),
      }, 'Fields to change'),
    },
    run: (ctx, args) async {
      final id = _str(args, 'patientId');
      final fields = args['fields'];
      if (id == null || fields is! Map) {
        return AiToolResult.error('patientId and fields are required.');
      }
      final f = Map<String, Object?>.from(fields);
      final p = await _load(ctx, id);
      if (p == null) return AiToolResult.error('Patient not found.');
      final change = <String, dynamic>{};
      final before = <String, dynamic>{};
      void put(String key, Object? value, Object? old) {
        change[key] = value;
        before[key] = old;
      }

      final first = _str(f, 'firstName');
      if (first != null) put('firstName', first, p.firstName);
      final last = _str(f, 'lastName');
      if (last != null) put('lastName', last, p.lastName);
      final phone = _str(f, 'phone');
      if (phone != null) put('phone', phone, p.phone);
      final email = _str(f, 'email');
      if (email != null) put('email', email, p.email);
      final g = _gender(_str(f, 'gender'));
      if (g != null) put('gender', g, p.gender);
      final dobStr = _str(f, 'dob');
      if (dobStr != null) {
        final d = _parseDate(dobStr);
        if (d == null) return AiToolResult.error('dob must be YYYY-MM-DD.');
        put('dateOfBirth', d, p.dateOfBirth);
      }
      if (change.isEmpty) return AiToolResult.error('Nothing to change.');
      final repo = ctx.read(patientRepositoryProvider);
      try {
        await repo.updatePatient(id, change);
      } catch (e) {
        return AiToolResult.error('Could not update patient: $e');
      }
      return AiToolResult.ok(
        {'patientId': id, 'updated': change.keys.toList()},
        summary: 'Updated ${p.fullName.trim()}',
        undo: () => repo.updatePatient(id, before),
      );
    },
  ),
  AiTool(
    name: 'add_medical_condition',
    description:
        "Add one medical condition to a patient's record (max 4 per "
        'patient). Needs patientId from find_patient.',
    group: AiToolGroup.patients,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'patientId': AiParam.string('Patient id'),
      'condition': AiParam.string('Condition, e.g. Diabetes'),
    },
    run: (ctx, args) async {
      final id = _str(args, 'patientId');
      final cond = _str(args, 'condition');
      if (id == null || cond == null) {
        return AiToolResult.error('patientId and condition are required.');
      }
      final p = await _load(ctx, id);
      if (p == null) return AiToolResult.error('Patient not found.');
      if (p.diagnosis.any((d) => d.toLowerCase() == cond.toLowerCase())) {
        return AiToolResult.ok({
          'patientId': id,
          'conditions': p.diagnosis,
          'note': 'Already recorded.',
        });
      }
      if (p.diagnosis.length >= Patient.maxDiagnoses) {
        return AiToolResult.error(
          'A patient can have at most ${Patient.maxDiagnoses} conditions.',
          data: {'conditions': p.diagnosis},
        );
      }
      final old = List<String>.of(p.diagnosis);
      final repo = ctx.read(patientRepositoryProvider);
      try {
        await repo.updatePatient(id, {
          'diagnosis': [...old, cond],
        });
      } catch (e) {
        return AiToolResult.error('Could not save: $e');
      }
      return AiToolResult.ok(
        {
          'patientId': id,
          'conditions': [...old, cond],
        },
        summary: 'Added $cond for ${p.fullName.trim()}',
        undo: () => repo.updatePatient(id, {'diagnosis': old}),
      );
    },
  ),
  AiTool(
    name: 'set_doctors_note',
    description:
        "Replace the patient's free-form doctor's note with the given text. "
        'Include the existing text in the new note if it should be kept.',
    group: AiToolGroup.patients,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'patientId': AiParam.string('Patient id'),
      'note': AiParam.string('Full new note text'),
    },
    run: (ctx, args) async {
      final id = _str(args, 'patientId');
      final note = args['note'];
      if (id == null || note is! String) {
        return AiToolResult.error('patientId and note are required.');
      }
      final p = await _load(ctx, id);
      if (p == null) return AiToolResult.error('Patient not found.');
      final old = p.notes;
      final repo = ctx.read(patientRepositoryProvider);
      try {
        await repo.updateDoctorsNote(id, note);
      } catch (e) {
        return AiToolResult.error('Could not save note: $e');
      }
      return AiToolResult.ok(
        {'patientId': id, 'replacedExistingNote': old.trim().isNotEmpty},
        summary: "Saved doctor's note for ${p.fullName.trim()}",
        undo: () => repo.updateDoctorsNote(id, old),
      );
    },
  ),
  AiTool(
    name: 'find_duplicate_patients',
    description:
        'Check whether a patient with this name or phone already exists. Use '
        'before create_patient.',
    group: AiToolGroup.patients,
    risk: AiToolRisk.read,
    permission: ClinicPermission.patientsView,
    params: const {
      'name': AiParam.string('Name to check', required: false),
      'phone': AiParam.string('Phone to check', required: false),
    },
    run: (ctx, args) async {
      final name = _str(args, 'name');
      final phone = _str(args, 'phone');
      if (name == null && phone == null) {
        return AiToolResult.error('Give a name or a phone.');
      }
      final all = await ctx.read(patientsStreamProvider.future);
      final found = <String, Patient>{};
      if (phone != null && _digits(phone).length >= 6) {
        final pd = _digits(phone);
        final tail = pd.length > 10 ? pd.substring(pd.length - 10) : pd;
        for (final p in all) {
          if (_digits(p.phone).endsWith(tail)) found[p.id] = p;
        }
      }
      if (name != null) {
        for (final p in matchPatientsForAi(all, name)) {
          found[p.id] = p;
        }
      }
      return AiToolResult.ok({
        'duplicatesFound': found.length,
        'matches': found.values.take(10).map(patientBrief).toList(),
      });
    },
  ),
  AiTool(
    name: 'archive_patient',
    description:
        'Archive (soft-delete) a patient so they leave the active list. The '
        'record is not erased. Needs patientId from find_patient and a '
        'reason.',
    group: AiToolGroup.patients,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.patientsEdit,
    params: const {
      'patientId': AiParam.string('Patient id'),
      'reason': AiParam.string('Why the patient is being archived'),
    },
    confirmText: _archiveText,
    run: (ctx, args) async {
      final id = _str(args, 'patientId');
      if (id == null) return AiToolResult.error('patientId is required.');
      final p = await _load(ctx, id);
      if (p == null) return AiToolResult.error('Patient not found.');
      try {
        await ctx.read(patientRepositoryProvider).deletePatient(id);
      } catch (e) {
        return AiToolResult.error('Could not archive: $e');
      }
      return AiToolResult.ok({
        'patientId': id,
        'archived': true,
      }, summary: 'Archived ${p.fullName.trim()}');
    },
  ),
];
