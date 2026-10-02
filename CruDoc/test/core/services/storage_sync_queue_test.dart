import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';
import 'package:doctor_management_app/core/services/storage_upload_store.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseException _fb(String code) =>
    FirebaseException(plugin: 'firebase_storage', code: code);

/// A queue over an in-memory store with a scripted uploader, so retry,
/// backoff and linking can be checked without Firebase or a database.
class _Harness {
  _Harness({this.doctor = 'doc-a'}) {
    queue = StorageSyncQueue.forTesting(
      store: store,
      currentDoctorId: () => doctor,
      isOnline: () async => online,
      now: () => clock,
      upload: (item, bytes) async {
        uploads.add(item.kind);
        if (uploadOutcomes.isNotEmpty) {
          final next = uploadOutcomes.removeAt(0);
          if (next != null) throw next;
        }
        return StoredFile(
          path: 'doctors/${item.doctorId}/x/${uploads.length}.pdf',
          contentType: item.contentType,
          sizeBytes: bytes.length,
        );
      },
      deleteObject: (path) async {
        deleted.add(path);
        if (deleteFails) throw _fb('object-not-found');
      },
      patchFirestore: (collection, doc, field, value) async {
        patches.add('$collection/$doc.$field=$value');
        if (patchOutcomes.isNotEmpty) {
          final next = patchOutcomes.removeAt(0);
          if (next != null) throw next;
        }
      },
    );
  }

  final MemoryUploadStore store = MemoryUploadStore();
  late final StorageSyncQueue queue;
  String? doctor;
  bool online = true;
  bool deleteFails = false;
  DateTime clock = DateTime(2026, 9, 1, 9);

  /// What successive uploads / link patches throw (null entries succeed).
  final List<Object?> uploadOutcomes = [];
  final List<Object?> patchOutcomes = [];

  final List<UploadKind> uploads = [];
  final List<String> deleted = [];
  final List<String> patches = [];

  Future<String?> enqueue({
    UploadKind kind = UploadKind.prescriptionPdf,
    String contentType = 'application/pdf',
    String? patientId = 'p1',
    UploadLink? link,
    String? replacePath,
    bool deleteLocalAfter = false,
    int size = 10,
  }) => queue.enqueue(
    kind: kind,
    bytes: Uint8List(size),
    contentType: contentType,
    patientId: patientId,
    link: link,
    replacePath: replacePath,
    deleteLocalAfter: deleteLocalAfter,
  );

  Future<PendingUpload?> row(String? id) => queue.get(id!);

  /// Waits for the pass `enqueue` starts. A failed item stays inside its
  /// backoff, so this is exactly one attempt per item.
  Future<void> settle() => queue.processPending();

  /// Moves the clock past any backoff, then runs a pass: one more attempt.
  Future<void> tick() {
    clock = clock.add(const Duration(hours: 2));
    return queue.processPending();
  }
}

