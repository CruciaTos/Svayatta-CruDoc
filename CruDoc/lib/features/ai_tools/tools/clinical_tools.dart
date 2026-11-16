import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/ai_tools/core/ai_tool.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_session_note.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';

const _uuid = Uuid();

const _noteSections = ['complaint', 'findings', 'diagnosis', 'advice'];

String? _s(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _dateStr(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _cut(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}...';

Map<String, Object?> _noteJson(ConsultationNote n) => {
  'noteId': n.id,
  'patientId': n.patientId,
  if (n.visitId.isNotEmpty) 'visitId': n.visitId,
  'date': _dateStr(n.createdAt),
  'status': n.status.value,
  if (n.chiefComplaint.trim().isNotEmpty)
    'complaint': _cut(n.chiefComplaint.trim(), 600),
  if (n.notes.trim().isNotEmpty) 'findings': _cut(n.notes.trim(), 2000),
  if (n.diagnosisSuggestions.isNotEmpty) 'diagnosis': n.diagnosisSuggestions,
  if (n.advice.trim().isNotEmpty) 'advice': _cut(n.advice.trim(), 600),
  if (n.medicines.isNotEmpty)
    'medicines': [
      for (final m in n.medicines)
        {
          'name': m.name,
          if (m.dosage.isNotEmpty) 'dosage': m.dosage,
          if (m.instructions.isNotEmpty) 'instructions': m.instructions,
        },
    ],
  if (n.followUpDate != null) 'followUp': _dateStr(n.followUpDate!),
};

List<AiTool> clinicalTools() => [
  AiTool(
    name: 'add_clinical_note',
    description:
        'Adds a quick note to the patient\'s doctor\'s notes (appended after '
        'what is already there), like "allergic to penicillin". For a '
        'visit\'s consultation note use update_consultation_note.',
    group: AiToolGroup.clinical,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'patientId': AiParam.string('Patient ID from find_patient'),
      'text': AiParam.string('The note, in the doctor\'s words'),
    },
    run: (ctx, args) async {
      final patientId = args['patientId'] as String;
      final text = (args['text'] as String).trim();
      final repo = ctx.read(patientRepositoryProvider);
      final patient = await repo.getPatient(patientId);
      if (patient == null) return AiToolResult.error('No such patient');
      final old = patient.notes;
      final combined = [
        old.trim(),
        text,
      ].where((s) => s.isNotEmpty).join('\n');
      await repo.updateDoctorsNote(patientId, combined);
      return AiToolResult.ok(
        {'patientId': patientId, 'added': _cut(text, 200)},
        summary: 'Note added for ${patient.fullName}',
        undo: () => repo.updateDoctorsNote(patientId, old),
      );
    },
  ),
  AiTool(
    name: 'get_consultation_note',
    description:
        'Reads a saved consultation (session) note by noteId, or the newest '
        'note of a visit by visitId. Returns complaint, findings, diagnosis, '
        'advice and medicines.',
    group: AiToolGroup.clinical,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {
      'noteId': AiParam.string('Note ID', required: false),
      'visitId': AiParam.string('Visit ID', required: false),
    },
    run: (ctx, args) async {
      final noteId = _s(args['noteId']);
      final visitId = _s(args['visitId']);
      if (noteId == null && visitId == null) {
        return AiToolResult.error('Give a noteId or a visitId');
      }
      final repo = ctx.read(consultationNoteRepositoryProvider);
      ConsultationNote? note;
      if (noteId != null) {
        note = await repo.getNote(noteId);
      } else {
        final notes = await repo.watchNotesForVisit(visitId!).first;
        for (final n in notes) {
          if (n.status == ConsultationNoteStatus.confirmed) {
            note = n;
            break;
          }
        }
        note ??= notes.isEmpty ? null : notes.first;
      }
      if (note == null) return AiToolResult.error('No note found');
      return AiToolResult.ok(_noteJson(note));
    },
  ),
  AiTool(
    name: 'update_consultation_note',
    description:
        'Replaces one section of a saved consultation note with new text. '
        'Sections: complaint, findings (the note\'s main text), diagnosis '
        '(separate several with semicolons), advice. Read the note first '
        'with get_consultation_note so you do not erase text the doctor '
        'wants kept.',
    group: AiToolGroup.clinical,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'noteId': AiParam.string('Note ID from get_consultation_note'),
      'section': AiParam.enumOf(_noteSections, 'Which section to replace'),
      'text': AiParam.string('The full new text of that section'),
    },
    run: (ctx, args) async {
      final repo = ctx.read(consultationNoteRepositoryProvider);
      final previous = await repo.getNote(args['noteId'] as String);
      if (previous == null) return AiToolResult.error('No such note');
      final section = args['section'] as String;
      final text = (args['text'] as String).trim();
      final edited = switch (section) {
        'complaint' => previous.copyWith(chiefComplaint: text),
        'findings' => previous.copyWith(notes: text),
        'diagnosis' => previous.copyWith(
          diagnosisSuggestions: [
            for (final d in text.split(RegExp(r'[;\n]')))
              if (d.trim().isNotEmpty) d.trim(),
          ],
        ),
        _ => previous.copyWith(advice: text),
      };
      await repo.updateSessionNote(edited);
      return AiToolResult.ok(
        {'noteId': previous.id, 'section': section},
        summary: 'Updated the $section of the consultation note',
        undo: () async {
          await repo.updateSessionNote(previous);
        },
      );
    },
  ),
  AiTool(
    name: 'draft_prescription',
    description:
        'Saves a DRAFT prescription for a patient from the doctor\'s dictated '
        'medicines. It is not issued or signed: the doctor reviews it and '
        'generates the Rx themselves. Only include drugs the doctor named; '
        'never suggest drugs or doses on your own.',
    group: AiToolGroup.clinical,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'patientId': AiParam.string('Patient ID from find_patient'),
      'items': AiParam.list(
        AiParam.object({
          'drug': AiParam.string('Drug name'),
          'dose': AiParam.string('Dose, e.g. 500 mg'),
          'frequency': AiParam.string('e.g. twice a day, 1-0-1'),
          'days': AiParam.integer('Number of days', min: 1, max: 365),
          'instructions': AiParam.string(
            'e.g. after food',
            required: false,
          ),
        }, 'One medicine'),
        'The medicines',
      ),
      'visitId': AiParam.string('Visit ID, if for a visit', required: false),
    },
    confirmText: (args) {
      final items = (args['items'] as List?) ?? const [];
      final lines = [
        for (final i in items)
          if (i is Map)
            '${i['drug']} ${i['dose']}, ${i['frequency']}, ${i['days']} days',
      ];
      return 'Save a draft prescription (not signed): ${lines.join('; ')}. '
          'You will review it before it is issued.';
    },
    run: (ctx, args) async {
      final patientId = args['patientId'] as String;
      final patient = await ctx
          .read(patientRepositoryProvider)
          .getPatient(patientId);
      if (patient == null) return AiToolResult.error('No such patient');
      final items = [
        for (final i in (args['items'] as List))
          if (i is Map) Map<String, Object?>.from(i),
      ];
      if (items.isEmpty) return AiToolResult.error('No medicines given');

      final medicines = [
        for (final i in items)
          NotedMedicine(
            name: '${i['drug']}',
            dosage: '${i['dose']}, ${i['frequency']}, ${i['days']} days',
            instructions: _s(i['instructions']) ?? '',
          ),
      ];
      final body = StringBuffer(
        'Draft prescription (not signed, prepared by the AI assistant). '
        'Review before issuing.',
      );
      for (final m in medicines) {
        body.write('\n- ${m.name} ${m.dosage}');
        if (m.instructions.isNotEmpty) body.write(' (${m.instructions})');
      }
      final saved = await ctx
          .read(consultationNoteRepositoryProvider)
          .saveSessionNote(
            ConsultationNote(
              id: _uuid.v4(),
              doctorId: '',
              patientId: patientId,
              visitId: _s(args['visitId']) ?? '',
              notes: body.toString(),
              medicines: medicines,
              createdAt: DateTime.now(),
            ),
          );
      return AiToolResult.ok(
        {
          'noteId': saved.id,
          'medicines': medicines.length,
          'issued': false,
          'status': 'draft saved in the patient\'s session notes; not signed',
        },
        summary:
            'Draft prescription saved for ${patient.fullName}; not signed',
      );
    },
  ),
  AiTool(
    name: 'get_homeopathy_case',
    description:
        'Reads a patient\'s homeopathy case sheet in short: chief problem, '
        'complaint, current remedy and potency, last follow-up.',
    group: AiToolGroup.clinical,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {'patientId': AiParam.string('Patient ID from find_patient')},
    run: (ctx, args) async {
      final sheet = await ctx
          .read(homeopathyRepositoryProvider)
          .getCaseSheetForPatient(args['patientId'] as String);
      if (sheet == null) {
        return AiToolResult.error('No homeopathy case sheet for this patient');
      }
      final o = sheet.overview;
      final c = sheet.chiefComplaint;
      final rx = sheet.prescriptionNotes;
      final f = sheet.followUp;
      Map<String, Object?> clean(Map<String, Object?> m) => {
        for (final e in m.entries)
          if (e.value != null && '${e.value}'.trim().isNotEmpty) e.key: e.value,
      };
      return AiToolResult.ok(
        clean({
          'caseSheetId': sheet.id,
          'completed': sheet.isCompleted,
          'caseDate': _dateStr(o.caseDate),
          'chiefProblem': _cut(o.chiefProblem.trim(), 300),
          'complaint': _cut(c.complaint.trim(), 300),
          'duration': c.duration.trim(),
          'remedy': rx.prescribedRemedy.trim(),
          'potency': rx.potency.trim(),
          'repetition': rx.repetitionScale.trim(),
          'lastResponse': f.responseRating.trim(),
          'nextPlan': f.nextPrescriptionPlan.trim(),
          'nextFollowUp': f.nextFollowUpDate == null
              ? null
              : _dateStr(f.nextFollowUpDate!),
          'additionalNotes': _cut(sheet.additionalNotes.trim(), 300),
        }),
      );
    },
  ),
  AiTool(
    name: 'add_homeopathy_session_note',
    description:
        'Adds a homeopathy session note for today: what the patient reports '
        '(text), and optionally the remedy and potency given.',
    group: AiToolGroup.clinical,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'patientId': AiParam.string('Patient ID from find_patient'),
      'text': AiParam.string('How the patient is today, in the doctor\'s words'),
      'remedy': AiParam.string('Remedy given', required: false),
      'potency': AiParam.string('Potency, e.g. 200C', required: false),
    },
    run: (ctx, args) async {
      final patientId = args['patientId'] as String;
      final patient = await ctx
          .read(patientRepositoryProvider)
          .getPatient(patientId);
      if (patient == null) return AiToolResult.error('No such patient');
      final now = DateTime.now();
      final repo = ctx.read(homeopathySessionNotesRepositoryProvider);
      final saved = await repo.saveSessionNote(
        HomeopathySessionNote(
          id: _uuid.v4(),
          patientId: patientId,
          doctorId: '',
          sessionDate: now,
          problemToday: (args['text'] as String).trim(),
          remedyGiven: _s(args['remedy']) ?? '',
          potency: _s(args['potency']) ?? '',
          createdAt: now,
        ),
      );
      return AiToolResult.ok(
        {'noteId': saved.id, 'patientId': patientId},
        summary: 'Homeopathy session note added for ${patient.fullName}',
        undo: () => repo.deleteSessionNote(saved.id),
      );
    },
  ),
];
