import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_cloud_fetch.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:crudoc_j2k/crudoc_j2k.dart';
import 'package:doctor_management_app/features/radiology/data/rad_progressive_flag.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_view_fetch.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_view_pixels.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_repository.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';

const _uuid = Uuid();

/// A new record id.
String radId([String prefix = '']) => '$prefix${_uuid.v4()}';

final radiologyRepositoryProvider = Provider<RadiologyRepository>(
  (ref) => RadiologyRepository(),
);

/// Whose radiology records these are: the signed-in doctor (the demo
/// account when nobody is signed in, like the dental screens).
final radDoctorIdProvider = Provider<String>((ref) {
  final user = ref.watch(authStateProvider).value;
  final clinicId = ref.watch(clinicAccessProvider).value?.clinicId;
  return clinicId ?? user?.uid ?? 'doc_omr';
});

final radDocsVersionProvider = StreamProvider<int>((ref) async* {
  yield 0;
  int version = 0;
  await for (final _ in RadiologyRepository.changes) {
    yield ++version;
  }
});

final radStudiesProvider = FutureProvider<List<RadStudy>>((ref) {
  ref.watch(radDocsVersionProvider);
  final id = ref.watch(radDoctorIdProvider);
  return ref.watch(radiologyRepositoryProvider).studies(id);
});

/// One study, read fresh (the viewer and report editor use it).
final radStudyProvider = FutureProvider.family<RadStudy?, String>((ref, id) {
  ref.watch(radStudiesProvider);
  return ref.watch(radiologyRepositoryProvider).study(id);
});

final radReferrersProvider = FutureProvider<List<RadReferrer>>((ref) {
  ref.watch(radDocsVersionProvider);
  final id = ref.watch(radDoctorIdProvider);
  return ref.watch(radiologyRepositoryProvider).referrers(id);
});

final radReportsProvider = FutureProvider<List<RadReport>>((ref) {
  ref.watch(radDocsVersionProvider);
  final id = ref.watch(radDoctorIdProvider);
  return ref.watch(radiologyRepositoryProvider).reports(id);
});

/// The report for a study, if one was started.
final radReportForStudyProvider = Provider.family<RadReport?, String>((
  ref,
  studyId,
) {
  final reports = ref.watch(radReportsProvider).value ?? const <RadReport>[];
  for (final r in reports) {
    if (r.studyId == studyId) return r;
  }
  return null;
});

final radTemplatesProvider = FutureProvider<List<RadTemplate>>((ref) {
  ref.watch(radDocsVersionProvider);
  final id = ref.watch(radDoctorIdProvider);
  return ref.watch(radiologyRepositoryProvider).templates(id);
});

final radPhrasesProvider = FutureProvider<List<RadPhrase>>((ref) {
  ref.watch(radDocsVersionProvider);
  final id = ref.watch(radDoctorIdProvider);
  return ref.watch(radiologyRepositoryProvider).phrases(id);
});

final radFeesProvider = FutureProvider<List<RadFee>>((ref) {
  ref.watch(radDocsVersionProvider);
  final id = ref.watch(radDoctorIdProvider);
  return ref.watch(radiologyRepositoryProvider).fees(id);
});

final radAuditProvider = FutureProvider<List<RadAuditEvent>>((ref) {
  ref.watch(radDocsVersionProvider);
  final id = ref.watch(radDoctorIdProvider);
  return ref.watch(radiologyRepositoryProvider).audit(id);
});

final radPacsServersProvider = FutureProvider<List<RadPacsServer>>((ref) {
  ref.watch(radDocsVersionProvider);
  final id = ref.watch(radDoctorIdProvider);
  return ref.watch(radiologyRepositoryProvider).pacsServers(id);
});

final radSettingsProvider = FutureProvider<RadSettings>((ref) {
  ref.watch(radDocsVersionProvider);
  final id = ref.watch(radDoctorIdProvider);
  return ref.watch(radiologyRepositoryProvider).settings(id);
});

/// Referrers by id, for rows that show who sent a study.
final radReferrerByIdProvider = Provider<Map<String, RadReferrer>>((ref) {
  final list = ref.watch(radReferrersProvider).value ?? const <RadReferrer>[];
  return {for (final r in list) r.id: r};
});

final radiologyProvider = Provider<RadiologyController>(
  RadiologyController.new,
);

/// Every change to radiology records goes through here: it saves, writes
/// the audit trail and refreshes the lists that show the record.
class RadiologyController {
  RadiologyController(this._ref);

  final Ref _ref;

  RadiologyRepository get _repo => _ref.read(radiologyRepositoryProvider);
  String get doctorId => _ref.read(radDoctorIdProvider);
  String get _me => _ref.read(doctorIdentityProvider).fullName ?? '';

