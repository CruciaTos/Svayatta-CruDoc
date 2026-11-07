import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/todos/data/todo.dart';
import 'package:doctor_management_app/features/todos/data/todo_format.dart';
import 'package:doctor_management_app/features/todos/data/todo_repository.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Open to-dos grouped for a list: Pinned (by [uid]), Overdue, Today,
/// Upcoming, No date. Each group by due time; undated ones newest first.
Map<String, List<Todo>> groupTodos(List<Todo> list, String uid, DateTime now) {
  final endOfToday = DateTime(now.year, now.month, now.day + 1);
  final g = <String, List<Todo>>{
    'Pinned': [],
    'Overdue': [],
    'Today': [],
    'Upcoming': [],
    'No date': [],
  };
  for (final t in list) {
    final due = t.dueAt;
    final key = t.pinnedFor(uid)
        ? 'Pinned'
        : due == null
        ? 'No date'
        : due.isBefore(now)
        ? 'Overdue'
        : due.isBefore(endOfToday)
        ? 'Today'
        : 'Upcoming';
    g[key]!.add(t);
  }
  int byDue(Todo a, Todo b) {
    if (a.dueAt == null || b.dueAt == null) {
      if (a.dueAt != b.dueAt) return a.dueAt == null ? 1 : -1;
      return (b.createdAt ?? DateTime(2100)).compareTo(
        a.createdAt ?? DateTime(2100),
      );
    }
    return a.dueAt!.compareTo(b.dueAt!);
  }

  for (final v in g.values) {
    v.sort(byDue);
  }
  return g;
}

/// The row's second line: due time, repeat, who from or for, note.
List<String> todoDetails(Todo t, String uid, DateTime now) => [
  if (t.done && t.doneAt != null)
    'Done ${todoWhen(t.doneAt!, now)}'
  else if (t.dueAt != null)
    '${t.overdue(now) ? 'Overdue · ' : ''}${todoWhen(t.dueAt!, now)}',
  if (t.repeat != TodoRepeat.none && !t.done) t.repeat.short,
  if (t.fromOther(uid) && t.createdByName.isNotEmpty) 'From ${t.createdByName}',
  if (t.delegatedBy(uid) && t.assignedToName.isNotEmpty)
    'For ${t.assignedToName}',
  if (t.note.isNotEmpty) t.note.split('\n').first,
];

/// Ticks [todo] off (or back on), with Undo, and says when a repeating
/// one comes back.
Future<void> toggleTodo(BuildContext context, WidgetRef ref, Todo todo) async {
  final repo = ref.read(todoRepositoryProvider);
  if (repo == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text, {VoidCallback? undo}) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        action: undo == null
            ? null
            : SnackBarAction(label: 'Undo', onPressed: undo),
      ),
    );
  try {
    if (todo.done) {
      await repo.reopen(todo);
      return;
    }
    await repo.complete(todo);
    if (todo.repeat != TodoRepeat.none && todo.dueAt != null) {
      var next = todo.repeat.next(todo.dueAt!);
      while (!next.isAfter(DateTime.now())) {
        next = todo.repeat.next(next);
      }
      say('Done. Next one ${todoWhen(next, DateTime.now())}');
    } else {
      say('Done', undo: () => repo.reopen(todo));
    }
  } catch (_) {
    say("Couldn't update the task. Try again.");
  }
}

/// The round tick box at the start of a to-do row. Green when done.
class TodoCheckCircle extends StatelessWidget {
  const TodoCheckCircle({
    super.key,
    required this.done,
    required this.label,
    required this.onTap,
  });

  final bool done;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: done ? c.greenTint : (hovered ? c.hoverFill : c.surface),
          shape: CircleBorder(
            side: BorderSide(
              color: done ? c.greenText : (hovered ? c.label3 : c.hairline),
              width: 1.5,
            ),
          ),
        ),
        child: done || hovered
            ? CruIcon(
                CruIcons.check,
                size: 14,
                strokeWidth: 2.2,
                color: done ? c.greenText : c.label3,
              )
            : null,
      ),
    );
  }
}
