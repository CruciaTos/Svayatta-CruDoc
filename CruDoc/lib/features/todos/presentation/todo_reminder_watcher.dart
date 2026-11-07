import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/push_notifications.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/todos/data/todo.dart';
import 'package:doctor_management_app/features/todos/data/todo_format.dart';
import 'package:doctor_management_app/features/todos/data/todo_repository.dart';

/// Keeps this device's to-do reminders in step with the list: schedules
/// an OS notification for each open to-do assigned to this person (they
/// fire even when the app is closed) and cancels the rest. Also says when
/// a colleague gives this person a task; phones get that as a push from
/// the server (onTodoAssigned) when the app is closed.
class TodoReminderWatcher extends ConsumerStatefulWidget {
  const TodoReminderWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TodoReminderWatcher> createState() =>
      _TodoReminderWatcherState();
}

class _TodoReminderWatcherState extends ConsumerState<TodoReminderWatcher>
    with WidgetsBindingObserver {
  bool _foreground = true;
  bool _busy = false;
  List<Todo>? _pending;

  static bool get _phone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushNotifications.instance.setRoute('todo', _open);
    ref.listenManual(myTodosProvider, (_, next) {
      final list = next.value;
      if (list != null) _sync(list);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushNotifications.instance.clearRoute('todo', _open);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  void _open(Map<String, dynamic> data) {
    if (!mounted) return;
    final shell = ref.read(shellNavigatorProvider);
    if (shell != null && shell(DesktopTab.todos)) return;
    // The phone's Tasks tab leads with what's due.
    ref.read(mobileTabSwitcherProvider)?.call(MobileTab.tasks);
  }

  /// One sync at a time; a newer list waits and replaces any older one.
  Future<void> _sync(List<Todo> list) async {
    _pending = list;
    if (_busy) return;
    _busy = true;
    try {
      while (_pending != null) {
        final next = _pending!;
        _pending = null;
        await _apply(next);
      }
    } catch (e) {
      debugPrint('[TodoReminderWatcher] $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _apply(List<Todo> list) async {
    final uid = ref.read(clinicAccessProvider).value?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final push = PushNotifications.instance;
    final now = DateTime.now();

    // Reminders: todoId -> what was scheduled, so unchanged ones are left.
    final schedKey = 'todos.scheduled.$uid';
    final before = <String, String>{};
    try {
      final raw = prefs.getString(schedKey);
      if (raw != null) {
        before.addAll(Map<String, String>.from(jsonDecode(raw) as Map));
      }
    } catch (_) {}
    final after = <String, String>{};
    for (final t in list) {
      final at = t.remindAt;
      if (t.assignedTo != uid || at == null || !at.isAfter(now)) continue;
      final sig = '${at.millisecondsSinceEpoch}|${t.title}';
      after[t.id] = sig;
      if (before[t.id] == sig) continue;
      final from = t.fromOther(uid) && t.createdByName.isNotEmpty
          ? 'From ${t.createdByName} · '
          : '';
      await push.schedule(
        id: todoNotificationId(t.id),
        title: t.title,
        body: '${from}Due ${todoWhen(t.dueAt!, at)}',
        when: at,
        data: {'type': 'todo', 'id': t.id},
      );
    }
    for (final id in before.keys) {
      if (!after.containsKey(id)) await push.cancel(todoNotificationId(id));
    }
    await prefs.setString(schedKey, jsonEncode(after));

    // New tasks from colleagues. First run on this device: history only.
    final seenKey = 'todos.seen.$uid';
    final fresh = !prefs.containsKey(seenKey);
    final seen = (prefs.getStringList(seenKey) ?? const []).toSet();
    var changed = false;
    for (final t in list) {
      if (!t.fromOther(uid) || t.done || !seen.add(t.id)) continue;
      changed = true;
      // A closed or background phone gets the server's push instead.
      if (fresh || (_phone && !_foreground)) continue;
      await push.show(
        id: todoAssignedNotificationId(t.id),
        title:
            'New task from ${t.createdByName.isEmpty ? 'a colleague' : t.createdByName}',
        body: t.dueAt == null
            ? t.title
            : '${t.title} · due ${todoWhen(t.dueAt!, now)}',
        data: {'type': 'todo', 'id': t.id},
      );
    }
    if (changed || fresh) await prefs.setStringList(seenKey, seen.toList());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