  // ───────────────────────────── Audit ─────────────────────────────

  Future<void> log(
    String action, {
    String targetKind = '',
    String targetId = '',
    String detail = '',
  }) async {
    await _repo.addAudit(
      doctorId,
      RadAuditEvent(
        id: radId('aud_'),
        at: DateTime.now(),
        action: action,
        targetKind: targetKind,
        targetId: targetId,
        detail: detail,
        by: _me,
      ),
    );
    _ref.invalidate(radAuditProvider);
  }

  // ───────────────────────────── Studies ─────────────────────────────

  Future<void> saveStudy(
    RadStudy s, {
    String? auditAction,
    String detail = '',
  }) async {
    await _repo.saveStudy(doctorId, s);
    _ref.invalidate(radStudiesProvider);
    if (auditAction != null) {
      await log(
        auditAction,
        targetKind: 'study',
        targetId: s.id,
        detail: detail,
      );
    }
  }

  Future<void> deleteStudy(RadStudy s) async {
    await _repo.deleteStudy(doctorId, s.id);
    final report = _ref.read(radReportForStudyProvider(s.id));
    if (report != null) await _repo.deleteReport(report.id);
    _ref.invalidate(radStudiesProvider);
    _ref.invalidate(radReportsProvider);
    await log(
      'Deleted study',
      targetKind: 'study',
      targetId: s.id,
      detail: s.patientName,
    );
  }

  /// Marks a new study as being read when it's opened.
  Future<void> openedStudy(RadStudy s) async {
    if (s.status == RadStudyStatus.newStudy) {
      await _repo.saveStudy(
        doctorId,
        s.copyWith(status: RadStudyStatus.reading),
      );
      _ref.invalidate(radStudiesProvider);
    }
    await log(
      'Opened',
      targetKind: 'study',
      targetId: s.id,
      detail: s.patientName,
    );
  }

  Future<Directory> studyDir(String studyId) =>
      _repo.studyDir(doctorId, studyId);

  /// The local file at [relativePath] in [s]. When it isn't on this
  /// computer (the study was imported on another device) but was uploaded,
  /// it is downloaded into the study folder first, once.
  Future<File> fileOf(RadStudy s, String relativePath) async {
    final file = await _repo.fileOf(doctorId, s.id, relativePath);
    if (kIsWeb || await file.exists()) return file;
    final image = s.images.where((i) => i.path == relativePath).firstOrNull;
    if (image == null || image.storagePath.isEmpty) return file;
    return RadCloudFetch.instance.fetch(image.storagePath, file);
  }

  /// Pixels for [image]. Uses the progressive viewing file when possible
  /// (see handoff Design), otherwise the original as before.
  Future<RadPixels> pixelsOf(
    RadStudy s,
    RadImageRef image,
    int frame, {
    required bool full,
  }) async {
    Future<RadPixels> oldPath() async {
      return loadRadPixels(
        await fileOf(s, image.path),
        image.kind,
        frame: frame,
      );
    }

    if (kIsWeb ||
        !j2kSupported ||
        image.storagePath.isEmpty ||
        image.kind != RadFileKind.dicom) {
      return oldPath();
    }

    final localOriginal = await _repo.fileOf(doctorId, s.id, image.path);
    if (await localOriginal.exists()) {
      return oldPath();
    }

    if (!(await radProgressiveViewEnabled())) {
      return oldPath();
    }

    try {
      final info = await RadViewFetch.instance.info(image.storagePath);
      if (info == null || !info.ready) {
        return oldPath();
      }

      final dir = await studyDir(s.id);
      final file = await RadViewFetch.instance.ensure(
        studyDir: dir,
        imageId: image.id,
        storagePath: image.storagePath,
        frame: frame,
        full: full,
      );

      return await loadRadViewPixels(
        file,
        info,
        frame: frame,
        full: full,
        pixelSpacingMm: image.pixelSpacingMm,
      );
    } catch (e) {
      debugPrint(
        '[rad] Progressive view failed (${e.runtimeType}), falling back to original',
      );
      return oldPath();
    }
  }

  /// What to draw [image]'s thumbnail from: the original when it's on this
  /// computer, otherwise its small cloud preview (downloaded once), and only
  /// failing that the original from the cloud.
  Future<(File, RadFileKind)> thumbSourceOf(
    RadStudy s,
    RadImageRef image,
  ) async {
    final original = await _repo.fileOf(doctorId, s.id, image.path);
    if (kIsWeb || await original.exists() || image.previewPath.isEmpty) {
      return (await fileOf(s, image.path), image.kind);
    }
    final dir = await _repo.studyDir(doctorId, s.id);
    final preview = File(p.join(dir.path, '.previews', '${image.id}.jpg'));
    return (
      await RadCloudFetch.instance.fetch(image.previewPath, preview),
      RadFileKind.raster,
    );
  }

