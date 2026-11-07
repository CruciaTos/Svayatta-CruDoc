import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/todos/data/todo.dart';

CollectionReference<Map<String, dynamic>> _todos(String clinicId) =>
    FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .collection('todos');

/// Saves, completes, pins and deletes to-dos in the active clinic.
class TodoRepository {
  TodoRepository(this.clinicId, this.uid);

  final String clinicId;
  final String uid;

  String newId() => _todos(clinicId).doc().id;

  Future<void> save(Todo t, {bool isNew = false}) {
    final data = {
      ...t.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      if (isNew) 'pinnedBy': t.pinnedBy,
    };
    return _todos(clinicId).doc(t.id).set(data, SetOptions(merge: true));
  }

  /// Ticks it off. A repeating one moves to its next due time instead
  /// (skipping any it already missed), so it stays on the list.
  Future<void> complete(Todo t) {
    final now = DateTime.now();
    if (t.repeat != TodoRepeat.none && t.dueAt != null) {
      var next = t.repeat.next(t.dueAt!);
      while (!next.isAfter(now)) {
        next = t.repeat.next(next);
      }
      return _todos(clinicId).doc(t.id).update({
        'dueAt': Timestamp.fromDate(next),
        'lastDoneAt': Timestamp.fromDate(now),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return _todos(clinicId).doc(t.id).update({
      'done': true,
      'doneAt': Timestamp.fromDate(now),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reopen(Todo t) => _todos(clinicId).doc(t.id).update({
    'done': false,
    'doneAt': null,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> setPinned(Todo t, bool pinned) =>
      _todos(clinicId).doc(t.id).update({
        'pinnedBy': pinned
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> delete(Todo t) => _todos(clinicId).doc(t.id).delete();
}

final todoRepositoryProvider = Provider<TodoRepository?>((ref) {
  final a = ref.watch(clinicAccessProvider).value;
  if (a == null) return null;
  return TodoRepository(a.clinicId, a.uid);
});

/// Every to-do this person made or was given, newest first. Two queries
/// (made by me, assigned to me) merged, because the rules only let each
/// person read their own.
final myTodosProvider = StreamProvider<List<Todo>>((ref) {
  final a = ref.watch(clinicAccessProvider).value;
  if (a == null) return Stream.value(const []);
  final col = _todos(a.clinicId);
  final mine = col.where('createdBy', isEqualTo: a.uid).snapshots();
  final given = col.where('assignedTo', isEqualTo: a.uid).snapshots();

  final out = StreamController<List<Todo>>();
  Map<String, Todo>? made;
  Map<String, Todo>? got;
  void emit() {
    if (made == null || got == null) return;
    final all = {...made!, ...got!}.values.toList()
      ..sort(
        (x, y) => (y.createdAt ?? DateTime(2100)).compareTo(
          x.createdAt ?? DateTime(2100),
        ),
      );
    out.add(all);
  }

  Map<String, Todo> read(QuerySnapshot<Map<String, dynamic>> s) => {
    for (final d in s.docs) d.id: Todo.fromMap(d.id, d.data()),
  };
  final subs = [
    mine.listen((s) {
      made = read(s);
      emit();
    }, onError: out.addError),
    given.listen((s) {
      got = read(s);
      emit();
    }, onError: out.addError),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    out.close();
  });
  return out.stream;
});
