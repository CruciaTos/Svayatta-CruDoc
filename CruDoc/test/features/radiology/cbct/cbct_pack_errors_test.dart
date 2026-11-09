import 'dart:io';
import 'dart:math';

import 'package:dicom_net/dicom_net.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_pack.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/dicom/dicom_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(
    () => dir = Directory.systemTemp.createTempSync('cbct_pack_errors_test'),
  );
  tearDown(() => dir.deleteSync(recursive: true));

  RadStudy synthetic() {
    final images = <RadImageRef>[];
    var n = 0;
    for (final bytes in SyntheticStudies.generate(count: 3)) {
      final d = DicomFile.parse(bytes);
      if (d.string(DicomTag.seriesDescription) != 'CBCT Axial') continue;
      final name = 'slice${n++}.dcm';
      File(p.join(dir.path, name)).writeAsBytesSync(bytes);
      images.add(
        RadImageRef(
          id: name,
          path: name,
          kind: RadFileKind.dicom,
          seriesUid: d.string(DicomTag.seriesInstanceUid) ?? '',
          instanceNumber: d.integer(DicomTag.instanceNumber) ?? 0,
          width: d.columns,
          height: d.rows,
          pixelSpacingMm: 0.4,
          sliceThickness: 0.4,
          position: d.numbers(DicomTag.imagePosition),
          orientation: d.numbers(DicomTag.imageOrientation),
        ),
      );
    }
    images.shuffle(Random(3));
    final now = DateTime(2026, 11, 9);
    return RadStudy(
      id: 's1',
      patientId: 'p1',
      patientName: 'TEST PHANTOM',
      modality: RadModality.cbct,
      studyDate: now,
      receivedAt: now,
      images: images,
      createdAt: now,
      updatedAt: now,
    );
  }

  test(
    'fewer than 16 slices throws CbctPackException containing "too few"',
    () async {
      final s = synthetic();
      final fewImagesStudy = s.copyWith(images: s.images.take(10).toList());

      expect(
        () => ensureCbctPack(study: fewImagesStudy, studyDir: dir),
        throwsA(
          isA<CbctPackException>().having(
            (e) => e.message,
            'message',
            contains('too few'),
          ),
        ),
      );
    },
  );

  test(
    'slices not evenly spaced throws CbctPackException containing "evenly spaced"',
    () async {
      final s = synthetic();
      final badImages = List<RadImageRef>.from(s.images);
      final orig = badImages[5];
      badImages[5] = RadImageRef(
        id: orig.id,
        path: orig.path,
        kind: orig.kind,
        seriesUid: orig.seriesUid,
        seriesDescription: orig.seriesDescription,
        instanceNumber: orig.instanceNumber,
        width: orig.width,
        height: orig.height,
        frames: orig.frames,
        compressed: orig.compressed,
        transferSyntax: orig.transferSyntax,
        pixelSpacingMm: orig.pixelSpacingMm,
        sliceThickness: orig.sliceThickness,
        sliceLocation: orig.sliceLocation,
        dicomModality: orig.dicomModality,
        storagePath: orig.storagePath,
        cloudStatus: orig.cloudStatus,
        position: [
          orig.position![0],
          orig.position![1],
          orig.position![2] + 0.3,
        ],
        orientation: orig.orientation,
      );
      final unevenStudy = s.copyWith(images: badImages);

      expect(
        () => ensureCbctPack(study: unevenStudy, studyDir: dir),
        throwsA(
          isA<CbctPackException>().having(
            (e) => e.message,
            'message',
            contains('evenly spaced'),
          ),
        ),
      );
    },
  );

  test(
    'study with no DICOM images throws CbctPackException containing "no DICOM"',
    () async {
      final s = synthetic();
      final noDicomStudy = s.copyWith(images: const []);

      expect(
        () => ensureCbctPack(study: noDicomStudy, studyDir: dir),
        throwsA(
          isA<CbctPackException>().having(
            (e) => e.message,
            'message',
            contains('no DICOM'),
          ),
        ),
      );
    },
  );
}
