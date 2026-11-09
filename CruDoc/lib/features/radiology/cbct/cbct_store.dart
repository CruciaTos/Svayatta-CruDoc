import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_device.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_pack.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_repository.dart';

enum CbctPackState { missing, packing, ready, failed }

@immutable
class CbctStatus {
  const CbctStatus({
    required this.state,
    this.progress = 0,
    this.stage = '',
    this.failure,
    this.packDir,
    this.meta,
  });

  const CbctStatus.missing() : this(state: CbctPackState.missing);

  final CbctPackState state;

  /// 0..1 while packing.
  final double progress;
  final String stage;
  final String? failure;
  final Directory? packDir;
  final Map<String, dynamic>? meta;
}

typedef CbctPackFn =
    Future<CbctPack> Function(
      RadStudy study,
      Directory studyDir,
      void Function(String stage, double progress) onProgress,
    );
typedef CbctPlanFn = CbctPlan Function(RadStudy study, Directory studyDir);
typedef CbctReadyFn = Future<Map<String, dynamic>?> Function(String dir, String fingerprint);

/// Packs CBCT studies for the 3D viewer in the background, one at a time
/// app-wide, and tells the screen where each stands.
class CbctStore {
  CbctStore({
    CbctPackFn? pack,
    CbctPlanFn? plan,
    CbctReadyFn? readReady,
    Future<Directory> Function(RadStudy study)? studyDirOf,
    Future<String> Function()? appVersion,
    bool Function()? platformSupported,
  }) : _pack = pack ?? _defaultPack,
       _plan = plan ?? planCbctPack,
       _readReady = readReady ?? readReadyCbctMeta,
       _studyDirOf = studyDirOf ?? _defaultStudyDir,
       _appVersion = appVersion ?? _defaultAppVersion,
       _supported = platformSupported ?? (() => CbctDevice.platformSupported);

  static final CbctStore instance = CbctStore();

  /// Used when the app version can't be read.
  static const _fallbackVersion = 'unknown';

  final CbctPackFn _pack;
  final CbctPlanFn _plan;
  final CbctReadyFn _readReady;
  final Future<Directory> Function(RadStudy) _studyDirOf;
  final Future<String> Function() _appVersion;
  final bool Function() _supported;

  final Map<String, CbctStatus> _status = {};
  final Map<String, StreamController<CbctStatus>> _controllers = {};
  final Queue<RadStudy> _queue = Queue();
  final Set<String> _queued = {};
  bool _running = false;

  static Future<CbctPack> _defaultPack(
    RadStudy study,
    Directory dir,
    void Function(String, double) onProgress,
  ) => ensureCbctPack(study: study, studyDir: dir, onProgress: onProgress);

  static Future<Directory> _defaultStudyDir(RadStudy study) async {
    final doctorId = ClinicSession.instance.tenantId ?? 'doc_omr';
    return RadiologyRepository().studyDir(doctorId, study.id);
  }

