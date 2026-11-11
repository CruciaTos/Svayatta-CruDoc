import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/todos/data/todo.dart';
import 'package:doctor_management_app/features/todos/data/todo_repository.dart';
import 'package:doctor_management_app/features/todos/presentation/todo_dialog.dart';
import 'package:doctor_management_app/features/todos/presentation/todo_icons.dart';
import 'package:doctor_management_app/features/todos/presentation/todo_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A to-do as a phone row: tick, title, details, pin.
class MobileTodoRow extends ConsumerWidget {
  const MobileTodoRow({
    super.key,
    required this.todo,
    required this.uid,
    required this.now,
  });

  final Todo todo;
  final String uid;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final t = todo;
    final pinned = t.pinnedFor(uid);
    final details = todoDetails(t, uid, now);
    return MobileRow(
      leading: SizedBox(
        width: 36,
        child: Center(
          child: TodoCheckCircle(
            done: t.done,
            label: t.done ? 'Mark ${t.title} not done' : 'Mark ${t.title} done',
            onTap: () => toggleTodo(context, ref, t),
          ),
        ),
      ),
      title: t.title,
      titleStyle: t.done
          ? MobileType.row
                .tint(c.label3)
                .copyWith(decoration: TextDecoration.lineThrough)
          : null,
      subtitle: details.isEmpty ? null : details.join(' · '),
      trailing: t.done
          ? null
          : CruIconButton(
              icon: pinned ? TodoIcons.pinFilled : TodoIcons.pin,
              iconSize: 18,
              semanticLabel: pinned ? 'Unpin' : 'Pin to the top',
              onPressed: () =>
                  ref.read(todoRepositoryProvider)?.setPinned(t, !pinned),
            ),
      onTap: () => showTodoDialog(mobileRoot(context), existing: t),
    );
  }
}

enum _View { mine, givenOut, done }

/// The To-do source on the phone's Tasks tab: your list, the ones you
/// gave colleagues, and what's done.
class MobileTodoPage extends ConsumerStatefulWidget {
  const MobileTodoPage({super.key});

  @override
  ConsumerState<MobileTodoPage> createState() => _MobileTodoPageState();
}

class _MobileTodoPageState extends ConsumerState<MobileTodoPage> {
  _View _view = _View.mine;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(clinicAccessProvider).value?.uid ?? '';
    final all = ref.watch(myTodosProvider).value;
    final hasTeam = (ref.watch(clinicMembersProvider).value?.length ?? 0) > 1;
    final now = DateTime.now();
    if (all == null) {
      return const MobileRowGroup(
        children: [MobileLoading('Loading your to-dos…', height: 120)],
      );
    }
    final mine = all.where((t) => !t.done && t.assignedTo == uid).toList();
    final givenOut = all.where((t) => !t.done && t.delegatedBy(uid)).toList();
    final done = all.where((t) => t.done).toList()
      ..sort(
        (a, b) => (b.doneAt ?? DateTime(0)).compareTo(a.doneAt ?? DateTime(0)),
      );
    final views = [
      _View.mine,
      if (hasTeam || givenOut.isNotEmpty) _View.givenOut,
      _View.done,
    ];
    final view = views.contains(_view) ? _view : _View.mine;
    final shown = switch (view) {
      _View.mine => mine,
      _View.givenOut => givenOut,
      _View.done => done.take(100).toList(),
    };
    final groups = view == _View.done
        ? {'Done': shown}
        : groupTodos(shown, uid, now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
          child: MobileSegmented<_View>(
            values: views,
            label: (v) => switch (v) {
              _View.mine => 'Mine',
              _View.givenOut => 'Given out',
              _View.done => 'Done',
            },
            selected: view,
            onChanged: (v) => setState(() => _view = v),
          ),
        ),
        const SizedBox(height: CruSpace.s16),
        if (shown.isEmpty)
          switch (view) {
            _View.mine => MobileEmpty(
              icon: TodoIcons.check,
              title: 'Nothing to do',
              body:
                  'Add bills to pay, renewals and jobs. Give a date to get a '
                  'reminder, even when CruDoc is closed.',
              action: 'New task',
              onAction: () => showTodoDialog(mobileRoot(context)),
            ),
            _View.givenOut => const MobileEmpty(
              icon: TodoIcons.check,
              title: 'Nothing given out',
              body:
                  'Tasks you assign to colleagues show here until they '
                  'finish them.',
            ),
            _View.done => const MobileEmpty(
              icon: TodoIcons.check,
              title: 'Nothing done yet',
              body: 'Finished tasks show here.',
            ),
          }
        else
          for (final e in groups.entries)
            if (e.value.isNotEmpty) ...[
              MobileRowGroup(
                title: e.key,
                children: [
                  for (final t in e.value)
                    MobileTodoRow(todo: t, uid: uid, now: now),
                ],
              ),
              const SizedBox(height: CruSpace.s12),
            ],
      ],
    );
  }
}

/// On the All page: the first five open to-dos you made or were given
/// (pinned, overdue, today, upcoming, no date), above the clinical tasks.
/// None open: nothing shown.
class MobileTodoDueGroup extends ConsumerWidget {
  const MobileTodoDueGroup({super.key, required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(clinicAccessProvider).value?.uid ?? '';
    final all = ref.watch(myTodosProvider).value ?? const <Todo>[];
    final now = DateTime.now();
    final g = groupTodos(
      all
          .where((t) => !t.done && (t.assignedTo == uid || t.createdBy == uid))
          .toList(),
      uid,
      now,
    );
    final due = [for (final l in g.values) ...l];
    if (due.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s16),
      child: MobileRowGroup(
        title: 'To-do',
        action: 'See all',
        onAction: onSeeAll,
        children: [
          for (final t in due.take(5))
            MobileTodoRow(todo: t, uid: uid, now: now),
        ],
      ),
    );
  }
}
