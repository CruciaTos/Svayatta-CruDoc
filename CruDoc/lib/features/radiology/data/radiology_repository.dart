import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_seed.dart';

/// Kinds of document in `radiology_docs`.
abstract final class RadKind {
  static const study = 'study';
  static const referrer = 'referrer';
  static const report = 'report';
  static const template = 'template';
  static const phrase = 'phrase';
  static const fee = 'fee';
  static const audit = 'audit';
  static const pacs = 'pacs';
  static const settings = 'settings';
  static const meta = 'meta';
}

/// Local-only store for the radiology module. Records are JSON documents
/// in the encrypted local database; image files live in the app's support
/// folder under `radiology/<doctor>/<study>/`.
class RadiologyRepository {
  RadiologyRepository({LocalDatabaseService? db})
      : _db = db ?? LocalDatabaseService.instance;

  final LocalDatabaseService _db;
  static const _table = 'radiology_docs';

  // ───────────────────────── Generic documents ─────────────────────────

  Future<List<Map<String, dynamic>>> _all(String doctorId, String kind) async {
    final db = await _db.localDatabase;
    final rows = await db.query(
      _table,
      where: 'doctorId = ? AND kind = ? AND isDeleted = 0',
      whereArgs: [doctorId, kind],
      orderBy: 'updatedAt DESC',
    );
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      try {
        final d = jsonDecode(r['data'] as String? ?? '{}');
        if (d is Map) out.add(Map<String, dynamic>.from(d));
      } catch (_) {
        // A damaged record is skipped rather than breaking the list.
      }
    }
    return out;
  }

  Future<Map<String, dynamic>?> _one(String id) async {
    final db = await _db.localDatabase;
    final rows = await db.query(_table,
        where: 'id = ? AND isDeleted = 0', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final d = jsonDecode(rows.first['data'] as String? ?? '{}');
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  Future<void> _put(
    String doctorId,
    String kind,
    String id,
    Map<String, dynamic> data, {
    String patientId = '',
  }) async {
    final db = await _db.localDatabase;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      _table,
      {
        'id': id,
        'doctorId': doctorId,
        'kind': kind,
        'patientId': patientId,
        'data': jsonEncode(data),
        'isDeleted': 0,
        'createdAt': (data['createdAt'] as int?) ?? now,
        'updatedAt': now,
      },
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
  }

  Future<void> _delete(String id) async {
    final db = await _db.localDatabase;
    await db.update(
      _table,
      {'isDeleted': 1, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Built-in templates, phrases and fees go in once per doctor, so they
  /// can be edited like the doctor's own.
  Future<void> _seedOnce(String doctorId) async {
    final id = 'seed_v1_$doctorId';
    if (await _one(id) != null) return;
    for (final ph in RadSeed.phrases()) {
      await _put(doctorId, RadKind.phrase, ph.id, ph.toJson());
    }
    for (final f in RadSeed.fees()) {
      await _put(doctorId, RadKind.fee, f.id, f.toJson());
    }
    await _put(doctorId, RadKind.meta, id, {'seededAt': DateTime.now().millisecondsSinceEpoch});
  }

  // ───────────────────────────── Studies ─────────────────────────────

  Future<List<RadStudy>> studies(String doctorId) async =>
      (await _all(doctorId, RadKind.study)).map(RadStudy.fromJson).toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  Future<RadStudy?> study(String id) async {
    final d = await _one(id);
    return d == null ? null : RadStudy.fromJson(d);
  }

  Future<void> saveStudy(String doctorId, RadStudy s) =>
      _put(doctorId, RadKind.study, s.id, s.toJson(), patientId: s.patientId);

  /// Removes the study and its files.
  Future<void> deleteStudy(String doctorId, String id) async {
    await _delete(id);
    final dir = await studyDir(doctorId, id);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  // ─────────────────────────── Study files ───────────────────────────

  Future<Directory> root(String doctorId) async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'radiology', doctorId));
  }

  Future<Directory> studyDir(String doctorId, String studyId) async =>
      Directory(p.join((await root(doctorId)).path, studyId));

  Future<File> fileOf(String doctorId, String studyId, String relativePath) async =>
      File(p.join((await studyDir(doctorId, studyId)).path, relativePath));

  /// Bytes on disk for all studies (Storage in Settings).
  Future<int> storageBytes(String doctorId) async {
    final dir = await root(doctorId);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  // ───────────────────────────── Referrers ─────────────────────────────

  Future<List<RadReferrer>> referrers(String doctorId) async =>
      (await _all(doctorId, RadKind.referrer)).map(RadReferrer.fromJson).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<void> saveReferrer(String doctorId, RadReferrer r) =>
      _put(doctorId, RadKind.referrer, r.id, r.toJson());

  Future<void> deleteReferrer(String id) => _delete(id);

  // ───────────────────────────── Reports ─────────────────────────────

  Future<List<RadReport>> reports(String doctorId) async =>
      (await _all(doctorId, RadKind.report)).map(RadReport.fromJson).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> saveReport(String doctorId, RadReport r) =>
      _put(doctorId, RadKind.report, r.id, r.toJson(), patientId: r.patientId);

  Future<void> deleteReport(String id) => _delete(id);

  // ──────────────────────── Templates and phrases ────────────────────────

  /// Built-in templates first (or the doctor's edited copy of one), then
  /// the doctor's own.
  Future<List<RadTemplate>> templates(String doctorId) async {
    final own = (await _all(doctorId, RadKind.template)).map(RadTemplate.fromJson).toList();
    final byId = {for (final t in own) t.id: t};
    return [
      for (final t in RadSeed.templates()) byId.remove(t.id) ?? t,
      ...byId.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
    ];
  }

  Future<void> saveTemplate(String doctorId, RadTemplate t) =>
      _put(doctorId, RadKind.template, t.id, t.toJson());

  Future<void> deleteTemplate(String id) => _delete(id);

  Future<List<RadPhrase>> phrases(String doctorId) async {
    await _seedOnce(doctorId);
    return (await _all(doctorId, RadKind.phrase)).map(RadPhrase.fromJson).toList()
      ..sort((a, b) => a.trigger.compareTo(b.trigger));
  }

  Future<void> savePhrase(String doctorId, RadPhrase ph) =>
      _put(doctorId, RadKind.phrase, ph.id, ph.toJson());

  Future<void> deletePhrase(String id) => _delete(id);

  // ─────────────────────────────── Fees ───────────────────────────────

  Future<List<RadFee>> fees(String doctorId) async {
    await _seedOnce(doctorId);
    final list = (await _all(doctorId, RadKind.fee)).map(RadFee.fromJson).toList();
    list.sort((a, b) => a.modality.index != b.modality.index
        ? a.modality.index.compareTo(b.modality.index)
        : a.label.compareTo(b.label));
    return list;
  }

  Future<void> saveFee(String doctorId, RadFee f) =>
      _put(doctorId, RadKind.fee, f.id, f.toJson());

  Future<void> deleteFee(String id) => _delete(id);

  // ─────────────────────────────── Audit ───────────────────────────────

  Future<List<RadAuditEvent>> audit(String doctorId) async =>
      (await _all(doctorId, RadKind.audit)).map(RadAuditEvent.fromJson).toList()
        ..sort((a, b) => b.at.compareTo(a.at));

  Future<void> addAudit(String doctorId, RadAuditEvent e) =>
      _put(doctorId, RadKind.audit, e.id, e.toJson());

  // ───────────────────────────── PACS ─────────────────────────────

  Future<List<RadPacsServer>> pacsServers(String doctorId) async =>
      (await _all(doctorId, RadKind.pacs)).map(RadPacsServer.fromJson).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  Future<void> savePacsServer(String doctorId, RadPacsServer s) =>
      _put(doctorId, RadKind.pacs, s.id, s.toJson());

  Future<void> deletePacsServer(String id) => _delete(id);

  // ───────────────────────────── Settings ─────────────────────────────

  Future<RadSettings> settings(String doctorId) async {
    final d = await _one('settings_$doctorId');
    return d == null ? const RadSettings() : RadSettings.fromJson(d);
  }

  Future<void> saveSettings(String doctorId, RadSettings s) =>
      _put(doctorId, RadKind.settings, 'settings_$doctorId', s.toJson());
}
