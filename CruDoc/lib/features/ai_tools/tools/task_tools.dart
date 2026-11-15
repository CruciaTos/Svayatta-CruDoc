import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/todos/data/todo.dart';
import 'package:doctor_management_app/features/todos/data/todo_repository.dart';

import '../core/ai_tool.dart';

const _maxItems = 15;

String? _str(Map<String, Object?> a, String k) {
  final v = a[k];
  return v is String && v.trim().isNotEmpty ? v.trim() : null;
}

/// `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM`, or null.
DateTime? _parseDue(String? s) {
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  // A bare date means end of that working day, so it isn't overdue at once.
  return s.length <= 10 ? DateTime(d.year, d.month, d.day, 9) : d;
}

Map<String, Object?> _row(Todo t, String uid) => {
  'id': t.id,
  'text': t.title,
  if (t.note.isNotEmpty) 'note': t.note,
  if (t.dueAt != null) 'due': t.dueAt!.toIso8601String(),
  'done': t.done,
  if (t.overdue(DateTime.now())) 'overdue': true,
  'pinned': t.pinnedFor(uid),
  if (t.repeat != TodoRepeat.none) 'repeats': t.repeat.name,
};

List<AiTool> taskTools() => [
  AiTool(
    name: 'list_todos',
    description:
        "List the signed-in person's to-dos (made by them or given to them), "
        'open ones first, pinned then soonest due. Use to find a to-do id.',
    group: AiToolGroup.tasks,
    risk: AiToolRisk.read,
    params: const {
      'includeDone': AiParam.boolean(
        'Also list finished to-dos (default false).',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final uid = ctx.access?.uid ?? '';
      final all = await ctx.read(myTodosProvider.future);
      final includeDone = args['includeDone'] == true;
      final list = all.where((t) => includeDone || !t.done).toList()
        ..sort((a, b) {
          if (a.done != b.done) return a.done ? 1 : -1;
          final pa = a.pinnedFor(uid), pb = b.pinnedFor(uid);
          if (pa != pb) return pa ? -1 : 1;
          final da = a.dueAt ?? DateTime(2100);
          final db = b.dueAt ?? DateTime(2100);
          return da.compareTo(db);
        });
      return AiToolResult.ok({
        'count': list.length,
        'todos': [for (final t in list.take(_maxItems)) _row(t, uid)],
        if (list.length > _maxItems) 'truncated': true,
      });
    },
  ),
  AiTool(
    name: 'add_todo',
    description:
        'Add a to-do or reminder for the signed-in person (not a patient '
        'record). Optionally link a patient (use find_patient first).',
    group: AiToolGroup.tasks,
    risk: AiToolRisk.write,
    params: const {
      'text': AiParam.string('What needs doing.'),
      'due': AiParam.string(
        'When it is due: YYYY-MM-DD or YYYY-MM-DDTHH:MM (24-hour).',
        required: false,
      ),
      'patientId': AiParam.string(
        'Patient this relates to, from find_patient.',
        required: false,
      ),
      'pinned': AiParam.boolean('Pin it to the top.', required: false),
    },
    run: (ctx, args) async {
      final repo = ctx.read(todoRepositoryProvider);
      final uid = ctx.access?.uid;
      if (repo == null || uid == null) {
        return AiToolResult.error('The clinic is not loaded yet. Try again.');
      }
      final text = _str(args, 'text');
      if (text == null) return AiToolResult.error('Say what the to-do is.');
      final dueRaw = _str(args, 'due');
      final due = _parseDue(dueRaw);
      if (dueRaw != null && due == null) {
        return AiToolResult.error('Could not read the due date "$dueRaw".');
      }

      var note = '';
      final patientId = _str(args, 'patientId');
      if (patientId != null) {
        final patients = ctx.read(patientsStreamProvider).value ?? const [];
        for (final p in patients) {
          if (p.id == patientId) note = 'Patient: ${p.fullName.trim()}';
        }
        if (note.isEmpty) {
          return AiToolResult.error('No patient with that id.');
        }
      }

      final members = ctx.read(clinicMembersProvider).value ?? const [];
      var name = '';
      for (final m in members) {
        if (m.uid == uid) name = m.name;
      }

      final todo = Todo(
        id: repo.newId(),
        title: text,
        note: note,
        createdBy: uid,
        createdByName: name,
        assignedTo: uid,
        assignedToName: name,
        dueAt: due,
        remind: due == null ? TodoRemind.none : TodoRemind.atTime,
      );
      await repo.save(todo, isNew: true);
      if (args['pinned'] == true) await repo.setPinned(todo, true);
      return AiToolResult.ok(
        {'id': todo.id, 'text': text, if (due != null) 'due': due.toIso8601String()},
        summary: 'Added to-do "$text"',
        undo: () => repo.delete(todo),
      );
    },
  ),
  AiTool(
    name: 'complete_todo',
    description:
        'Tick off a to-do by id (from list_todos). A repeating to-do moves '
        'to its next due date instead.',
    group: AiToolGroup.tasks,
    risk: AiToolRisk.write,
    params: const {'todoId': AiParam.string('To-do id from list_todos.')},
    run: (ctx, args) async {
      final repo = ctx.read(todoRepositoryProvider);
      if (repo == null) {
        return AiToolResult.error('The clinic is not loaded yet. Try again.');
      }
      final id = _str(args, 'todoId');
      final all = await ctx.read(myTodosProvider.future);
      Todo? todo;
      for (final t in all) {
        if (t.id == id) todo = t;
      }
      if (todo == null) return AiToolResult.error('No to-do with that id.');
      if (todo.done) return AiToolResult.error('That to-do is already done.');
      final t = todo;
      await repo.complete(t);
      final repeats = t.repeat != TodoRepeat.none && t.dueAt != null;
      return AiToolResult.ok(
        {'id': t.id, 'text': t.title, if (repeats) 'repeats': t.repeat.name},
        summary: 'Done: "${t.title}"',
        // Reopen restores done/doneAt; for a repeating one, put the due
        // date back as well.
        undo: () async {
          if (repeats) {
            await repo.save(t);
          } else {
            await repo.reopen(t);
          }
        },
      );
    },
  ),
];
