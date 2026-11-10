import 'package:doctor_management_app/features/radiology/cbct/cbct_viewer_screen.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RadImageRef makeImage({
    int frames = 1,
    bool compressed = false,
    String id = 'slice',
    String dicomModality = '',
    int width = 0,
    int height = 0,
  }) {
    return RadImageRef(
      id: id,
      path: '$id.dcm',
      kind: RadFileKind.dicom,
      frames: frames,
      compressed: compressed,
      dicomModality: dicomModality,
      width: width,
      height: height,
    );
  }

  RadStudy makeStudy({
    required RadModality modality,
    required List<RadImageRef> images,
  }) {
    final now = DateTime(2026, 11, 9);
    return RadStudy(
      id: 's_gate',
      patientId: 'p_gate',
      patientName: 'TEST PHANTOM',
      modality: modality,
      studyDate: now,
      receivedAt: now,
      images: images,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('a CBCT study with 40 single-frame uncompressed images is a volume', () {
    final study = makeStudy(
      modality: RadModality.cbct,
      images: List.generate(40, (i) => makeImage(id: 'slice_$i')),
    );
    expect(radIsVolume(study), isTrue);
  });

  test('a CBCT study with one single-frame image is not a volume', () {
    final study = makeStudy(
      modality: RadModality.cbct,
      images: [makeImage(frames: 1, id: 'single_slice')],
    );
    expect(radIsVolume(study), isFalse);
  });

  test('a CBCT study with one multi-frame image (frames: 40) is a volume', () {
    final study = makeStudy(
      modality: RadModality.cbct,
      images: [makeImage(frames: 40, id: 'multiframe_slice')],
    );
    expect(radIsVolume(study), isTrue);
  });

  test('an RadModality.opg study with 40 images is not a volume', () {
    final study = makeStudy(
      modality: RadModality.opg,
      images: List.generate(40, (i) => makeImage(id: 'opg_$i')),
    );
    expect(radIsVolume(study), isFalse);
  });

  // A4: CT / MR studies open in the 3D viewer when they have >= 30 slices.
  test('a CT series (dicomModality=CT) with 30 equal-size slices is a volume', () {
    final study = makeStudy(
      modality: RadModality.other,
      images: List.generate(
        30,
        (i) => makeImage(
          id: 'ct_$i',
          dicomModality: 'CT',
          width: 512,
          height: 512,
        ),
      ),
    );
    expect(radIsVolume(study), isTrue);
  });

  test('a CT series with 29 slices is NOT a volume (too few)', () {
    final study = makeStudy(
      modality: RadModality.other,
      images: List.generate(
        29,
        (i) => makeImage(id: 'ct_$i', dicomModality: 'CT', width: 512, height: 512),
      ),
    );
    expect(radIsVolume(study), isFalse);
  });

  test('an MR series (dicomModality=MR) with 30 slices is a volume', () {
    final study = makeStudy(
      modality: RadModality.other,
      images: List.generate(
        30,
        (i) => makeImage(id: 'mr_$i', dicomModality: 'MR', width: 256, height: 256),
      ),
    );
    expect(radIsVolume(study), isTrue);
  });

  test('a CT series with mixed image sizes is NOT a volume', () {
    final images = [
      ...List.generate(
        29,
        (i) => makeImage(id: 'ct_$i', dicomModality: 'CT', width: 512, height: 512),
      ),
      makeImage(id: 'ct_29', dicomModality: 'CT', width: 256, height: 256),
    ];
    final study = makeStudy(modality: RadModality.other, images: images);
    expect(radIsVolume(study), isFalse);
  });
}