void main() {
  group('enqueue', () {
    test('uploads a file, then records the row as done', () async {
      final h = _Harness();
      final id = await h.enqueue();
      await h.settle();

      final row = await h.row(id);
      expect(row?.status, UploadStatus.done);
      expect(row?.resultPath, isNotNull);
      expect(h.uploads, [UploadKind.prescriptionPdf]);
      expect(await h.store.readBytes(row!), isNull, reason: 'staged copy goes');
    });

    test('queues nothing when nobody is signed in', () async {
      final h = _Harness(doctor: null);
      expect(await h.enqueue(), isNull);
      expect(h.uploads, isEmpty);
    });

    test('queues nothing for a patient file with no patient', () async {
      final h = _Harness();
      expect(await h.enqueue(patientId: null), isNull);
      expect(await h.enqueue(patientId: ''), isNull);
    });

    test('rejects a content type the kind does not take', () async {
      final h = _Harness();
      expect(
        await h.enqueue(
          kind: UploadKind.clinicalXray,
          contentType: 'application/dicom',
        ),
        isNull,
      );
      expect(await h.enqueue(contentType: 'text/html'), isNull);
    });

    test('rejects an uncompressed file over 15 MB', () async {
      final h = _Harness();
      expect(await h.enqueue(size: 15 * 1024 * 1024 + 1), isNull);
    });

    test('accepts a large image the service will compress', () async {
      final h = _Harness();
      final id = await h.enqueue(
        kind: UploadKind.sterilizationStrip,
        contentType: 'image/jpeg',
        patientId: null,
        size: 20 * 1024 * 1024,
      );
      expect(id, isNotNull);
    });
  });

  group('failures', () {
    test('being offline keeps the item pending, however long', () async {
      final h = _Harness()
        ..uploadOutcomes.addAll(List.filled(15, _fb('retry-limit-exceeded')));
      final id = await h.enqueue();
      await h.settle();
      for (var i = 1; i < 15; i++) {
        await h.tick();
      }
      final row = await h.row(id);
      expect(row?.status, UploadStatus.pending);
      expect(row?.attempts, 15);
      expect(await h.store.readBytes(row!), isNotNull, reason: 'file is kept');
    });

    test('a refused upload fails at once and keeps the staged file', () async {
      final h = _Harness()..uploadOutcomes.add(_fb('unauthorized'));
      final id = await h.enqueue();
      await h.settle();

      final row = await h.row(id);
      expect(row?.status, UploadStatus.failed);
      expect(row?.lastError, contains('permission'));
      expect(await h.store.readBytes(row!), isNotNull);
      await h.tick();
      expect(h.uploads, hasLength(1), reason: 'not retried');
    });

    test('a too-large file fails permanently', () async {
      final h = _Harness()
        ..uploadOutcomes.add(StorageFileTooLargeException(20, 15));
      final id = await h.enqueue();
      await h.settle();
      expect((await h.row(id))?.status, UploadStatus.failed);
    });

    test('a failed sensitive file is not kept on the device', () async {
      final h = _Harness()..uploadOutcomes.add(_fb('unauthorized'));
      final id = await h.enqueue(
        kind: UploadKind.voiceDictation,
        contentType: 'audio/mp4',
        deleteLocalAfter: true,
      );
      await h.settle();
      final row = await h.row(id);
      expect(row?.status, UploadStatus.failed);
      expect(await h.store.readBytes(row!), isNull);
    });

    test('an unrecognised error is parked after ten attempts', () async {
      final h = _Harness()
        ..uploadOutcomes.addAll(List.filled(12, StateError('boom')));
      final id = await h.enqueue();
      await h.settle();
      for (var i = 1; i < 12; i++) {
        await h.tick();
      }
      expect((await h.row(id))?.status, UploadStatus.failed);
      expect(h.uploads, hasLength(10), reason: 'stops at the tenth attempt');
    });

    test('an unrecognised error while offline is never parked', () async {
      final h = _Harness()
        ..online = false
        ..uploadOutcomes.addAll(List.filled(12, StateError('boom')));
      final id = await h.enqueue();
      await h.settle();
      for (var i = 1; i < 12; i++) {
        await h.tick();
      }
      expect((await h.row(id))?.status, UploadStatus.pending);
    });

    test('retry puts a failed item back in line', () async {
      final h = _Harness()..uploadOutcomes.add(_fb('unauthorized'));
      final id = await h.enqueue();
      await h.settle();
      await h.queue.retry(id!);
      await h.settle();
      expect((await h.row(id))?.status, UploadStatus.done);
      expect(h.uploads, hasLength(2));
    });
  });

  group('backoff', () {
    test('a failed item waits out its delay', () async {
      final h = _Harness()..uploadOutcomes.add(_fb('retry-limit-exceeded'));
      await h.enqueue();
      await h.settle();
      expect(h.uploads, hasLength(1));

      await h.queue.processPending();
      expect(h.uploads, hasLength(1), reason: 'still inside the 30 s delay');

      h.clock = h.clock.add(const Duration(seconds: 31));
      await h.queue.processPending();
      expect(h.uploads, hasLength(2));
    });

    test('regaining the connection skips the wait', () async {
      final h = _Harness()..uploadOutcomes.add(_fb('retry-limit-exceeded'));
      await h.enqueue();
      await h.settle();
      expect(h.uploads, hasLength(1));

      await h.queue.processPending(ignoreBackoff: true);
      expect(h.uploads, hasLength(2));
    });
  });

  group('linking', () {
    test('patches the Firestore field once the file is uploaded', () async {
      final h = _Harness();
      await h.enqueue(link: const UploadLink('visits', 'v1', 'pdfStoragePath'));
      await h.settle();
      expect(h.patches, ['visits/v1.pdfStoragePath=doctors/doc-a/x/1.pdf']);
    });

    test('a failed link retries without uploading a second copy', () async {
      final h = _Harness()..patchOutcomes.add(_fb('not-found'));
      final id = await h.enqueue(
        link: const UploadLink('visits', 'v1', 'pdfStoragePath'),
      );
      await h.settle();
      expect((await h.row(id))?.status, UploadStatus.pending);
      expect((await h.row(id))?.resultPath, isNotNull);

      await h.tick();
      expect((await h.row(id))?.status, UploadStatus.done);
      expect(h.uploads, hasLength(1), reason: 'uploaded once');
      expect(h.patches, hasLength(2));
    });

    test('runs a registered handler with the storage path', () async {
      final h = _Harness();
      UploadLinkContext? seen;
      h.queue.registerLinkHandler('note.audio', (ctx) async => seen = ctx);
      final id = await h.enqueue(
        link: const UploadLink.viaHandler(
          'note.audio',
          docId: 'n1',
          args: {'k': 1},
        ),
      );
      await h.settle();

      expect(seen?.queueId, id);
      expect(seen?.storagePath, 'doctors/doc-a/x/1.pdf');
      expect(seen?.link.docId, 'n1');
      expect(seen?.link.args, {'k': 1});
      expect(h.patches, isEmpty, reason: 'a handler replaces the patch');
    });

    test('a missing handler waits instead of losing the upload', () async {
      final h = _Harness();
      final id = await h.enqueue(link: const UploadLink.viaHandler('late'));
      await h.settle();
      expect((await h.row(id))?.status, UploadStatus.pending);

      h.queue.registerLinkHandler('late', (_) async {});
      await h.tick();
      expect((await h.row(id))?.status, UploadStatus.done);
      expect(h.uploads, hasLength(1));
    });

    test('deletes the replaced version only after the new one links', () async {
      final h = _Harness()..patchOutcomes.add(_fb('not-found'));
      await h.enqueue(
        link: const UploadLink('visits', 'v1', 'pdfStoragePath'),
        replacePath: 'doctors/doc-a/old.pdf',
      );
      await h.settle();
      expect(h.deleted, isEmpty, reason: 'the old file is still the only copy');

      await h.tick();
      expect(h.deleted, ['doctors/doc-a/old.pdf']);
    });

    test('a replaced file that is already gone is not an error', () async {
      final h = _Harness()..deleteFails = true;
      final id = await h.enqueue(replacePath: 'doctors/doc-a/old.pdf');
      await h.settle();
      expect((await h.row(id))?.status, UploadStatus.done);
    });
  });

  group('cancel', () {
    test('drops a waiting file before it is uploaded', () async {
      final h = _Harness()..uploadOutcomes.add(_fb('retry-limit-exceeded'));
      final id = await h.enqueue();
      await h.settle();
      await h.queue.cancel(id!);

      final row = await h.row(id);
      expect(row?.status, UploadStatus.cancelled);
      expect(await h.store.readBytes(row!), isNull);
      await h.tick();
      expect(h.uploads, hasLength(1), reason: 'never retried');
    });

    test(
      'deletes the object when cancelled after upload, before link',
      () async {
        final h = _Harness()..patchOutcomes.add(_fb('not-found'));
        final id = await h.enqueue(link: const UploadLink('visits', 'v1', 'f'));
        await h.settle();
        await h.queue.cancel(id!);
        expect(h.deleted, ['doctors/doc-a/x/1.pdf']);
      },
    );

    test('an upload cancelled mid-flight is removed when it lands', () async {
      final h = _Harness();
      final started = Completer<void>();
      final release = Completer<void>();
      final queue = StorageSyncQueue.forTesting(
        store: h.store,
        currentDoctorId: () => 'doc-a',
        upload: (item, bytes) async {
          started.complete();
          await release.future;
          return const StoredFile(
            path: 'doctors/doc-a/late.pdf',
            contentType: 'application/pdf',
            sizeBytes: 1,
          );
        },
        deleteObject: (path) async => h.deleted.add(path),
      );
      final id = await queue.enqueue(
        kind: UploadKind.prescriptionPdf,
        bytes: Uint8List(4),
        contentType: 'application/pdf',
        patientId: 'p1',
      );
      await started.future;

      await queue.cancel(id!);
      release.complete();
      await queue.processPending();

      expect(h.deleted, ['doctors/doc-a/late.pdf']);
      expect((await queue.get(id))?.status, UploadStatus.cancelled);
    });

    test(
      'an upload that fails after being cancelled stays cancelled',
      () async {
        final h = _Harness();
        final started = Completer<void>();
        final release = Completer<void>();
        final queue = StorageSyncQueue.forTesting(
          store: h.store,
          currentDoctorId: () => 'doc-a',
          upload: (item, bytes) async {
            started.complete();
            await release.future;
            throw _fb('retry-limit-exceeded');
          },
          deleteObject: (path) async => h.deleted.add(path),
        );
        final id = await queue.enqueue(
          kind: UploadKind.prescriptionPdf,
          bytes: Uint8List(4),
          contentType: 'application/pdf',
          patientId: 'p1',
        );
        await started.future;

        await queue.cancel(id!);
        release.complete();
        await queue.processPending();

        final row = await queue.get(id);
        expect(row?.status, UploadStatus.cancelled);
        expect(await h.store.readBytes(row!), isNull);
      },
    );

    test('leaves a finished upload alone', () async {
      final h = _Harness();
      final id = await h.enqueue();
      await h.settle();
      await h.queue.cancel(id!);
      expect((await h.row(id))?.status, UploadStatus.done);
      expect(h.deleted, isEmpty);
    });
  });

  group('doctors', () {
    test("another doctor's files wait until that doctor signs in", () async {
      final h = _Harness()..uploadOutcomes.add(_fb('retry-limit-exceeded'));
      final id = await h.enqueue();
      await h.settle();
      expect(h.uploads, hasLength(1));

      h.doctor = 'doc-b';
      await h.tick();
      expect(
        h.uploads,
        hasLength(1),
        reason: "doc-b must not send doc-a's file",
      );

      h.doctor = 'doc-a';
      await h.tick();
      expect((await h.row(id))?.status, UploadStatus.done);
    });

    test('nothing is uploaded while signed out', () async {
      final h = _Harness()..uploadOutcomes.add(_fb('retry-limit-exceeded'));
      await h.enqueue();
      await h.settle();

      h.doctor = null;
      await h.tick();
      expect(h.uploads, hasLength(1));
    });
  });

  group('counts', () {
    test('watchPendingCount follows the queue', () async {
      final h = _Harness()..uploadOutcomes.add(_fb('retry-limit-exceeded'));
      final seen = <int>[];
      final sub = h.queue.watchPendingCount().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [0]);

      await h.enqueue();
      await h.settle();
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, 1);

      await h.tick();
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, 0);
      await sub.cancel();
    });

    test('watchFailedCount counts parked items', () async {
      final h = _Harness()..uploadOutcomes.add(_fb('unauthorized'));
      final seen = <int>[];
      final sub = h.queue.watchFailedCount().listen(seen.add);
      await h.enqueue();
      await h.settle();
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, 1);
      await sub.cancel();
    });
  });

  group('contentTypeForPath', () {
    test('maps the known extensions, case-insensitively', () {
      expect(contentTypeForPath('a/b/scan.JPG'), 'image/jpeg');
      expect(contentTypeForPath('x.jpeg'), 'image/jpeg');
      expect(contentTypeForPath('x.tif'), 'image/tiff');
      expect(contentTypeForPath('x.dcm'), 'application/dicom');
      expect(contentTypeForPath('x.enc'), 'application/octet-stream');
      expect(contentTypeForPath('x.m4a'), 'audio/mp4');
    });

    test('returns null for an unknown or missing extension', () {
      expect(contentTypeForPath('x.exe'), isNull);
      expect(contentTypeForPath('noextension'), isNull);
    });

    test('knows which types the storage rules take', () {
      expect(isUploadableContentType('image/png'), isTrue);
      expect(isUploadableContentType('application/dicom'), isTrue);
      expect(isUploadableContentType('image/tiff'), isTrue);
      expect(isUploadableContentType('image/bmp'), isFalse);
    });

    test('takes DICOM and TIFF as imaging originals only', () {
      expect(
        acceptsContentType(UploadKind.imagingOriginal, 'application/dicom'),
        isTrue,
      );
      expect(
        acceptsContentType(UploadKind.imagingOriginal, 'image/tiff'),
        isTrue,
      );
      expect(
        acceptsContentType(UploadKind.imagingOriginal, 'image/jpeg'),
        isFalse,
      );
      expect(
        acceptsContentType(UploadKind.clinicalPhoto, 'image/tiff'),
        isFalse,
      );
      expect(
        acceptsContentType(UploadKind.clinicalXray, 'application/dicom'),
        isFalse,
      );
      expect(
        acceptsContentType(UploadKind.imagingPreview, 'image/jpeg'),
        isTrue,
      );
    });
  });

  group('exceedsUploadLimit', () {
    const mb = 1024 * 1024;

    test('allows DICOM and TIFF up to 250 MB', () {
      expect(
        exceedsUploadLimit(250 * mb, contentType: 'application/dicom'),
        isFalse,
      );
      expect(
        exceedsUploadLimit(250 * mb + 1, contentType: 'application/dicom'),
        isTrue,
      );
      expect(exceedsUploadLimit(40 * mb, contentType: 'image/tiff'), isFalse);
    });

    test('keeps 15 MB for everything else', () {
      expect(exceedsUploadLimit(15 * mb, contentType: 'image/jpeg'), isFalse);
      expect(
        exceedsUploadLimit(15 * mb + 1, contentType: 'image/jpeg'),
        isTrue,
      );
      expect(exceedsUploadLimit(15 * mb + 1), isTrue);
    });
  });

  group('large files from disk', () {
    late Directory dir;
    late _DiskStore store;
    late List<String> fromFile;
    late List<String> fromBytes;
    late StorageSyncQueue queue;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('crudoc_stream_');
      store = _DiskStore(dir);
      fromFile = [];
      fromBytes = [];
      queue = StorageSyncQueue.forTesting(
        store: store,
        currentDoctorId: () => 'doc-a',
        deleteObject: (_) async {},
        upload: (item, bytes) async {
          fromBytes.add(item.kind.name);
          return StoredFile(
            path: 'doctors/doc-a/b/${item.id}',
            contentType: item.contentType,
            sizeBytes: bytes.length,
          );
        },
        uploadFile: (item, file) async {
          fromFile.add(item.kind.name);
          return StoredFile(
            path: 'doctors/doc-a/f/${item.id}',
            contentType: item.contentType,
            sizeBytes: await file.length(),
          );
        },
      );
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<String> source(String name, int size) async {
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      final raf = await file.open(mode: FileMode.write);
      await raf.truncate(size);
      await raf.close();
      return file.path;
    }

    test(
      'a DICOM original is uploaded straight from its staged file',
      () async {
        final path = await source('ct.dcm', 3 * 1024 * 1024);
        final id = await queue.enqueueFile(
          kind: UploadKind.imagingOriginal,
          sourcePath: path,
          contentType: 'application/dicom',
          patientId: 'p1',
        );
        await queue.processPending();

        expect(fromFile, ['imagingOriginal']);
        expect(fromBytes, isEmpty, reason: 'never loaded into memory');
        final row = await queue.get(id!);
        expect(row?.status, UploadStatus.done);
        expect(row?.resultPath, 'doctors/doc-a/f/$id');
        expect(
          await store.stagedFile(row!),
          isNull,
          reason: 'staged copy removed',
        );
      },
    );

    test(
      'the source file is copied, so the original can be moved away',
      () async {
        final path = await source('ct.dcm', 1024);
        await queue.enqueueFile(
          kind: UploadKind.imagingOriginal,
          sourcePath: path,
          contentType: 'application/dicom',
          patientId: 'p1',
        );
        await File(path).delete();
        await queue.processPending();
        expect(fromFile, ['imagingOriginal']);
      },
    );

    test('smaller kinds queued from a file still upload from bytes', () async {
      final path = await source('scan.pdf', 2048);
      await queue.enqueueFile(
        kind: UploadKind.clinicalLab,
        sourcePath: path,
        contentType: 'application/pdf',
        patientId: 'p1',
      );
      await queue.processPending();
      expect(fromBytes, ['clinicalLab']);
      expect(fromFile, isEmpty);
    });

    test('a DICOM file over 250 MB is refused and nothing is staged', () async {
      final path = await source('huge.dcm', 250 * 1024 * 1024 + 1);
      final id = await queue.enqueueFile(
        kind: UploadKind.imagingOriginal,
        sourcePath: path,
        contentType: 'application/dicom',
        patientId: 'p1',
      );
      expect(id, isNull);
      expect(store.stagedCount, 0);
    });

    test(
      'a staged copy that has gone missing fails without retrying',
      () async {
        final path = await source('ct.dcm', 1024);
        final id = await queue.enqueueFile(
          kind: UploadKind.imagingOriginal,
          sourcePath: path,
          contentType: 'application/dicom',
          patientId: 'p1',
        );
        await store.deleteBytes((await queue.get(id!))!);
        await queue.processPending();
        expect((await queue.get(id))?.status, UploadStatus.failed);
        expect(fromFile, isEmpty);
      },
    );
  });
}

/// An in-memory store whose staged copies are real files in [dir], like
/// the on-device store, so streaming from disk can be checked.
class _DiskStore extends MemoryUploadStore {
  _DiskStore(this.dir);

  final Directory dir;
  final Map<String, File> _files = {};

  int get stagedCount => _files.length;

  @override
  Future<PendingUpload> stageFile(
    PendingUpload upload,
    String sourcePath,
  ) async {
    final copy = await File(
      sourcePath,
    ).copy('${dir.path}${Platform.pathSeparator}staged-${upload.id}');
    _files[upload.id] = copy;
    await save(upload);
    return upload;
  }

  @override
  Future<File?> stagedFile(PendingUpload upload) async {
    final file = _files[upload.id];
    return file != null && await file.exists() ? file : null;
  }

  @override
  Future<Uint8List?> readBytes(PendingUpload upload) async {
    final file = await stagedFile(upload);
    return file == null ? super.readBytes(upload) : file.readAsBytes();
  }

  @override
  Future<void> deleteBytes(PendingUpload upload) async {
    final file = _files.remove(upload.id);
    if (file != null && await file.exists()) await file.delete();
    await super.deleteBytes(upload);
  }
}