  Future<int> storageBytes() => _repo.storageBytes(doctorId);

  /// When a study of [priority] received at [receivedAt] is due.
  Future<DateTime> dueFor(RadPriority priority, DateTime receivedAt) async {
    final settings = await _ref.read(radSettingsProvider.future);
    return receivedAt.add(settings.turnaround(priority));
  }

  // ───────────────────────────── Referrers ─────────────────────────────

  Future<void> saveReferrer(RadReferrer r, {bool isNew = false}) async {
    await _repo.saveReferrer(doctorId, r);
    _ref.invalidate(radReferrersProvider);
    await log(
      isNew ? 'Added referrer' : 'Edited referrer',
      targetKind: 'referrer',
      targetId: r.id,
      detail: r.name,
    );
  }

  Future<void> deleteReferrer(RadReferrer r) async {
    await _repo.deleteReferrer(r.id);
    _ref.invalidate(radReferrersProvider);
    await log(
      'Deleted referrer',
      targetKind: 'referrer',
      targetId: r.id,
      detail: r.name,
    );
  }

  // ───────────────────────────── Reports ─────────────────────────────

  /// Saves the report and moves its study along the workflow.
  Future<void> saveReport(RadReport r, {String? auditAction}) async {
    await _repo.saveReport(doctorId, r);
    final study = await _repo.study(r.studyId);
    if (study != null) {
      final next = switch (r.status) {
        RadReportStatus.draft => RadStudyStatus.draft,
        RadReportStatus.preliminary => RadStudyStatus.preliminary,
        RadReportStatus.finalised =>
          r.sharedAt != null
              ? RadStudyStatus.delivered
              : RadStudyStatus.finalised,
      };
      if (next != study.status) {
        await _repo.saveStudy(doctorId, study.copyWith(status: next));
        _ref.invalidate(radStudiesProvider);
      }
    }
    _ref.invalidate(radReportsProvider);
    if (auditAction != null) {
      await log(
        auditAction,
        targetKind: 'report',
        targetId: r.id,
        detail: r.title,
      );
    }
  }

  Future<void> deleteReport(RadReport r) async {
    await _repo.deleteReport(r.id);
    _ref.invalidate(radReportsProvider);
    await log(
      'Deleted report',
      targetKind: 'report',
      targetId: r.id,
      detail: r.title,
    );
  }

  // ──────────────────────── Templates, phrases, fees ────────────────────────

  Future<void> saveTemplate(RadTemplate t) async {
    await _repo.saveTemplate(doctorId, t);
    _ref.invalidate(radTemplatesProvider);
  }

  Future<void> deleteTemplate(RadTemplate t) async {
    await _repo.deleteTemplate(t.id);
    _ref.invalidate(radTemplatesProvider);
  }

  Future<void> savePhrase(RadPhrase ph) async {
    await _repo.savePhrase(doctorId, ph);
    _ref.invalidate(radPhrasesProvider);
  }

  Future<void> deletePhrase(RadPhrase ph) async {
    await _repo.deletePhrase(ph.id);
    _ref.invalidate(radPhrasesProvider);
  }

  Future<void> saveFee(RadFee f) async {
    await _repo.saveFee(doctorId, f);
    _ref.invalidate(radFeesProvider);
  }

  Future<void> deleteFee(RadFee f) async {
    await _repo.deleteFee(f.id);
    _ref.invalidate(radFeesProvider);
  }

  /// The fee for a study type: the first fee listed for it.
  Future<double?> feeFor(RadModality m) async {
    final fees = await _ref.read(radFeesProvider.future);
    for (final f in fees) {
      if (f.modality == m) return f.amount;
    }
    return null;
  }

  // ───────────────────────────── PACS and settings ─────────────────────────────

  Future<void> savePacsServer(RadPacsServer s) async {
    await _repo.savePacsServer(doctorId, s);
    _ref.invalidate(radPacsServersProvider);
  }

  Future<void> deletePacsServer(RadPacsServer s) async {
    await _repo.deletePacsServer(s.id);
    _ref.invalidate(radPacsServersProvider);
  }

  Future<void> saveSettings(RadSettings s) async {
    await _repo.saveSettings(doctorId, s);
    _ref.invalidate(radSettingsProvider);
  }

  /// Merges [values] into the viewer preferences (the viewer's own keys).
  Future<void> saveViewerPrefs(Map<String, dynamic> values) async {
    final s = await _ref.read(radSettingsProvider.future);
    await saveSettings(s.copyWith(viewer: {...s.viewer, ...values}));
  }
}
