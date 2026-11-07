import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/todos/data/todo.dart';
import 'package:doctor_management_app/features/todos/data/todo_format.dart';
import 'package:doctor_management_app/features/todos/data/todo_repository.dart';
import 'package:doctor_management_app/features/todos/presentation/todo_dialog.dart';
import 'package:doctor_management_app/features/todos/presentation/todo_icons.dart';
import 'package:doctor_management_app/features/todos/presentation/todo_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _View { mine, givenOut, done }

/// To-dos and reminders: bills, renewals, chores and jobs for colleagues.
/// Same page on the desktop sidebar and in the phone's More.
class TodosScreen extends ConsumerStatefulWidget {
  const TodosScreen({super.key});

  @override
  ConsumerState<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends ConsumerState<TodosScreen> {
  _View _view = _View.mine;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(clinicAccessProvider).value?.uid ?? '';
    final async = ref.watch(myTodosProvider);
    final all = async.value;
    final hasTeam = (ref.watch(clinicMembersProvider).value?.length ?? 0) > 1;
    final now = DateTime.now();

    final mine =
        all?.where((t) => !t.done && t.assignedTo == uid).toList() ??
        const <Todo>[];
    final givenOut =
        all?.where((t) => !t.done && t.delegatedBy(uid)).toList() ??
        const <Todo>[];
    final done = (all?.where((t) => t.done).toList() ?? <Todo>[])
      ..sort(
        (a, b) => (b.doneAt ?? DateTime(0)).compareTo(a.doneAt ?? DateTime(0)),
      );
    final showGiven = hasTeam || givenOut.isNotEmpty;
    final view = !showGiven && _view == _View.givenOut ? _View.mine : _view;
    final overdue = mine.where((t) => t.overdue(now)).length;

    final shown = switch (view) {
      _View.mine => mine,
      _View.givenOut => givenOut,
      _View.done => done.take(100).toList(),
    };
    final groups = view == _View.done
        ? {'Done': shown}
        : groupTodos(shown, uid, now);

    return Padding(
      padding: cruIsPhone(context)
          ? CruSpace.mainPaddingPhone
          : CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'To-do',
            subtitle: all == null
                ? 'Bills, renewals and jobs, with reminders'
                : mine.isEmpty
                ? 'Nothing on your list'
                : [
                    if (overdue > 0) '$overdue overdue',
                    DashFormat.plural(mine.length, 'open task'),
                  ].join(' · '),
            actions: [
              CruButton(
                label: 'New task',
                icon: CruIcons.plus,
                onPressed: () => showTodoDialog(context),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          DentalFilterBar(
            filters: [
              CruSegmentedControl<_View>(
                semanticLabel: 'Show',
                segments: [
                  const CruSegment(_View.mine, 'Mine'),
                  if (showGiven) const CruSegment(_View.givenOut, 'Given out'),
                  const CruSegment(_View.done, 'Done'),
                ],
                selected: view,
                onChanged: (v) => setState(() => _view = v),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: all == null
                ? (async.hasError
                      ? Center(
                          child: DentalEmptyState(
                            icon: TodoIcons.check,
                            title: "Couldn't load your tasks",
                            body:
                                'Check your connection. They come back on their own.',
                          ),
                        )
                      : const SkeletonCard(rows: 4, rowHeight: 56))
                : CruCard(
                    semanticLabel: 'Tasks',
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: shown.isEmpty
                        ? Center(
                            child: SingleChildScrollView(
                              child: _empty(context, view),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final e in groups.entries)
                                if (e.value.isNotEmpty) ...[
                                  DentalGroupLabel(
                                    e.key,
                                    trailing: '${e.value.length}',
                                  ),
                                  for (var i = 0; i < e.value.length; i++) ...[
                                    if (i > 0)
                                      const CruSeparator(indent: 12 + 24 + 12),
                                    _TodoRow(
                                      todo: e.value[i],
                                      uid: uid,
                                      now: now,
                                    ),
                                  ],
                                ],
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, _View view) => switch (view) {
    _View.mine => DentalEmptyState(
      icon: TodoIcons.check,
      title: 'Nothing to do',
      body:
          'Add bills to pay, renewals and jobs. Give a date to get a '
          'reminder, even when CruDoc is closed.',
      actions: [
        CruButton(
          label: 'New task',
          icon: CruIcons.plus,
          onPressed: () => showTodoDialog(context),
        ),
      ],
    ),
    _View.givenOut => const DentalEmptyState(
      icon: TodoIcons.check,
      title: 'Nothing given out',
      body: 'Tasks you assign to colleagues show here until they finish them.',
    ),
    _View.done => const DentalEmptyState(
      icon: TodoIcons.check,
      title: 'Nothing done yet',
      body: 'Finished tasks show here.',
    ),
  };
}

class _TodoRow extends ConsumerWidget {
  const _TodoRow({required this.todo, required this.uid, required this.now});

  final Todo todo;
  final String uid;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final t = todo;
    final pinned = t.pinnedFor(uid);
    final overdue = t.overdue(now);
    final who = t.fromOther(uid)
        ? (t.createdByName.isEmpty ? null : 'From ${t.createdByName}')
        : t.delegatedBy(uid)
        ? (t.assignedToName.isEmpty ? null : 'For ${t.assignedToName}')
        : null;
    final subStyle = CruType.subhead.tint(c.label2);
    final bits = <InlineSpan>[
      if (t.done && t.doneAt != null)
        TextSpan(text: 'Done ${todoWhen(t.doneAt!, now)}')
      else if (t.dueAt != null)
        TextSpan(
          text: todoWhen(t.dueAt!, now),
          style: overdue ? subStyle.tint(c.amberText) : null,
        ),
      if (t.repeat != TodoRepeat.none && !t.done)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CruIcon(TodoIcons.repeat, size: 14, color: c.label3),
              const SizedBox(width: CruSpace.s4),
              Text(t.repeat.short, style: subStyle),
            ],
          ),
        ),
      if (who != null) TextSpan(text: who),
      if (t.note.isNotEmpty) TextSpan(text: t.note.split('\n').first),
    ];
    final sub = <InlineSpan>[];
    for (var i = 0; i < bits.length; i++) {
      if (i > 0) sub.add(const TextSpan(text: ' · '));
      sub.add(bits[i]);
    }

    return DentalListRow(
      semanticLabel:
          '${t.title}${t.done
              ? ', done'
              : overdue
              ? ', overdue'
              : ''}',
      onTap: () => showTodoDialog(context, existing: t),
      child: Row(
        children: [
          TodoCheckCircle(
            done: t.done,
            label: t.done ? 'Mark ${t.title} not done' : 'Mark ${t.title} done',
            onTap: () => toggleTodo(context, ref, t),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.done
                      ? CruType.callout
                            .tint(c.label3)
                            .copyWith(decoration: TextDecoration.lineThrough)
                      : CruType.callout.tint(c.label),
                ),
                if (sub.isNotEmpty)
                  Text.rich(
                    TextSpan(children: sub, style: subStyle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (!t.done) ...[
            const SizedBox(width: CruSpace.s8),
            CruIconButton(
              icon: pinned ? TodoIcons.pinFilled : TodoIcons.pin,
              iconSize: 18,
              semanticLabel: pinned ? 'Unpin' : 'Pin to the top',
              tooltip: pinned ? 'Unpin' : 'Pin to the top',
              onPressed: () =>
                  ref.read(todoRepositoryProvider)?.setPinned(t, !pinned),
            ),
          ],
        ],
      ),
    );
  }
}
