import 'dart:async';
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
      expect(isUploadableContentType('application/dicom'), isFalse);
      expect(isUploadableContentType('image/tiff'), isFalse);
    });
  });
}
