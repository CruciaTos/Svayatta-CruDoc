import 'package:intl/intl.dart';

/// "Today 5:30 PM", "Tomorrow 9:00 AM", "Yesterday", "Mon 12 Nov 9:00 AM".
String todoWhen(DateTime d, DateTime now) {
  final a = DateTime(d.year, d.month, d.day);
  final b = DateTime(now.year, now.month, now.day);
  final diff = a.difference(b).inDays;
  final time = DateFormat('h:mm a').format(d);
  final day = switch (diff) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => DateFormat(a.year == b.year ? 'EEE d MMM' : 'd MMM yyyy').format(d),
  };
  return '$day $time';
}

/// A stable notification id for a to-do (31-bit FNV-1a of its id, kept
/// in its own range so it never replaces another kind of notification).
int todoNotificationId(String todoId) {
  var h = 0x811c9dc5;
  for (final c in todoId.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return 0x40000000 | (h & 0x3fffffff);
}

/// Same id space, for "you were given a task" (shown once).
int todoAssignedNotificationId(String todoId) =>
    todoNotificationId('assigned:$todoId');
