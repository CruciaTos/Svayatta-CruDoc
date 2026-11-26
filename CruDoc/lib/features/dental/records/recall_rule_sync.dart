import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';

/// Turns the clinic's recall rules into real recall records, so the server's
/// daily recall sweep (which reads `dental_records` of kind "recall") reaches
/// patients whose recall comes from a rule, not only from a hand-set date.
///
/// One record per patient and rule, id `<patientId>_<ruleId>`, data
/// `source: 'rule'`. A newer qualifying procedure moves its due date forward
/// (and reopens it); a completed visit on/after (due - 14 days) marks it
/// done. A hand-set open recall for the same rule or reason is left alone.
class RecallRuleSync {
  RecallRuleSync._();

  static const _backfillKey = 'crudoc.recallRuleBackfill.v1.';
  static const _grace = Duration(days: 14);
  static bool _running = false;
  static bool _again = false;

  /// One idempotent pass over existing procedures, once per clinic per
  /// version. Call after sync has started, on the clinic device.
  static Future<void> backfillOnce(String doctorId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_backfillKey$doctorId';
      if (prefs.getBool(key) ?? false) return;
      final ok = await _runAndCheck(doctorId);
      if (ok) await prefs.setBool(key, true);
    } catch (e) {
      debugPrint('Recall rule backfill failed: $e');
    }
  }

  static Future<bool> _runAndCheck(String doctorId) async {
    if (_running) {
      _again = true;
      return false;
    }
    _running = true;
    try {
      await _run(doctorId, null);
      return true;
    } catch (e) {
      debugPrint('Recall rule sync failed: $e');
      return false;
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        await run(doctorId);
      }
    }
  }

  /// Re-evaluates the rules for [patientId], or the whole clinic when null.
  /// Returns false when there were no rules yet (nothing was evaluated).
  static Future<bool> run(String doctorId, {String? patientId}) async {
    if (_running) {
      _again = true;
      return false;
    }
    _running = true;
    try {
      return await _run(doctorId, patientId);
    } catch (e) {
      debugPrint('Recall rule sync failed: $e');
      return false;
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        await run(doctorId, patientId: patientId);
      }
    }
  }

  static Future<bool> _run(String doctorId, String? patientId) async {
    final repo = DentalRecordsRepository();
    final now = DateTime.now();
    final procedures = await repo.completedProcedures(
      doctorId,
      now.subtract(const Duration(days: 730)),
      patientId: patientId,
    ); // newest first
    // Only clinics with completed dental procedures get default dental recall
    // rules; non-dental clinics must never have dental rules seeded.
    if (procedures.isEmpty) return false;

    final rules = await ensureRecallRules(repo, doctorId);
    if (rules.isEmpty) return false;

    final recalls = [
      for (final r in await repo.all(doctorId, RecKind.recall))
        if (patientId == null || r.patientId == patientId) r,
    ];
    final byId = {for (final r in recalls) r.id: r};

    // Newest qualifying procedure per patient + rule.
    final latest =
        <String, ({String patientId, RecallRule rule, DateTime due})>{};
    for (final p in procedures) {
      if (p.patientId.isEmpty) continue;
      for (final rule in rules) {
        if (!rule.matches(p.name)) continue;
        latest.putIfAbsent(
          '${p.patientId}_${rule.record.id}',
          () => (
            patientId: p.patientId,
            rule: rule,
            due: DateTime(p.at.year, p.at.month + rule.months, p.at.day),
          ),
        );
      }
    }
    if (latest.isEmpty) return true;

    final db = await LocalDatabaseService.instance.localDatabase;
    final visitRows = await db.query(
      'visits',
      columns: ['patientId', 'scheduledStart'],
      where: "doctorId = ? AND isDeleted = 0 AND status = 'completed'",
      whereArgs: [doctorId],
    );
    final lastVisit = <String, int>{};
    for (final v in visitRows) {
      final id = v['patientId'] as String? ?? '';
      final t = (v['scheduledStart'] as int?) ?? 0;
      if (t > (lastVisit[id] ?? 0)) lastVisit[id] = t;
    }
    final names = <String, String>{};
    Future<String> nameOf(String id) async {
      final cached = names[id];
      if (cached != null) return cached;
      final rows = await db.query(
        'patients',
        columns: ['firstName', 'lastName'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final n = rows.isEmpty
          ? ''
          : '${rows.first['firstName']} ${rows.first['lastName']}'.trim();
      return names[id] = n;
    }

    final out = <DentalRecord>[];
    for (final entry in latest.entries) {
      final s = entry.value;
      final id = entry.key;
      final visit = lastVisit[s.patientId];
      final visited =
          visit != null &&
          visit >= s.due.subtract(_grace).millisecondsSinceEpoch;
      final existing = byId[id];

      if (existing != null) {
        final open = recallStatusOf(existing).isOpen;
        if (visited && open && existing.str('source') == 'rule') {
          out.add(
            existing.copyWith(
              data: {...existing.data, 'status': RecallStatus.done.name},
            ),
          );
        } else if (!visited && s.due.isAfter(existing.recordedAt)) {
          // A newer procedure: a new cycle, due later.
          out.add(
            existing.copyWith(
              data: {...existing.data, 'status': RecallStatus.pending.name},
              recordedAt: s.due,
            ),
          );
        }
        continue;
      }

      if (visited) continue;
      if (s.due.isBefore(now.subtract(_grace))) continue; // left for the clinic
      final reason = s.rule.name;
      final manual = recalls.any(
        (r) =>
            r.patientId == s.patientId &&
            recallStatusOf(r).isOpen &&
            (r.str('ruleId') == s.rule.record.id ||
                r.str('reason').toLowerCase() == reason.toLowerCase()),
      );
      if (manual) continue;
      final at = DateTime.now();
      out.add(
        DentalRecord(
          id: id,
          patientId: s.patientId,
          kind: RecKind.recall,
          data: {
            'patientName': await nameOf(s.patientId),
            'reason': reason,
            'ruleId': s.rule.record.id,
            'notes': '',
            'status': RecallStatus.pending.name,
            'source': 'rule',
          },
          recordedAt: s.due,
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
    await repo.saveMany(doctorId, out);
    return true;
  }
}
