import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/todos/data/todo.dart';
import 'package:doctor_management_app/features/todos/data/todo_format.dart';
import 'package:doctor_management_app/features/todos/data/todo_repository.dart';
import 'package:doctor_management_app/features/todos/presentation/todo_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Adds a to-do, or edits [existing]. True when something was saved.
Future<bool> showTodoDialog(BuildContext context, {Todo? existing}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _TodoDialog(existing: existing),
  );
  return saved == true;
}

/// Someone a to-do can be assigned to.
class _Person {
  const _Person(this.uid, this.name);
  final String uid;
  final String name;
}

class _TodoDialog extends ConsumerStatefulWidget {
  const _TodoDialog({this.existing});

  final Todo? existing;

  @override
  ConsumerState<_TodoDialog> createState() => _TodoDialogState();
}

class _TodoDialogState extends ConsumerState<_TodoDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _note;
  DateTime? _due;
  late TodoRemind _remind;
  late TodoRepeat _repeat;
  late String _assignee;
  late bool _pinned;
  bool _saving = false;
  bool _dirty = false;
  bool _submitted = false;
  String? _notice;

  String get _uid => ref.read(clinicAccessProvider).value?.uid ?? '';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _due = e?.dueAt;
    _remind = e?.remind ?? TodoRemind.atTime;
    _repeat = e?.repeat ?? TodoRepeat.none;
    _assignee = e?.assignedTo ?? _uid;
    _pinned = e?.pinnedFor(_uid) ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// Me first, then the clinic's other active members.
  List<_Person> _people(List<ClinicMember> members) {
    final me = members.where((m) => m.uid == _uid).firstOrNull;
    final myName = me?.name.trim().isNotEmpty == true
        ? me!.name.trim()
        : (ref.read(doctorIdentityProvider).fullName ?? '').trim();
    return [
      _Person(_uid, myName),
      for (final m in members)
        if (m.uid != _uid && m.active) _Person(m.uid, m.name.trim()),
    ];
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final start = _due ?? DateTime(now.year, now.month, now.day, 9);
    final d = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d == null) return;
    setState(
      () => _due = DateTime(d.year, d.month, d.day, start.hour, start.minute),
    );
    _edited();
  }

  Future<void> _pickTime() async {
    final due = _due;
    if (due == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(due),
    );
    if (t == null) return;
    setState(
      () => _due = DateTime(due.year, due.month, due.day, t.hour, t.minute),
    );
    _edited();
  }

  Future<void> _save(List<_Person> people) async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    final repo = ref.read(todoRepositoryProvider);
    if (repo == null) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    String nameOf(String uid) =>
        people.where((p) => p.uid == uid).firstOrNull?.name ?? '';
    final e = widget.existing;
    final todo = Todo(
      id: e?.id ?? repo.newId(),
      title: _title.text.trim(),
      note: _note.text.trim(),
      createdBy: e?.createdBy ?? _uid,
      createdByName: e?.createdByName ?? nameOf(_uid),
      assignedTo: _assignee,
      assignedToName: nameOf(_assignee),
      dueAt: _due,
      remind: _due == null ? TodoRemind.none : _remind,
      repeat: _due == null ? TodoRepeat.none : _repeat,
      done: e?.done ?? false,
      doneAt: e?.doneAt,
      pinnedBy: _pinned ? [_uid] : const [],
    );
    try {
      await repo.save(todo, isNew: e == null);
      if (e != null && e.pinnedFor(_uid) != _pinned) {
        await repo.setPinned(todo, _pinned);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() {
        _saving = false;
        _notice =
            "Couldn't save the task. Check your connection and try again.";
      });
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    final repo = ref.read(todoRepositoryProvider);
    if (e == null || repo == null) return;
    final ok = await confirmDental(
      context,
      title: 'Delete this task?',
      body: '"${e.title}" will be removed for everyone it was shared with.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    await repo.delete(e);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(clinicMembersProvider).value ?? const [];
    final people = _people(members);
    final e = widget.existing;
    final due = _due;
    final now = DateTime.now();
    return CruFormDialog(
      title: e == null ? 'New task' : 'Task',
      subtitle: due == null
          ? 'A to-do or reminder'
          : 'Due ${todoWhen(due, now)}',
      leading: const CruIconTile(
        icon: TodoIcons.check,
        tone: CruTileTone.accent,
      ),
      submitLabel: e == null ? 'Add task' : 'Save changes',
      onSubmit: () => _save(people),
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: Form(
        key: _form,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Task',
              description: 'What needs doing.',
              children: [
                CruTextField(
                  label: 'Title',
                  controller: _title,
                  hint: 'Pay the Wi-Fi bill',
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Say what needs doing.';
                    if (t.length > 200) return 'Keep it under 200 characters.';
                    return null;
                  },
                  onChanged: (_) => _edited(),
                ),
                CruTextField(
                  label: 'Note',
                  optional: true,
                  controller: _note,
                  maxLines: 3,
                  hint: 'Account number, amount, who to call',
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => (v ?? '').length > 2000
                      ? 'Keep the note under 2000 characters.'
                      : null,
                  onChanged: (_) => _edited(),
                ),
                if (people.length > 1)
                  CruDropdownField<_Person>(
                    label: 'Assign to',
                    icon: CruIcons.user,
                    value: people.where((p) => p.uid == _assignee).firstOrNull,
                    items: people,
                    itemLabel: (p) => p.uid == _uid
                        ? 'Me${p.name.isEmpty ? '' : ' (${p.name})'}'
                        : (p.name.isEmpty ? 'Colleague' : p.name),
                    onChanged: (p) {
                      setState(() => _assignee = p.uid);
                      _edited();
                    },
                  ),
              ],
            ),
            CruFormSection(
              title: 'When',
              description: due == null
                  ? 'Add a date to get a reminder.'
                  : 'You get a notification on this device, even when CruDoc is closed.',
              children: [
                CruFieldRow(
                  children: [
                    CruPickerField(
                      label: 'Date',
                      icon: CruIcons.calendar,
                      value: due == null ? null : DentalFormat.date(due),
                      placeholder: 'No date',
                      onTap: _pickDate,
                    ),
                    if (due != null)
                      CruPickerField(
                        label: 'Time',
                        icon: CruIcons.clock,
                        value: DentalFormat.time(due),
                        placeholder: 'Pick a time',
                        onTap: _pickTime,
                      ),
                  ],
                ),
                if (due != null) ...[
                  CruFieldRow(
                    children: [
                      CruDropdownField<TodoRemind>(
                        label: 'Remind me',
                        value: _remind,
                        items: TodoRemind.values,
                        itemLabel: (r) => r.label,
                        onChanged: (r) {
                          setState(() => _remind = r);
                          _edited();
                        },
                      ),
                      CruDropdownField<TodoRepeat>(
                        label: 'Repeat',
                        value: _repeat,
                        items: TodoRepeat.values,
                        itemLabel: (r) => r.label,
                        onChanged: (r) {
                          setState(() => _repeat = r);
                          _edited();
                        },
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruLink(
                      label: 'Remove date',
                      onPressed: () {
                        setState(() => _due = null);
                        _edited();
                      },
                    ),
                  ),
                ],
              ],
            ),
            CruFormSection(
              title: 'Pin',
              children: [
                CruSwitchRow(
                  title: 'Pin to the top',
                  subtitle:
                      'Only for you. Pinned tasks stay first in your list.',
                  value: _pinned,
                  onChanged: (v) {
                    setState(() => _pinned = v);
                    _edited();
                  },
                ),
                if (e != null && e.createdBy == _uid)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruLink(
                      label: 'Delete this task',
                      onPressed: _delete,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
