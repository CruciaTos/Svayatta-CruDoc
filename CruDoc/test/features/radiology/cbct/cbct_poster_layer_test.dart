import 'dart:io';
import 'dart:math';

import 'package:dicom_net/dicom_net.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_pack.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_poster_layer.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/dicom/dicom_file.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(
    () => dir = Directory.systemTemp.createTempSync('cbct_poster_layer_test'),
  );
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

  testWidgets('CbctPosterLayer renders 4 posters, then fades out', (
    tester,
  ) async {
    CbctPack? pack;
    await tester.runAsync(() async {
      final study = synthetic();
      pack = await ensureCbctPack(study: study, studyDir: dir);
    });
    expect(pack, isNotNull);

    Widget buildLayer({required bool visible}) {
      return MaterialApp(
        theme: CruTheme.of(CruAppearance.day),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: CbctPosterLayer(
              packDir: pack!.dir,
              meta: pack!.meta,
              visible: visible,
              background: null,
            ),
          ),
        ),
      );
    }

    // 1. Pump with visible: true inside MaterialApp and SizedBox(width: 800, height: 600)
    await tester.pumpWidget(buildLayer(visible: true));
    await tester.pump();

    // Expect four Image widgets (one per view)
    expect(find.byType(Image), findsNWidgets(4));

    // Expect the layer is visible (opacity 1)
    final initialOpacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(CbctPosterLayer),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(initialOpacity.opacity, 1.0);
    final initialIgnorePointer = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(CbctPosterLayer),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(initialIgnorePointer.ignoring, isFalse);

    // 2. Pump again with visible: false, wait 300 ms, and expect faded out (opacity 0, ignoring pointers)
    await tester.pumpWidget(buildLayer(visible: false));
    await tester.pump(const Duration(milliseconds: 300));

    final fadedOpacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(CbctPosterLayer),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(fadedOpacity.opacity, 0.0);
    final fadedIgnorePointer = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(CbctPosterLayer),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(fadedIgnorePointer.ignoring, isTrue);
  });
}
