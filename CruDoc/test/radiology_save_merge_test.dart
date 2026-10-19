import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/viewer/annotation_merge.dart';
import 'package:doctor_management_app/features/radiology/viewer/image_look.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/image_filters.dart';

RadAnnotation _a(String id, {double x = 0, String text = ''}) => RadAnnotation(
  id: id,
  kind: RadAnnoKind.length,
  points: [RadPoint(x, 0), RadPoint(x + 10, 0)],
  text: text,
);

List<String> _ids(Map<String, List<RadAnnotation>> m, String image) => [
  for (final a in m[image] ?? const <RadAnnotation>[]) a.id,
];

RadStudy _study(Map<String, dynamic> extras) => RadStudy(
  id: 's1',
  patientId: 'p1',
  patientName: 'Test',
  modality: RadModality.opg,
  studyDate: DateTime(2026),
  receivedAt: DateTime(2026),
  extras: extras,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  group('radMergeAnnotations', () {
    test('keeps what each device added', () {
      final base = {
        'img': [_a('a')],
      };
      final merged = radMergeAnnotations(
        base: base,
        local: {
          'img': [_a('a'), _a('mine')],
        },
        remote: {
          'img': [_a('a'), _a('theirs')],
        },
      );
      expect(_ids(merged, 'img'), ['a', 'mine', 'theirs']);
    });

    test('a deletion here stays deleted', () {
      final merged = radMergeAnnotations(
        base: {
          'img': [_a('a'), _a('b')],
        },
        local: {
          'img': [_a('a')],
        },
        remote: {
          'img': [_a('a'), _a('b')],
        },
      );
      expect(_ids(merged, 'img'), ['a']);
    });

    test('a deletion on the other device is taken when untouched here', () {
      final merged = radMergeAnnotations(
        base: {
          'img': [_a('a'), _a('b')],
        },
        local: {
          'img': [_a('a'), _a('b')],
        },
        remote: {
          'img': [_a('a')],
        },
      );
      expect(_ids(merged, 'img'), ['a']);
    });

    test('an edit here wins over the stored copy', () {
      final merged = radMergeAnnotations(
        base: {
          'img': [_a('a', text: 'old')],
        },
        local: {
          'img': [_a('a', text: 'mine')],
        },
        remote: {
          'img': [_a('a', text: 'theirs')],
        },
      );
      expect(merged['img']!.single.text, 'mine');
    });

    test("the other device's edit is taken when untouched here", () {
      final merged = radMergeAnnotations(
        base: {
          'img': [_a('a', x: 1)],
        },
        local: {
          'img': [_a('a', x: 1)],
        },
        remote: {
          'img': [_a('a', x: 5)],
        },
      );
      expect(merged['img']!.single.points.first.x, 5);
    });

    test('deleted here but changed there: the change is kept', () {
      final merged = radMergeAnnotations(
        base: {
          'img': [_a('a', text: 'old')],
        },
        local: const {},
        remote: {
          'img': [_a('a', text: 'theirs')],
        },
      );
      expect(merged['img']!.single.text, 'theirs');
    });

    test('annotations on another image come through', () {
      final merged = radMergeAnnotations(
        base: const {},
        local: {
          'one': [_a('a')],
        },
        remote: {
          'two': [_a('b')],
        },
      );
      expect(_ids(merged, 'one'), ['a']);
      expect(_ids(merged, 'two'), ['b']);
    });
  });

  test('radMergeCalibration keeps a change here, else the stored one', () {
    final merged = radMergeCalibration(
      base: {'a': 0.1, 'b': 0.1},
      local: {'a': 0.2, 'b': 0.1},
      remote: {'a': 0.3, 'b': 0.4, 'c': 0.5},
    );
    expect(merged, {'a': 0.2, 'b': 0.4, 'c': 0.5});
  });

  group('image looks', () {
    const look = RadImageLook(
      center: 400,
      width: 1200,
      invert: true,
      quarterTurns: 1,
      flipH: true,
      filters: RadFilterSettings(gamma: 1.4, clahe: true),
    );

    test('round-trip through the study extras', () {
      final extras = radExtrasWithLooks({'ceph': 'kept'}, {'img': look});
      final s = _study(extras);
      expect(radLooksOf(s)['img'], look);
      expect(s.extras['ceph'], 'kept');
    });

    test('null removes an image back to how it opens', () {
      final withLook = radExtrasWithLooks(const {}, {'img': look, 'other': look});
      final cleared = radExtrasWithLooks(withLook, {'img': null});
      final looks = radLooksOf(_study(cleared));
      expect(looks.containsKey('img'), isFalse);
      expect(looks['other'], look);
    });

    test('a damaged entry is skipped, not thrown', () {
      final looks = radLooksOf(
        _study({
          RadImageLook.extrasKey: {'img': 'nonsense', 'ok': look.toJson()},
        }),
      );
      expect(looks.keys, ['ok']);
    });
  });
}
