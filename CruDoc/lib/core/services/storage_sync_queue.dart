import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/files/data/file_types.dart';

import 'medical_storage_service.dart';
import 'storage_upload_store.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';

export 'storage_upload_store.dart'
    show PendingUpload, UploadKind, UploadLink, UploadStatus;

/// Stand-in doctor id used while signed out; nothing is ever uploaded for it.
const String kLocalDoctorId = 'local_doctor';

/// The content type for a file name, or null when it isn't one CruDoc knows.
/// The one place extensions are mapped, so call sites don't repeat it.
String? contentTypeForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (path.substring(dot + 1).toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'tif' || 'tiff' => 'image/tiff',
    'dcm' => 'application/dicom',
    'pdf' => 'application/pdf',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'csv' => 'text/csv',
    'enc' => 'application/octet-stream',
    _ => null,
  };
}

/// Content types `storage.rules` accepts. Anything else (BMP, GIF…) would
/// be refused by the server, so callers can keep such files local-only
/// instead of queueing an upload that can never succeed.
bool isUploadableContentType(String contentType) =>
    _rulesContentTypes.contains(contentType);

const Set<String> _rulesContentTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/pdf',
  'audio/mp4',
  'audio/aac',
  'audio/opus',
  'text/csv',
  'application/octet-stream',
  'application/dicom',
  'image/tiff',
};

/// Whether [StorageSyncQueue.enqueue] takes a [contentType] file as [kind].
bool acceptsContentType(UploadKind kind, String contentType) =>
    _allowedTypes[kind]?.contains(contentType) ?? false;

/// True when [sizeBytes] is over what the rules allow for [contentType]:
/// 250 MB for DICOM and TIFF originals, 15 MB for everything else. Files
/// screen uploads ([UploadKind.patientFile]) have their own limits.
bool exceedsUploadLimit(
  int sizeBytes, {
  String contentType = '',
  UploadKind? kind,
}) =>
    sizeBytes >
    (kind == UploadKind.patientFile
        ? PatientFileTypes.maxBytesFor(contentType)
        : MedicalStorageService.maxUploadBytesFor(contentType));

const Set<String> _images = {'image/jpeg', 'image/png', 'image/webp'};
const Set<String> _audio = {'audio/mp4', 'audio/aac', 'audio/opus'};

/// What each kind accepts; mirrors the checks in `MedicalStorageService`.
final Map<UploadKind, Set<String>> _allowedTypes = {
  UploadKind.patientAvatar: _images,
  UploadKind.prescriptionPdf: {'application/pdf'},
  UploadKind.invoicePdf: {'application/pdf'},
  UploadKind.treatmentPlanPdf: {'application/pdf'},
  UploadKind.clinicalXray: {..._images, 'application/pdf'},
  UploadKind.clinicalPhoto: _images,
  UploadKind.clinicalLab: {..._images, 'application/pdf'},
  UploadKind.voiceDictation: _audio,
  UploadKind.brandingLogo: _images,
  UploadKind.brandingSignature: _images,
  UploadKind.inventoryReceipt: {..._images, 'application/pdf'},
  UploadKind.sterilizationStrip: _images,
  UploadKind.databaseBackup: {'application/octet-stream'},
  UploadKind.revenueCsv: {'text/csv'},
  UploadKind.imagingOriginal: {'application/dicom', 'image/tiff'},
  UploadKind.imagingPreview: {'image/jpeg'},
  UploadKind.patientFile: PatientFileTypes.contentTypes,
};

/// What a link handler is told once its file is in the bucket.
class UploadLinkContext {
  const UploadLinkContext({
    required this.queueId,
    required this.doctorId,
    required this.patientId,
    required this.storagePath,
    required this.link,
  });

  final String queueId;
  final String doctorId;
  final String? patientId;

  /// Where the file landed in Cloud Storage. Save this, never a URL.
  final String storagePath;
  final UploadLink link;
}

