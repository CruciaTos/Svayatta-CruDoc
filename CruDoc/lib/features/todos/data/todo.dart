import 'package:cloud_firestore/cloud_firestore.dart';

/// How often a to-do comes back once it's done (a monthly Wi-Fi bill).
enum TodoRepeat {
  none('Does not repeat', ''),
  daily('Every day', 'Daily'),
  weekly('Every week', 'Weekly'),
  monthly('Every month', 'Monthly'),
  yearly('Every year', 'Yearly');

  const TodoRepeat(this.label, this.short);

  final String label;
  final String short;

  static TodoRepeat fromName(Object? v) => TodoRepeat.values.firstWhere(
    (r) => r.name == v,
    orElse: () => TodoRepeat.none,
  );

  /// The next due time after [from]. Month ends clamp (31 Jan → 28 Feb).
  DateTime next(DateTime from) {
    DateTime addMonths(int n) {
      final m = from.month - 1 + n;
      final y = from.year + m ~/ 12;
      final month = m % 12 + 1;
      final lastDay = DateTime(y, month + 1, 0).day;
      return DateTime(
        y,
        month,
        from.day > lastDay ? lastDay : from.day,
        from.hour,
        from.minute,
      );
    }

    return switch (this) {
      none => from,
      daily => DateTime(
        from.year,
        from.month,
        from.day + 1,
        from.hour,
        from.minute,
      ),
      weekly => DateTime(
        from.year,
        from.month,
        from.day + 7,
        from.hour,
        from.minute,
      ),
      monthly => addMonths(1),
      yearly => addMonths(12),
    };
  }
}

/// When the reminder fires, relative to the due time.
enum TodoRemind {
  none('No reminder', null),
  atTime('At the due time', Duration.zero),
  min15('15 minutes before', Duration(minutes: 15)),
  hour1('1 hour before', Duration(hours: 1)),
  day1('1 day before', Duration(days: 1));

  const TodoRemind(this.label, this.before);

  final String label;
  final Duration? before;

  static TodoRemind fromName(Object? v) => TodoRemind.values.firstWhere(
    (r) => r.name == v,
    orElse: () => TodoRemind.atTime,
  );
}

/// A to-do or reminder: "Pay the router's Wi-Fi bill", "Order gloves".
/// Lives at `clinics/{clinicId}/todos/{id}`, seen only by the person who
/// made it and the person it's assigned to (often the same person).
class Todo {
  const Todo({
    required this.id,
    required this.title,
    this.note = '',
    required this.createdBy,
    this.createdByName = '',
    required this.assignedTo,
    this.assignedToName = '',
    this.dueAt,
    this.remind = TodoRemind.atTime,
    this.repeat = TodoRepeat.none,
    this.done = false,
    this.doneAt,
    this.pinnedBy = const [],
    this.createdAt,
  });

  final String id;
  final String title;
  final String note;
  final String createdBy;
  final String createdByName;
  final String assignedTo;
  final String assignedToName;
  final DateTime? dueAt;
  final TodoRemind remind;
  final TodoRepeat repeat;
  final bool done;
  final DateTime? doneAt;

  /// Who pinned it: pins are per person, so a colleague's pin doesn't
  /// move it in your list.
  final List<String> pinnedBy;
  final DateTime? createdAt;

  bool pinnedFor(String uid) => pinnedBy.contains(uid);

  /// Assigned by someone else to [uid].
  bool fromOther(String uid) => assignedTo == uid && createdBy != uid;

  /// [uid] assigned it to someone else.
  bool delegatedBy(String uid) => createdBy == uid && assignedTo != uid;

  bool overdue(DateTime now) => !done && dueAt != null && dueAt!.isBefore(now);

  /// When the reminder should fire, or null for none.
  DateTime? get remindAt {
    final before = remind.before;
    if (done || dueAt == null || before == null) return null;
    return dueAt!.subtract(before);
  }

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

  factory Todo.fromMap(String id, Map<String, dynamic> m) => Todo(
    id: id,
    title: (m['title'] as String?) ?? '',
    note: (m['note'] as String?) ?? '',
    createdBy: (m['createdBy'] as String?) ?? '',
    createdByName: (m['createdByName'] as String?) ?? '',
    assignedTo: (m['assignedTo'] as String?) ?? '',
    assignedToName: (m['assignedToName'] as String?) ?? '',
    dueAt: _date(m['dueAt']),
    remind: TodoRemind.fromName(m['remind']),
    repeat: TodoRepeat.fromName(m['repeat']),
    done: m['done'] == true,
    doneAt: _date(m['doneAt']),
    pinnedBy: [
      for (final p in (m['pinnedBy'] as List?) ?? const [])
        if (p is String) p,
    ],
    createdAt: _date(m['createdAt']),
  );

  /// The fields a save writes (not createdAt or pins, set on their own).
  Map<String, dynamic> toMap() => {
    'title': title,
    'note': note,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'assignedTo': assignedTo,
    'assignedToName': assignedToName,
    'dueAt': dueAt == null ? null : Timestamp.fromDate(dueAt!),
    'remind': remind.name,
    'repeat': repeat.name,
    'done': done,
    'doneAt': doneAt == null ? null : Timestamp.fromDate(doneAt!),
  };
}
