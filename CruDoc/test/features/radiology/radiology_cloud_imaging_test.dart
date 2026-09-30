import 'dart:io';
import 'dart:typed_data';

import 'package:doctor_management_app/core/services/storage_upload_store.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_cloud_fetch.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_cloud_sync.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  group('RadImageRef', () {
    test('keeps the preview path and SOP Instance UID through JSON', () {
      const ref = RadImageRef(
        id: 'i1',
        path: 'series/1.dcm',
        kind: RadFileKind.dicom,
        storagePath: 'doctors/d/patients/p/clinical/imaging/2026/09/x.dcm',
        previewPath: 'doctors/d/patients/p/clinical/imaging-previews/2026/09/y.jpg',
        sopInstanceUid: '1.2.840.1',
      );
      final back = RadImageRef.fromJson(ref.toJson());
      expect(back.previewPath, ref.previewPath);
      expect(back.sopInstanceUid, '1.2.840.1');
      expect(back.storagePath, ref.storagePath);
    });

    test('reads older records without the new fields', () {
      final back = RadImageRef.fromJson({'id': 'i1', 'path': 'a.jpg'});
      expect(back.previewPath, isEmpty);
      expect(back.sopInstanceUid, isEmpty);
    });

    test('copyWith sets the preview path and keeps the rest', () {
      const ref = RadImageRef(
        id: 'i1',
        path: 'a.dcm',
        kind: RadFileKind.dicom,
        storagePath: 's',
        sopInstanceUid: 'u',
      );
      final next = ref.copyWith(previewPath: 'pv');
      expect(next.previewPath, 'pv');
      expect(next.storagePath, 's');
      expect(next.sopInstanceUid, 'u');
    });
  });

  group('RadiologyCloudSync.kindFor', () {
    test('sends DICOM and TIFF to imaging, pictures to x-rays', () {
      expect(RadiologyCloudSync.kindFor('application/dicom'), UploadKind.imagingOriginal);
      expect(RadiologyCloudSync.kindFor('image/tiff'), UploadKind.imagingOriginal);
      expect(RadiologyCloudSync.kindFor('image/jpeg'), UploadKind.clinicalXray);
    });
  });

  group('renderRadPreviewJpeg', () {
    test('shrinks a large picture to a small JPEG', () {
      final source = img.Image(width: 2000, height: 1000);
      img.fill(source, color: img.ColorRgb8(120, 120, 120));
      final jpeg = renderRadPreviewJpeg(img.encodePng(source), RadFileKind.raster);
      expect(jpeg, isNotNull);
      final decoded = img.decodeJpg(jpeg!)!;
      expect(decoded.width, lessThanOrEqualTo(radPreviewMaxEdge));
      expect(decoded.height, lessThanOrEqualTo(radPreviewMaxEdge));
    });

    test('returns null for bytes it cannot decode', () {
      expect(renderRadPreviewJpeg(Uint8List.fromList([1, 2, 3]), RadFileKind.dicom), isNull);
    });
  });

  group('RadCloudFetch', () {
    late Directory tmp;

    setUp(() async => tmp = await Directory.systemTemp.createTemp('radfetch'));
    tearDown(() async => tmp.delete(recursive: true));

    test('downloads once, into nested folders, and reuses the file', () async {
      var calls = 0;
      final fetch = RadCloudFetch(
        download: (path, dest) async {
          calls++;
          await dest.writeAsString('data');
        },
      );
      final dest = File(p.join(tmp.path, 'study', 'series', 'a.dcm'));
      final results = await Future.wait([
        fetch.fetch('x', dest),
        fetch.fetch('x', dest),
      ]);
      expect(calls, 1);
      expect(results.first.path, dest.path);
      expect(await dest.readAsString(), 'data');
      await fetch.fetch('x', dest);
      expect(calls, 1);
    });

    test('leaves nothing behind when the download fails', () async {
      final fetch = RadCloudFetch(
        download: (path, dest) async {
          await dest.writeAsString('half');
          throw const SocketException('offline');
        },
      );
      final dest = File(p.join(tmp.path, 'a.dcm'));
      await expectLater(fetch.fetch('x', dest), throwsA(isA<SocketException>()));
      expect(await dest.exists(), isFalse);
      expect(await File('${dest.path}.part').exists(), isFalse);
    });
  });
}