/// Records [UploadLinkContext.storagePath] on the feature's own record.
///
/// Must be safe to run more than once for the same upload: a failure after
/// the handler ran (or a crash) runs it again. It may delete
/// [UploadLinkContext.storagePath] itself when the record it belongs to is
/// gone (a discarded note, say); that counts as success.
typedef UploadLinkHandler = Future<void> Function(UploadLinkContext context);

/// Uploads one item's bytes and reports where they landed.
typedef UploadExecutor =
    Future<StoredFile> Function(PendingUpload item, Uint8List bytes);

/// Sets [field] on a Firestore document; fails until the document exists.
typedef FirestoreFieldPatch =
    Future<void> Function(
      String collectionPath,
      String docId,
      String field,
      String value,
    );

/// Uploads files to Cloud Storage in the background, and never loses one.
///
/// Callers save the file locally, call [enqueue] and carry on. The file is
/// copied into private staging and recorded in the local database, so it
/// survives an app restart and a long offline spell. It is uploaded when a
/// connection is available, its storage path is recorded on the record it
/// belongs to (see [UploadLink]), and only then is the staged copy removed.
///
/// On web there is no local database or file system: items are kept in
/// memory and uploaded at once, best effort.
class StorageSyncQueue {
  StorageSyncQueue._({
    UploadStore? store,
    UploadExecutor? upload,
    Future<void> Function(String path)? deleteObject,
    FirestoreFieldPatch? patchFirestore,
    String? Function()? currentDoctorId,
    Future<bool> Function()? isOnline,
    DateTime Function()? now,
  }) : _store = store ?? (kIsWeb ? MemoryUploadStore() : SqliteUploadStore()),
       _upload = upload ?? _uploadWithService,
       _deleteObject = deleteObject ?? _deleteWithService,
       _patchFirestore = patchFirestore ?? _patchFirestoreField,
       _currentDoctorId = currentDoctorId ?? _signedInDoctorId,
       _isOnline = isOnline ?? _deviceIsOnline,
       _now = now ?? DateTime.now;

  static final StorageSyncQueue instance = StorageSyncQueue._();

  /// A queue wired to fakes, so tests need neither Firebase nor a database.
  @visibleForTesting
  factory StorageSyncQueue.forTesting({
    required UploadStore store,
    required UploadExecutor upload,
    required Future<void> Function(String path) deleteObject,
    required String? Function() currentDoctorId,
    FirestoreFieldPatch? patchFirestore,
    Future<bool> Function()? isOnline,
    DateTime Function()? now,
  }) => StorageSyncQueue._(
    store: store,
    upload: upload,
    deleteObject: deleteObject,
    patchFirestore: patchFirestore ?? (collection, doc, field, value) async {},
    currentDoctorId: currentDoctorId,
    isOnline: isOnline ?? () async => true,
    now: now,
  );

  final UploadStore _store;
  final UploadExecutor _upload;
  final Future<void> Function(String path) _deleteObject;
  final FirestoreFieldPatch _patchFirestore;
  final String? Function() _currentDoctorId;
  final Future<bool> Function() _isOnline;
  final DateTime Function() _now;

  static const Uuid _uuid = Uuid();
  static const Duration _retention = Duration(days: 7);
  static const Duration _sweepEvery = Duration(minutes: 2);

  /// After this many failures of an unrecognised kind, the item is parked
  /// in Sync issues. Being offline never counts: that just keeps waiting.
  static const int _maxUnexpectedAttempts = 10;

  static const List<Duration> _backoff = [
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];
  static const Duration _backoffCap = Duration(hours: 1);

