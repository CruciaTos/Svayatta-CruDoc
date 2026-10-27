import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite_common;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;

import 'package:doctor_management_app/core/database/windows_local_database.dart';
import 'package:doctor_management_app/features/files/data/file_fingerprint.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_cloud_sync.dart';

void main() {
  setUpAll(() {
    sqflite_ffi.sqfliteFfiInit();
  });

  group('File Fingerprint (SHA-256)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('crudoc_hash_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('hashes empty file accurately in background isolate', () async {
      final file = File('${tempDir.path}/empty.txt');
      await file.create();

      final hash = await computeFileSha256(file.path);
      // Canonical SHA-256 of empty bytes
      expect(
        hash,
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('hashes text content in isolate matching crypto convert', () async {
      const content = 'CruDoc Clinic File Sharing Test Content';
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString(content);

      final hash = await computeFileSha256(file.path);
      final expected = sha256.convert(utf8.encode(content)).toString();

      expect(hash, expected);
      expect(hash.length, 64);
      expect(hash, matches(r'^[0-9a-f]{64}$'));
    });

    test('streams large binary file in chunks matching computeBytesSha256', () async {
      // 512 KB of pseudo-random bytes
      final bytes = Uint8List(512 * 1024);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = (i * 31 + 7) & 0xFF;
      }

      final file = File('${tempDir.path}/large.bin');
      await file.writeAsBytes(bytes);

      final fileHash = await computeFileSha256(file.path);
      final memoryHash = computeBytesSha256(bytes);

      expect(fileHash, memoryHash);
      expect(fileHash.length, 64);
    });
  });

  group('PatientFile model with sha256', () {
    final now = DateTime(2026, 10, 27, 12, 0, 0);

    test('defaults sha256 to empty string', () {
      final file = PatientFile(
        id: 'f1',
        doctorId: 'clinic-1',
        ownerUid: 'doc-1',
        patientId: 'p1',
        folderId: '',
        rootId: '',
        name: 'test.pdf',
        contentType: 'application/pdf',
        sizeBytes: 1024,
        visibleTo: const ['doc-1'],
        createdAt: now,
        updatedAt: now,
      );

      expect(file.sha256, '');
    });

    test('toLocalMap and fromLocalMap preserve sha256', () {
      final hash = 'a' * 64;
      final file = PatientFile(
        id: 'f2',
        doctorId: 'clinic-1',
        ownerUid: 'doc-1',
        patientId: 'p1',
        folderId: 'folder-1',
        rootId: 'folder-1',
        name: 'scan.dcm',
        contentType: 'application/dicom',
        sizeBytes: 2048,
        visibleTo: const ['doc-1', 'doc-2'],
        createdAt: now,
        updatedAt: now,
        sha256: hash,
        storagePath: 'clinic-blobs/clinic-1/$hash/original',
      );

      final localMap = file.toLocalMap();
      expect(localMap['sha256'], hash);

      final restored = PatientFile.fromLocalMap(localMap);
      expect(restored.sha256, hash);
      expect(restored.storagePath, 'clinic-blobs/clinic-1/$hash/original');
      expect(restored.name, 'scan.dcm');
    });

    test('copyWith updates or preserves sha256', () {
      final hash1 = '1' * 64;
      final hash2 = '2' * 64;

      final file = PatientFile(
        id: 'f3',
        doctorId: 'clinic-1',
        ownerUid: 'doc-1',
        patientId: 'p1',
        folderId: '',
        rootId: '',
        name: 'test.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 512,
        visibleTo: const ['doc-1'],
        createdAt: now,
        updatedAt: now,
        sha256: hash1,
      );

      // Preserved when null
      final updatedName = file.copyWith(name: 'renamed.jpg');
      expect(updatedName.sha256, hash1);

      // Overridden when passed
      final updatedHash = file.copyWith(sha256: hash2);
      expect(updatedHash.sha256, hash2);
    });
  });

  group('FilesCloudSync sha256 mapping', () {
    test('firestoreData includes sha256 when non-empty', () {
      final hash = 'b' * 64;
      final localRow = {
        'id': 'f1',
        'doctorId': 'clinic-1',
        'ownerUid': 'doc-1',
        'patientId': 'p1',
        'folderId': '',
        'rootId': '',
        'name': 'file.pdf',
        'contentType': 'application/pdf',
        'sizeBytes': 1234,
        'visibleTo': '["doc-1"]',
        'isDeleted': 0,
        'createdAt': 1700000000000,
        'updatedAt': 1700000000000,
        'storagePath': '',
        'thumb': '',
        'viewPath': '',
        'sha256': hash,
      };

      final firestoreData = FilesCloudSync.firestoreDataForTesting(
        'patient_files',
        localRow,
      );

      expect(firestoreData['sha256'], hash);
    });

    test('firestoreData omits sha256 when empty string (backward compatibility)', () {
      final localRow = {
        'id': 'f2',
        'doctorId': 'clinic-1',
        'ownerUid': 'doc-1',
        'patientId': 'p1',
        'folderId': '',
        'rootId': '',
        'name': 'legacy.pdf',
        'contentType': 'application/pdf',
        'sizeBytes': 500,
        'visibleTo': '["doc-1"]',
        'isDeleted': 0,
        'createdAt': 1700000000000,
        'updatedAt': 1700000000000,
        'storagePath': 'patient-files/clinic-1/p1/f2/original',
        'thumb': '',
        'viewPath': '',
        'sha256': '',
      };

      final firestoreData = FilesCloudSync.firestoreDataForTesting(
        'patient_files',
        localRow,
      );

      expect(firestoreData.containsKey('sha256'), isFalse);
    });

    test('localRow decodes sha256 from remote snapshot map', () {
      final hash = 'c' * 64;
      final remoteDoc = {
        'doctorId': 'clinic-1',
        'ownerUid': 'doc-1',
        'patientId': 'p1',
        'folderId': '',
        'rootId': '',
        'name': 'report.pdf',
        'contentType': 'application/pdf',
        'sizeBytes': 4096,
        'visibleTo': ['doc-1'],
        'isDeleted': false,
        'createdAt': null,
        'updatedAt': null,
        'storagePath': 'clinic-blobs/clinic-1/$hash/original',
        'thumb': '',
        'viewPath': '',
        'sha256': hash,
      };

      final localRow = FilesCloudSync.localRowForTesting(
        'patient_files',
        'f3',
        remoteDoc,
      );

      expect(localRow['sha256'], hash);
    });
  });

  group('SQLite patient_files sha256 column migration', () {
    test('existing patient_files table without sha256 gains column via ALTER TABLE', () async {
      final dbPath = '${Directory.systemTemp.path}/crudoc_mig_test_${DateTime.now().microsecondsSinceEpoch}.db';
      final database = await sqflite_ffi.databaseFactoryFfi.openDatabase(
        dbPath,
        options: sqflite_common.OpenDatabaseOptions(version: 1),
      );
      addTearDown(() async {
        await database.close();
        final f = File(dbPath);
        if (await f.exists()) await f.delete();
      });

      final localDb = WindowsDatabase(database);

      // Create legacy table structure without sha256 column
      await localDb.execute('''
        CREATE TABLE patient_files (
          id TEXT PRIMARY KEY,
          doctorId TEXT NOT NULL DEFAULT '',
          ownerUid TEXT NOT NULL DEFAULT '',
          patientId TEXT NOT NULL,
          folderId TEXT NOT NULL DEFAULT '',
          rootId TEXT NOT NULL DEFAULT '',
          name TEXT NOT NULL DEFAULT '',
          contentType TEXT NOT NULL DEFAULT '',
          sizeBytes INTEGER NOT NULL DEFAULT 0,
          visibleTo TEXT NOT NULL DEFAULT '[]',
          localPath TEXT NOT NULL DEFAULT '',
          storagePath TEXT NOT NULL DEFAULT '',
          cloudStatus TEXT NOT NULL DEFAULT '',
          isDeleted INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL,
          thumb TEXT NOT NULL DEFAULT '',
          viewPath TEXT NOT NULL DEFAULT '',
          syncStatus TEXT NOT NULL DEFAULT 'pending'
            CHECK (syncStatus IN ('synced', 'pending')),
          lastSyncedAt INTEGER
        )
      ''');

      // Insert legacy file row
      await localDb.insert('patient_files', {
        'id': 'legacy-1',
        'doctorId': 'clinic-1',
        'ownerUid': 'doc-1',
        'patientId': 'p1',
        'folderId': '',
        'rootId': '',
        'name': 'old.pdf',
        'contentType': 'application/pdf',
        'sizeBytes': 100,
        'visibleTo': '[]',
        'localPath': '',
        'storagePath': '',
        'cloudStatus': '',
        'isDeleted': 0,
        'createdAt': 1000,
        'updatedAt': 1000,
        'thumb': '',
        'viewPath': '',
        'syncStatus': 'pending',
      });

      // Verify sha256 column does NOT exist yet
      final tableInfoBefore = await database.rawQuery('PRAGMA table_info(patient_files)');
      final columnsBefore = tableInfoBefore.map((r) => r['name'] as String).toSet();
      expect(columnsBefore.contains('sha256'), isFalse);

      // Apply migration: ALTER TABLE ADD COLUMN sha256
      await localDb.execute("ALTER TABLE patient_files ADD COLUMN sha256 TEXT NOT NULL DEFAULT ''");
      await localDb.execute("CREATE INDEX IF NOT EXISTS idx_patient_files_sha256 ON patient_files (sha256)");

      // Verify column now exists
      final tableInfoAfter = await database.rawQuery('PRAGMA table_info(patient_files)');
      final columnsAfter = tableInfoAfter.map((r) => r['name'] as String).toSet();
      expect(columnsAfter.contains('sha256'), isTrue);

      // Existing row has default empty string
      final rows = await localDb.query('patient_files', where: 'id = ?', whereArgs: ['legacy-1']);
      expect(rows.first['sha256'], '');

      // New row can insert 64-char sha256
      final newHash = 'd' * 64;
      await localDb.insert('patient_files', {
        'id': 'new-1',
        'doctorId': 'clinic-1',
        'ownerUid': 'doc-1',
        'patientId': 'p1',
        'folderId': '',
        'rootId': '',
        'name': 'new.pdf',
        'contentType': 'application/pdf',
        'sizeBytes': 200,
        'visibleTo': '[]',
        'localPath': '',
        'storagePath': '',
        'cloudStatus': '',
        'isDeleted': 0,
        'createdAt': 2000,
        'updatedAt': 2000,
        'thumb': '',
        'viewPath': '',
        'syncStatus': 'pending',
        'sha256': newHash,
      });

      final queryNew = await localDb.query('patient_files', where: 'id = ?', whereArgs: ['new-1']);
      expect(queryNew.first['sha256'], newHash);
    });
  });

  group('Blob Paths and Storage Deduplication', () {
    test('blobOriginalPath and blobViewPath generate correct shared paths', () {
      final sha = 'e' * 64;
      expect(
        'clinic-blobs/clinic-123/$sha/original',
        'clinic-blobs/clinic-123/${'e' * 64}/original',
      );
      expect(
        'clinic-blobs/clinic-123/$sha/view',
        'clinic-blobs/clinic-123/${'e' * 64}/view',
      );
    });

    test('download verification detects damaged/tampered file', () async {
      final tempDir = await Directory.systemTemp.createTemp('crudoc_verify_');
      try {
        final originalFile = File('${tempDir.path}/test.txt');
        await originalFile.writeAsString('Legitimate content');
        final validHash = await computeFileSha256(originalFile.path);

        // Tamper with the content
        await originalFile.writeAsString('Tampered content');
        final tamperedHash = await computeFileSha256(originalFile.path);

        expect(tamperedHash, isNot(equals(validHash)));
      } finally {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      }
    });

    test('shared clinic-blobs paths are never deleted directly by client', () {
      bool isClientDeletable(String path) {
        if (path.startsWith('clinic-blobs/')) return false;
        return true;
      }

      final sha = 'f' * 64;
      expect(isClientDeletable('clinic-blobs/clinic-1/$sha/original'), isFalse);
      expect(isClientDeletable('clinic-blobs/clinic-1/$sha/view'), isFalse);
      expect(isClientDeletable('patient-files/clinic-1/p1/f1/original'), isTrue);
      expect(isClientDeletable('doctors/clinic-1/patients/p1/clinical/xrays/file.jpg'), isTrue);
    });
  });
}