  static Future<String> _defaultAppVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } on Object {
      return _fallbackVersion;
    }
  }

  /// The last known status; [refresh] reads the disk.
  CbctStatus statusOf(RadStudy study) => _status[study.id] ?? const CbctStatus.missing();

  void _set(String id, CbctStatus s) {
    _status[id] = s;
    _controllers[id]?.add(s);
  }

  /// Reads the pack folder: ready only for a current pack made from these
  /// files, failed when this app version already failed on them.
  Future<CbctStatus> refresh(RadStudy study) async {
    final current = _status[study.id];
    if (current?.state == CbctPackState.packing) return current!;
    CbctStatus s;
    try {
      final dir = await _studyDirOf(study);
      final plan = _plan(study, dir);
      final meta = await _readReady(plan.dir, plan.fingerprint);
      if (meta != null) {
        s = CbctStatus(
          state: CbctPackState.ready,
          progress: 1,
          packDir: Directory(plan.dir),
          meta: meta,
        );
      } else {
        final failure = await _readFailure(plan.dir);
        s = failure != null
            ? CbctStatus(
                state: CbctPackState.failed,
                failure: failure,
                packDir: Directory(plan.dir),
              )
            : CbctStatus(state: CbctPackState.missing, packDir: Directory(plan.dir));
      }
    } on CbctPackException catch (e) {
      s = CbctStatus(state: CbctPackState.failed, failure: e.message);
    } on Object {
      s = const CbctStatus.missing();
    }
    _set(study.id, s);
    return s;
  }

  Future<String?> _readFailure(String packDir) async {
    final f = File(p.join(packDir, 'failed.json'));
    try {
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['appVersion'] == await _appVersion()) return '${j['reason']}';
    } on Object {
      // Unreadable: treat as no failure.
    }
    return null;
  }

  Future<void> _writeFailure(String packDir, String reason) async {
    try {
      final d = Directory(packDir);
      await d.create(recursive: true);
      await File(p.join(packDir, 'failed.json')).writeAsString(
        jsonEncode({'reason': reason, 'appVersion': await _appVersion()}),
      );
    } on Object {
      // Best effort.
    }
  }

  Stream<CbctStatus> watch(RadStudy study) {
    final c = _controllers.putIfAbsent(
      study.id,
      () => StreamController<CbctStatus>.broadcast(),
    );
    late StreamController<CbctStatus> out;
    StreamSubscription<CbctStatus>? sub;
    out = StreamController<CbctStatus>(
      onListen: () {
        sub = c.stream.listen(out.add);
        final known = _status[study.id];
        if (known != null) {
          out.add(known);
        }
        if (known == null || known.state == CbctPackState.missing) {
          unawaited(refresh(study));
        }
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// Queues [study] to be packed; [priority] moves it to the front. Does
  /// nothing when the platform can't open 3D, or the pack is ready or
  /// packing. Never throws.
  void enqueue(RadStudy study, {bool priority = false}) {
    if (!_supported() || !study.modality.isVolume) return;
    final state = _status[study.id]?.state;
    if (state == CbctPackState.packing && !_queued.contains(study.id)) return;
    if (_queued.contains(study.id)) {
      if (priority) {
        _queue.removeWhere((s) => s.id == study.id);
        _queue.addFirst(study);
      }
      return;
    }
    _queued.add(study.id);
    if (priority) {
      _queue.addFirst(study);
    } else {
      _queue.addLast(study);
    }
    if (state != CbctPackState.ready) {
      _set(
        study.id,
        CbctStatus(
          state: CbctPackState.packing,
          stage: 'Waiting',
          packDir: _status[study.id]?.packDir,
        ),
      );
    }
    unawaited(_pump());
  }

  /// Resolves when the queue is empty (tests).
  Future<void> get idle async {
    while (_running || _queue.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final study = _queue.removeFirst();
        _queued.remove(study.id);
        await _packOne(study);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _packOne(RadStudy study) async {
    String? packDir;
    try {
      final dir = await _studyDirOf(study);
      final plan = _plan(study, dir);
      packDir = plan.dir;
      final ready = await _readReady(plan.dir, plan.fingerprint);
      if (ready != null) {
        _set(
          study.id,
          CbctStatus(
            state: CbctPackState.ready,
            progress: 1,
            packDir: Directory(plan.dir),
            meta: ready,
          ),
        );
        return;
      }
      if (await _readFailure(plan.dir) != null && !_retryFailed.remove(study.id)) {
        _set(
          study.id,
          CbctStatus(
            state: CbctPackState.failed,
            failure: await _readFailure(plan.dir),
            packDir: Directory(plan.dir),
          ),
        );
        return;
      }
      _set(
        study.id,
        CbctStatus(
          state: CbctPackState.packing,
          stage: 'Starting',
          packDir: Directory(plan.dir),
        ),
      );
      final pack = await _pack(study, dir, (stage, progress) {
        _set(
          study.id,
          CbctStatus(
            state: CbctPackState.packing,
            progress: progress,
            stage: stage,
            packDir: Directory(plan.dir),
          ),
        );
      });
      try {
        await File(p.join(pack.dir.path, 'failed.json')).delete();
      } on Object {
        // None to remove.
      }
      _set(
        study.id,
        CbctStatus(
          state: CbctPackState.ready,
          progress: 1,
          packDir: pack.dir,
          meta: pack.meta,
        ),
      );
    } on CbctPackException catch (e) {
      if (packDir != null) await _writeFailure(packDir, e.message);
      _set(
        study.id,
        CbctStatus(
          state: CbctPackState.failed,
          failure: e.message,
          packDir: packDir == null ? null : Directory(packDir),
        ),
      );
    } on Object catch (e) {
      debugPrint('[cbct] pack failed: $e');
      const message = 'The 3D viewer could not read this scan.';
      if (packDir != null) await _writeFailure(packDir, message);
      _set(
        study.id,
        CbctStatus(
          state: CbctPackState.failed,
          failure: message,
          packDir: packDir == null ? null : Directory(packDir),
        ),
      );
    }
  }

  /// Studies the person asked for by hand: a failure from this app version
  /// is tried once more.
  final Set<String> _retryFailed = {};

  /// Queues [study] at the front even if it failed before (the person
  /// opened it, so try again once).
  void retry(RadStudy study) {
    _retryFailed.add(study.id);
    if (_status[study.id]?.state == CbctPackState.failed) _status.remove(study.id);
    enqueue(study, priority: true);
  }
}

final cbctStoreProvider = Provider<CbctStore>((ref) => CbctStore.instance);

/// Where one study's 3D pack stands, by study id. Needs the study loaded
/// (see the radStudyProvider) before it can read the disk.
final cbctStatusProvider = StreamProvider.family<CbctStatus, String>((ref, studyId) {
  final store = ref.watch(cbctStoreProvider);
  final c = StreamController<CbctStatus>();
  final known = store._controllers.putIfAbsent(
    studyId,
    () => StreamController<CbctStatus>.broadcast(),
  );
  final current = store._status[studyId];
  if (current != null) c.add(current);
  final sub = known.stream.listen(c.add);
  ref.onDispose(() {
    sub.cancel();
    c.close();
  });
  return c.stream;
});
