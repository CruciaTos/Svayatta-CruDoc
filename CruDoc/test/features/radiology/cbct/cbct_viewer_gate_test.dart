import 'package:doctor_management_app/features/radiology/cbct/cbct_viewer_screen.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RadImageRef makeImage({
    int frames = 1,
    bool compressed = false,
    String id = 'slice',
  }) {
    return RadImageRef(
      id: id,
      path: '$id.dcm',
      kind: RadFileKind.dicom,
      frames: frames,
      compressed: compressed,
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
}