  final Map<String, UploadLinkHandler> _handlers = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _timer;
  bool _started = false;
  Future<void>? _inFlight;
  bool _rerun = false;
  bool _rerunIgnoresBackoff = false;
  String? _recoveredFor;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Starts the triggers: sign-in, connection regained, and a timer as a
  /// backstop. Safe to call more than once. Call after `Firebase.initializeApp`.
  void start() {
    if (_started) return;
    _started = true;

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _changes.add(null);
      if (user != null) unawaited(processPending(ignoreBackoff: true));
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(processPending(ignoreBackoff: true));
      }
    });
    _timer = Timer.periodic(_sweepEvery, (_) => unawaited(processPending()));

    unawaited(processPending(ignoreBackoff: true));
  }

  Future<void> stop() async {
    await _authSub?.cancel();
    await _connectivitySub?.cancel();
    _timer?.cancel();
    _authSub = _connectivitySub = null;
    _timer = null;
    _started = false;
  }

  /// Names a [UploadLinkHandler] so a queued item can find it again after a
  /// restart. Register at startup, before anything is enqueued.
  void registerLinkHandler(String name, UploadLinkHandler handler) =>
      _handlers[name] = handler;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Stages [bytes] and queues them for upload. Returns the queue id, or null
  /// when nothing was queued: not signed in as a real doctor, a patient file
  /// with no patient, a content type the kind doesn't take, or a file over
  /// 15 MB. The reason is logged. Never throws for network errors — the local
  /// copy the caller already saved is what matters offline.
  ///
  /// [compress] applies to clinical media only; avatars, branding, receipts
  /// and strips are always compressed by `MedicalStorageService`.
  ///
  /// Set [deleteLocalAfter] for sensitive files (voice): the staged copy is
  /// also dropped if the upload is abandoned.
  Future<String?> enqueue({
    required UploadKind kind,
    required Uint8List bytes,
    required String contentType,
    String? patientId,
    UploadLink? link,
    String? replacePath,
    bool compress = false,
    bool deleteLocalAfter = false,
  }) async {
    try {
      final doctorId = _currentDoctorId();
      if (doctorId == null) {
        _log('not enqueuing ${kind.name}: no signed-in doctor');
        return null;
      }
      if (kind.isPatientScoped && (patientId == null || patientId.isEmpty)) {
        _log('not enqueuing ${kind.name}: no patient id');
        return null;
      }
      if (!(_allowedTypes[kind]?.contains(contentType) ?? false)) {
        _log('not enqueuing ${kind.name}: content type $contentType');
        return null;
      }
      final willCompress =
          _images.contains(contentType) &&
          (compress || _alwaysCompressed.contains(kind));
      if (!willCompress &&
          exceedsUploadLimit(
            bytes.lengthInBytes,
            contentType: contentType,
            kind: kind,
          )) {
        _log(
          'not enqueuing ${kind.name}: ${bytes.lengthInBytes} bytes is over '
          'the limit for $contentType',
        );
        return null;
      }

      final now = _now();
      final id = _uuid.v4();
      await _store.stage(
        PendingUpload(
          id: id,
          doctorId: doctorId,
          patientId: patientId,
          kind: kind,
          localPath: '',
          contentType: contentType,
          compress: compress,
          link: link,
          replacePath: replacePath,
          deleteLocalAfter: deleteLocalAfter,
          status: UploadStatus.pending,
          createdAt: now,
          updatedAt: now,
        ),
        bytes,
      );
      _changes.add(null);
      unawaited(processPending(ignoreBackoff: true));
      return id;
    } catch (e) {
      _log('enqueue failed: $e');
      return null;
    }
  }

  /// Uploads what is waiting for the signed-in doctor. Rows for any other
  /// doctor are left alone. Items that failed recently wait out their
  /// backoff unless [ignoreBackoff] is set (connection regained, manual
  /// retry). Safe to call at any time: if a pass is already running this waits
  /// for it (and for a second look at the queue) instead of starting another.
  Future<void> processPending({bool ignoreBackoff = false}) {
    final running = _inFlight;
    if (running != null) {
      // Wait for the pass already under way, which then goes round again
      // to pick up whatever was added since it listed the queue.
      _rerun = true;
      _rerunIgnoresBackoff = _rerunIgnoresBackoff || ignoreBackoff;
      return running;
    }
    return _inFlight = _drain(
      ignoreBackoff,
    ).whenComplete(() => _inFlight = null);
  }

  Future<void> _drain(bool ignoreBackoff) async {
    try {
      var skipBackoff = ignoreBackoff;
      do {
        _rerun = false;
        await _runPass(skipBackoff);
        skipBackoff = _rerunIgnoresBackoff;
        _rerunIgnoresBackoff = false;
      } while (_rerun);
    } catch (e) {
      _log('pass failed: $e');
    }
  }

  /// Stops an item. Not yet uploaded: its staged copy is dropped. Uploaded
  /// but not yet linked (or being uploaded right now): the object is deleted
  /// too. Already done: left as is — the record it belongs to owns it now.
  Future<void> cancel(String queueId) async {
    final item = await _store.get(queueId);
    if (item == null || item.status == UploadStatus.done) return;
    if (item.status == UploadStatus.cancelled) return;

    await _store.save(
      item.copyWith(status: UploadStatus.cancelled, updatedAt: _now()),
    );
    // An upload in flight notices the cancelled status when it finishes and
    // removes what it just uploaded; nothing more to do for it here.
    if (item.status != UploadStatus.uploading) {
      await _store.deleteBytes(item);
      final uploaded = item.resultPath;
      if (uploaded != null && uploaded.isNotEmpty) {
        await _deleteQuietly(uploaded);
      }
    }
    _changes.add(null);
  }

  /// Cancels every unfinished item whose link runs [handler] for [docId]
  /// (e.g. everything still on its way for one scribe note). Lets a feature
  /// stop its uploads without having remembered their queue ids.
  Future<void> cancelByLink(String handler, String docId) async {
    final doctorId = _currentDoctorId();
    if (doctorId == null) return;
    final open = await _store.list(doctorId, {
      UploadStatus.pending,
      UploadStatus.uploading,
      UploadStatus.failed,
    });
    for (final item in open) {
      final link = item.link;
      if (link != null && link.handler == handler && link.docId == docId) {
        await cancel(item.id);
      }
    }
  }

  Future<PendingUpload?> get(String queueId) => _store.get(queueId);

  /// Puts a failed item back in line, ignoring its backoff.
  Future<void> retry(String queueId) async {
    final item = await _store.get(queueId);
    if (item == null || item.status != UploadStatus.failed) return;
    await _store.save(
      item.copyWith(
        status: UploadStatus.pending,
        attempts: 0,
        updatedAt: _now(),
      ),
    );
    _changes.add(null);
    unawaited(processPending(ignoreBackoff: true));
  }

  Future<void> retryAllFailed() async {
    final doctorId = _currentDoctorId();
    if (doctorId == null) return;
    for (final item in await _store.list(doctorId, {UploadStatus.failed})) {
      await retry(item.id);
    }
  }

  /// Items the doctor needs to look at.
  Future<List<PendingUpload>> failedUploads() async {
    final doctorId = _currentDoctorId();
    if (doctorId == null) return const [];
    return _store.list(doctorId, {UploadStatus.failed});
  }

  /// Waiting or uploading, for the signed-in doctor.
  Stream<int> watchPendingCount() =>
      _watch({UploadStatus.pending, UploadStatus.uploading});

  Stream<int> watchFailedCount() => _watch({UploadStatus.failed});

  Stream<int> _watch(Set<UploadStatus> statuses) {
    late final StreamController<int> controller;
    StreamSubscription<void>? subscription;
    int? last;

    Future<void> emit() async {
      final doctorId = _currentDoctorId();
      var next = 0;
      if (doctorId != null) {
        try {
          next = await _store.count(doctorId, statuses);
        } catch (_) {
          // Counts are only for the badge; a read error shows as none waiting.
        }
      }
      if (controller.isClosed || next == last) return;
      last = next;
      controller.add(next);
    }

    controller = StreamController<int>(
      onListen: () {
        subscription = _changes.stream.listen((_) => unawaited(emit()));
        unawaited(emit());
      },
      onCancel: () async {
        await subscription?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // Processing
  // ---------------------------------------------------------------------------

  Future<void> _runPass(bool ignoreBackoff) async {
    final doctorId = _currentDoctorId();
    if (doctorId == null) return;

    if (_recoveredFor != doctorId) {
      // Left "uploading" by an app killed mid-upload: uploading again is
      // safe, and an item that already reached the bucket resumes at linking.
      for (final stuck in await _store.list(doctorId, {
        UploadStatus.uploading,
      })) {
        await _store.save(stuck.copyWith(status: UploadStatus.pending));
      }
      _recoveredFor = doctorId;
      unawaited(_store.sweepOrphanedBytes());
    }
    await _store.purgeFinishedBefore(_now().subtract(_retention));

    final waiting = await _store.list(doctorId, {UploadStatus.pending});
    for (final item in waiting) {
      // Signed out, or another doctor signed in, part-way through.
      if (_currentDoctorId() != doctorId) break;
      if (!ignoreBackoff && !_isDue(item)) continue;
      await _processOne(item);
    }
    _changes.add(null);
  }

  bool _isDue(PendingUpload item) {
    if (item.attempts == 0) return true;
    return !_now().isBefore(item.updatedAt.add(_delayFor(item.attempts)));
  }

  static Duration _delayFor(int attempts) =>
      attempts <= _backoff.length ? _backoff[attempts - 1] : _backoffCap;

  Future<void> _processOne(PendingUpload listed) async {
    // Cancelled (or otherwise moved on) since the pass listed it.
    final item = await _store.get(listed.id);
    if (item == null || item.status != UploadStatus.pending) return;

    var current = item.copyWith(status: UploadStatus.uploading);
    await _store.save(current);
    _changes.add(null);

    try {
      var path = current.resultPath;
      if (path == null || path.isEmpty) {
        final bytes = await _store.readBytes(current);
        if (bytes == null) {
          throw const _PermanentFailure(
            'The saved copy of this file is missing.',
          );
        }
        final stored = await _upload(current, bytes);
        path = stored.path;
        // Remember it before anything else can fail, so a retry finishes
        // linking rather than uploading a second copy. Start from the stored
        // row, not the copy held since the upload began, or a cancel that
        // arrived meanwhile would be overwritten.
        current = (await _store.get(current.id) ?? current).copyWith(
          resultPath: path,
        );
        await _store.save(current);
      }

      // Cancelled while the upload ran: don't leave the object behind.
      final latest = await _store.get(current.id);
      if (latest == null || latest.status == UploadStatus.cancelled) {
        await _deleteQuietly(path);
        await _store.deleteBytes(current);
        return;
      }

      await _link(current, path);

      final replaced = current.replacePath;
      if (replaced != null && replaced.isNotEmpty && replaced != path) {
        await _deleteQuietly(replaced);
      }

      await _store.save(
        current.copyWith(
          status: UploadStatus.done,
          clearLastError: true,
          updatedAt: _now(),
        ),
      );
      await _store.deleteBytes(current);
    } catch (e) {
      await _recordFailure(current, e);
    }
  }

  Future<void> _link(PendingUpload item, String storagePath) async {
    final link = item.link;
    if (link == null) return;

    final name = link.handler;
    if (name != null) {
      final handler = _handlers[name];
      if (handler == null) {
        throw StateError('No link handler registered for "$name".');
      }
      await handler(
        UploadLinkContext(
          queueId: item.id,
          doctorId: item.doctorId,
          patientId: item.patientId,
          storagePath: storagePath,
          link: link,
        ),
      );
      return;
    }
    if (link.collectionPath.isEmpty ||
        link.docId.isEmpty ||
        link.field.isEmpty) {
      return;
    }
    await _patchFirestore(
      link.collectionPath,
      link.docId,
      link.field,
      storagePath,
    )
    // Offline, a Firestore write waits instead of failing.
    .timeout(const Duration(seconds: 30));
  }

  Future<void> _recordFailure(PendingUpload item, Object error) async {
    // Cancelled while it was failing: it stays cancelled.
    final latest = await _store.get(item.id);
    if (latest == null || latest.status == UploadStatus.cancelled) {
      final uploaded = latest?.resultPath ?? item.resultPath;
      if (uploaded != null && uploaded.isNotEmpty) {
        await _deleteQuietly(uploaded);
      }
      await _store.deleteBytes(item);
      return;
    }

    var failure = _classify(error);
    if (!failure.permanent && !failure.offline && !await _isOnline()) {
      failure = _Failure.offline('No connection; will retry.');
    }
    _log('${item.kind.name} ${item.id}: ${failure.message} ($error)');

    final attempts = item.attempts + 1;
    final gaveUp =
        failure.permanent ||
        (!failure.offline && attempts >= _maxUnexpectedAttempts);

    await _store.save(
      item.copyWith(
        status: gaveUp ? UploadStatus.failed : UploadStatus.pending,
        attempts: attempts,
        lastError: failure.message,
        updatedAt: _now(),
      ),
    );
    if (gaveUp && item.deleteLocalAfter) await _store.deleteBytes(item);
  }

  _Failure _classify(Object error) {
    if (error is _PermanentFailure) return _Failure.permanent(error.message);
    if (error is StorageFileTooLargeException) {
      return _Failure.permanent(error.message);
    }
    if (error is StorageCompressionException) {
      return _Failure.permanent(error.message);
    }
    if (error is ArgumentError) {
      return _Failure.permanent('This file is not accepted for upload.');
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        'unauthorized' => _Failure.permanent(
          'The server refused this file (permission denied).',
        ),
        'invalid-argument' ||
        'invalid-checksum' ||
        'invalid-url' ||
        'bucket-not-found' ||
        'project-not-found' => _Failure.permanent(
          'The server rejected this file (${error.code}).',
        ),
        'retry-limit-exceeded' ||
        'unavailable' ||
        'network-request-failed' ||
        'canceled' => _Failure.offline('No connection; will retry.'),
        _ => _Failure.unexpected(error.message ?? error.code),
      };
    }
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return _Failure.offline('No connection; will retry.');
    }
    return _Failure.unexpected(error.toString());
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await _deleteObject(path);
    } on FirebaseException catch (e) {
      // Already gone (the lifecycle rule, or a second delete) is the goal.
      if (e.code != 'object-not-found') {
        _log('could not delete $path: ${e.code}');
      }
    } catch (e) {
      _log('could not delete $path: $e');
    }
  }

  static const Set<UploadKind> _alwaysCompressed = {
    UploadKind.patientAvatar,
    UploadKind.brandingLogo,
    UploadKind.brandingSignature,
    UploadKind.inventoryReceipt,
    UploadKind.sterilizationStrip,
  };

  void _log(String message) => debugPrint('[StorageSyncQueue] $message');

  // ---------------------------------------------------------------------------
  // Defaults
  // ---------------------------------------------------------------------------

  static String? _signedInDoctorId() {
    try {
      final uid = ClinicSession.instance.tenantId;
      if (uid == null || uid.isEmpty || uid == kLocalDoctorId) return null;
      return uid;
    } catch (_) {
      // Firebase isn't running (widget tests, or very early startup): nobody
      // is signed in, so there is nothing to upload and nothing to show.
      return null;
    }
  }

  static Future<bool> _deviceIsOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  static Future<void> _deleteWithService(String path) =>
      MedicalStorageService.instance.delete(path);

  /// `update`, not `set`: it fails with `not-found` until the record has
  /// synced, so the queue waits instead of creating a stub document.
  static Future<void> _patchFirestoreField(
    String collectionPath,
    String docId,
    String field,
    String value,
  ) => FirebaseFirestore.instance.collection(collectionPath).doc(docId).update({
    field: value,
  });

  static Future<StoredFile> _uploadWithService(
    PendingUpload item,
    Uint8List bytes,
  ) {
    final service = MedicalStorageService.instance;
    final doctorId = item.doctorId;
    final patientId = item.patientId ?? '';
    final type = item.contentType;

    return switch (item.kind) {
      UploadKind.patientAvatar => service.uploadPatientAvatar(
        doctorId: doctorId,
        patientId: patientId,
        bytes: bytes,
        contentType: type,
      ),
      UploadKind.prescriptionPdf => service.uploadPrescriptionPdf(
        doctorId: doctorId,
        patientId: patientId,
        bytes: bytes,
      ),
      UploadKind.invoicePdf => service.uploadInvoicePdf(
        doctorId: doctorId,
        patientId: patientId,
        bytes: bytes,
      ),
      UploadKind.treatmentPlanPdf => service.uploadTreatmentPlanPdf(
        doctorId: doctorId,
        patientId: patientId,
        bytes: bytes,
      ),
      UploadKind.clinicalXray => service.uploadClinicalMedia(
        doctorId: doctorId,
        patientId: patientId,
        kind: ClinicalMediaKind.xray,
        bytes: bytes,
        contentType: type,
        compress: item.compress,
      ),
      UploadKind.clinicalPhoto => service.uploadClinicalMedia(
        doctorId: doctorId,
        patientId: patientId,
        kind: ClinicalMediaKind.photo,
        bytes: bytes,
        contentType: type,
        compress: item.compress,
      ),
      UploadKind.clinicalLab => service.uploadClinicalMedia(
        doctorId: doctorId,
        patientId: patientId,
        kind: ClinicalMediaKind.lab,
        bytes: bytes,
        contentType: type,
        compress: item.compress,
      ),
      // The dictation scratch folder belongs to the person, not the clinic.
      UploadKind.voiceDictation => service.uploadVoiceDictation(
        doctorId: FirebaseAuth.instance.currentUser?.uid ?? doctorId,
        patientId: patientId,
        bytes: bytes,
        contentType: type,
      ),
      UploadKind.brandingLogo => service.uploadClinicBranding(
        doctorId: doctorId,
        kind: ClinicBrandingKind.logo,
        bytes: bytes,
        contentType: type,
      ),
      UploadKind.brandingSignature => service.uploadClinicBranding(
        doctorId: doctorId,
        kind: ClinicBrandingKind.signature,
        bytes: bytes,
        contentType: type,
      ),
      UploadKind.inventoryReceipt => service.uploadInventoryReceipt(
        doctorId: doctorId,
        bytes: bytes,
        contentType: type,
      ),
      UploadKind.sterilizationStrip => service.uploadSterilizationStrip(
        doctorId: doctorId,
        bytes: bytes,
        contentType: type,
      ),
      UploadKind.databaseBackup => service.uploadDatabaseBackup(
        doctorId: doctorId,
        encryptedBytes: bytes,
      ),
      UploadKind.imagingOriginal => service.uploadImagingOriginal(
        doctorId: doctorId,
        patientId: patientId,
        bytes: bytes,
        contentType: type,
      ),
      UploadKind.imagingPreview => service.uploadClinicalMedia(
        doctorId: doctorId,
        patientId: patientId,
        kind: ClinicalMediaKind.imagingPreview,
        bytes: bytes,
        contentType: type,
        compress: false, // Already a small JPEG.
      ),
      UploadKind.revenueCsv => service.uploadRevenueCsv(
        doctorId: doctorId,
        bytes: bytes,
      ),
      // Stored under the file's own id (the link's document).
      UploadKind.patientFile => service.uploadPatientFile(
        doctorId: doctorId,
        patientId: patientId,
        fileId: item.link?.docId ?? '',
        bytes: bytes,
        contentType: type,
      ),
    };
  }
}

/// A failure retrying can't fix.
class _PermanentFailure implements Exception {
  const _PermanentFailure(this.message);
  final String message;
}

class _Failure {
  const _Failure._(
    this.message, {
    required this.permanent,
    required this.offline,
  });

  /// Won't work however often it is retried.
  factory _Failure.permanent(String message) =>
      _Failure._(message, permanent: true, offline: false);

  /// No connection: keeps waiting, however long it takes.
  factory _Failure.offline(String message) =>
      _Failure._(message, permanent: false, offline: true);

  /// Not understood: retried, but parked after a few attempts.
  factory _Failure.unexpected(String message) =>
      _Failure._(message, permanent: false, offline: false);

  final String message;
  final bool permanent;
  final bool offline;
}
