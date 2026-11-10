import 'dart:io';
import 'dart:math';

import 'package:dicom_net/dicom_net.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_pack.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/dicom/dicom_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('cbct_pack_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  RadStudy synthetic() {
    final images = <RadImageRef>[];
    var n = 0;
    // generate(count: 3) makes a panoramic, an intraoral and a 96x96x40 CBCT.
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
    images.shuffle(Random(3)); // the packer must sort them itself
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

  test('packs a shuffled synthetic CBCT into the volume the viewer reads', () async {
    final study = synthetic();
    expect(study.images.length, 40);

    final pack = await ensureCbctPack(study: study, studyDir: dir);
    final g = pack.meta['geometry'] as Map<String, dynamic>;
    expect(g['dims'], [96, 96, 40]);
    expect(
      (g['spacing'] as List).map((e) => (e as num).toDouble()),
      everyElement(closeTo(0.4, 1e-9)),
    );
    expect(g['origin'], [0.0, 0.0, 0.0]);
    expect(g['direction'], [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]);

    final bytes = File(p.join(pack.dir.path, 'full.i16')).readAsBytesSync();
    expect(bytes.length, 96 * 96 * 40 * 2);
    final v = bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2);
    // Corner voxel is air (-1000 plus up to 40 of noise).
    expect(v[0], inInclusiveRange(-1000, -955));
    // x=48, y=33, z=20 is inside the bony arch (1200 plus noise): slices came
    // out in order and rows/columns are the right way round.
    expect(v[(20 * 96 + 33) * 96 + 48], inInclusiveRange(1190, 1250));

    final lm = pack.meta['landmarks'] as Map<String, dynamic>;
    expect(lm['air'], inInclusiveRange(-1000, -900));
    expect(lm['soft'], inInclusiveRange(0, 150));
    expect(lm['teeth'], inInclusiveRange(1000, 1300));
    expect(lm['bone'], inInclusiveRange(lm['soft'] as num, lm['teeth'] as num));

    // A second call finds the finished pack and does not build again.
    final again = await ensureCbctPack(study: study, studyDir: dir);
    expect(again.meta['createdAt'], pack.meta['createdAt']);
  });

  test('synthetic CBCT pack has kind == dental (no modality tag in synthetic slices)', () async {
    final pack = await ensureCbctPack(study: synthetic(), studyDir: dir);
    // Synthetic slices carry no Modality DICOM tag, so the packer falls back to dental.
    expect(pack.meta['kind'], 'dental');
  });

  test('writes a preview volume and four posters, axial with anterior on top', () async {
    final pack = await ensureCbctPack(study: synthetic(), studyDir: dir);
    expect(cbctPackVersion, 4);
    final vols = pack.meta['volumes'] as Map<String, dynamic>;
    expect(vols['mid'], isNull); // 96 voxels: no mid volume
    final lods = vols['lods'] as List;
    expect(lods.length, 2);
    expect(lods[0]['dims'], [48, 48, 20]);
    expect(lods[0]['file'], 'preview.i16');
    expect(lods[1]['dims'], [96, 96, 40]);
    expect(lods[1]['file'], 'full.i16');
    final pv = vols['preview'] as Map<String, dynamic>;
    final f = pv['factor'] as int;
    expect(f, 2);
    expect(pv['dims'], [(96 / f).ceil(), (96 / f).ceil(), (40 / f).ceil()]);
    expect(
      (pv['spacing'] as List).map((e) => (e as num).toDouble()),
      everyElement(closeTo(0.8, 1e-9)),
    );
    // The first preview voxel sits half a full voxel along each axis.
    expect(
      (pv['origin'] as List).map((e) => (e as num).toDouble()),
      everyElement(closeTo(0.2, 1e-9)),
    );
    final previewBytes = File(p.join(pack.dir.path, pv['file'] as String)).lengthSync();
    expect(previewBytes, 48 * 48 * 20 * 2);

    final names = (pack.meta['posters'] as Map).cast<String, String>();
    expect(names.keys, containsAll(['axial', 'coronal', 'sagittal', 'threeD']));
    for (final n in names.values) {
      final bytes = File(p.join(pack.dir.path, n)).readAsBytesSync();
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: n);
      final im = img.decodePng(bytes)!;
      expect(im.width > im.height ? im.width : im.height, lessThanOrEqualTo(1024));
    }

    // The bony arch has its apex at low y and is open toward +y: on the
    // axial poster the apex is near the top and the opening at the bottom.
    final axial = img.decodePng(File(p.join(pack.dir.path, 'poster_axial.png')).readAsBytesSync())!;
    num at(double fx, double fy) =>
        axial.getPixel((fx * axial.width).floor(), (fy * axial.height).floor()).r;
    expect(at(0.5, 33.5 / 96), greaterThan(at(0.5, 62.5 / 96) + 60));
  });
}
