import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/outcome_scale.dart';
import 'package:doctor_management_app/features/therapy/data/outcome_scale_registry.dart';
import 'package:doctor_management_app/features/therapy/data/scales/measured_scales.dart';
import 'package:doctor_management_app/features/therapy/domain/outcome_score_models.dart';

/// Outcome scores leave the clinic on a report another clinician or an
/// insurer may read, so these tests are mostly about what the app refuses to
/// say: no figure from a half-finished questionnaire, no improvement claimed
/// from a change inside measurement error, and no claim at all where the
/// instrument has no error figure to judge against.
///
/// The questionnaire used here is invented. Real instruments are licensed
/// text held in `assets/outcome_scales/`, and the scoring rules are better
/// tested against a fixture whose every value is known anyway.
void main() {
  /// Four items, 0–4 each: max 16 raw, and three answers needed.
  const fixture = ScaleDef(
    id: 'fix',
    name: 'Fixture Disability Index',
    short: 'FDI',
    region: 'Test',
    kind: ScaleKind.questionnaire,
    unit: '%',
    higherIsBetter: false,
    source: 'invented for tests',
    mdc: 10,
    minAnswered: 3,
    bands: [
      ScaleBand(0, 20, 'Minimal'),
      ScaleBand(21, 60, 'Moderate'),
      ScaleBand(61, 100, 'Severe'),
    ],
    items: [
      ScaleItem('a', 'A', ['0', '1', '2', '3', '4']),
      ScaleItem('b', 'B', ['0', '1', '2', '3', '4']),
      ScaleItem('c', 'C', ['0', '1', '2', '3', '4']),
      ScaleItem('d', 'D', ['0', '1', '2', '3', '4']),
    ],
  );

  DentalRecord rec(
    Map<String, int> answers, {
    String scaleId = 'fix',
    double? value,
    DateTime? at,
  }) => DentalRecord.create(
    'p1',
    RecKind.physioScaleScore,
    OutcomeScore.toData(
      scaleId: scaleId,
      answers: answers,
      value: value,
      note: '',
    ),
    at: at ?? DateTime(2026, 11, 1),
  );

  ScaleResult result(Map<String, int> answers, {DateTime? at}) =>
      OutcomeScore.fromRecord(rec(answers, at: at)).scoreWith(fixture);

  group('scoring', () {
    test('a full questionnaire is a percentage of the maximum', () {
      // 2+2+2+2 = 8 of 16.
      final r = result({'a': 2, 'b': 2, 'c': 2, 'd': 2});
      expect(r.answered, 4);
      expect(r.raw, 8);
      expect(r.maxRaw, 16);
      expect(r.rounded, 50);
      expect(r.display, '50%');
      expect(r.band?.label, 'Moderate');
    });

    test('a skipped item lowers the denominator, not the score', () {
      // 4+4+4 = 12 of 12 → 100%, not 12 of 16 → 75%.
      final r = result({'a': 4, 'b': 4, 'c': 4});
      expect(r.answered, 3);
      expect(r.maxRaw, 12);
      expect(r.rounded, 100);
      expect(r.line, contains('scored over 3 of 4'));
    });

    test('an unanswered item is never read as a zero', () {
      final skipped = result({'a': 0, 'b': 0, 'c': 0});
      final zeroed = result({'a': 0, 'b': 0, 'c': 0, 'd': 0});
      expect(skipped.maxRaw, 12);
      expect(zeroed.maxRaw, 16);
      // Both are 0%, but they are not the same measurement.
      expect(skipped.answered, isNot(zeroed.answered));
    });

    test('too few answers reports no figure at all', () {
      final r = result({'a': 4, 'b': 4});
      expect(r.isReportable, isFalse);
      expect(r.figure, isNull);
      expect(r.display, isNull);
      expect(r.rounded, isNull);
      expect(r.band, isNull);
      expect(r.stillNeeded, 1);
      expect(r.line, 'Incomplete — 2 of 4 answered');
    });

    test('an option index from another version is dropped, not clamped', () {
      // 9 is not a valid option, so item d does not count at all.
      final r = result({'a': 2, 'b': 2, 'c': 2, 'd': 9});
      expect(r.answered, 3);
      expect(r.raw, 6);
      expect(r.maxRaw, 12);
      expect(r.rounded, 50);
    });

    test('a negative index is dropped too', () {
      final r = result({'a': 2, 'b': 2, 'c': 2, 'd': -1});
      expect(r.answered, 3);
      expect(r.raw, 6);
    });

    test('every reachable figure falls in exactly one band', () {
      for (var raw = 0; raw <= 16; raw++) {
        final f = raw * 100 / 16;
        final hits = [
          for (final b in fixture.bands)
            if (b.contains(f.round())) b,
        ];
        expect(hits.length, 1, reason: 'raw $raw → ${f.round()}%');
      }
    });
  });

  group('measured scales', () {
    ScaleResult measured(ScaleDef s, double? v) => OutcomeScore.fromRecord(
      rec(const {}, scaleId: s.id, value: v),
    ).scoreWith(s);

    test('a time is reported with its unit', () {
      final r = measured(kTugScale, 13.4);
      expect(r.isReportable, isTrue);
      expect(r.display, '13 s');
      // No bands: falls-risk cut-offs depend on the population.
      expect(r.band, isNull);
    });

    test('a distance is reported with its unit', () {
      expect(measured(kSixMinuteWalkScale, 420).display, '420 m');
    });

    test('no figure recorded reports nothing', () {
      final r = measured(kTugScale, null);
      expect(r.isReportable, isFalse);
      expect(r.line, 'Not recorded');
    });

    test('a null value is left out of the record entirely', () {
      final data = OutcomeScore.toData(
        scaleId: 'tug',
        answers: const {},
        value: null,
        note: '',
      );
      expect(data.containsKey('value'), isFalse);
    });
  });

  group('change over time', () {
    List<ScaleResult> trend(List<DentalRecord> recs) =>
        scaleTrend(fixture, recs);

    test('the trend is oldest first, whatever order the records arrive', () {
      final t = trend([
        rec({'a': 1, 'b': 1, 'c': 1, 'd': 1}, at: DateTime(2026, 11, 20)),
        rec({'a': 3, 'b': 3, 'c': 3, 'd': 3}, at: DateTime(2026, 10, 1)),
      ]);
      expect(t.first.rounded, 75);
      expect(t.last.rounded, 25);
    });

    test('a fall on a disability index is an improvement', () {
      final c = scaleChange(
        trend([
          rec({'a': 3, 'b': 3, 'c': 3, 'd': 3}, at: DateTime(2026, 10, 1)),
          rec({'a': 1, 'b': 1, 'c': 1, 'd': 1}, at: DateTime(2026, 11, 12)),
        ]),
      )!;
      expect(c.improved, isTrue);
      expect(c.size, 50);
      expect(c.weeks, 6);
      expect(c.beyondMdc, isTrue);
      expect(
        c.reportLine,
        'FDI down 50 points over 6 weeks, from 75% to 25%, beyond the 10 '
        'points minimal detectable change',
      );
    });

    test('a change inside the error figure is not called an improvement', () {
      // 50% → 44%: a 6 point move against a 10 point MDC.
      final c = scaleChange(
        trend([
          rec({'a': 2, 'b': 2, 'c': 2, 'd': 2}, at: DateTime(2026, 10, 1)),
          rec({'a': 2, 'b': 2, 'c': 2, 'd': 1}, at: DateTime(2026, 10, 15)),
        ]),
      )!;
      expect(c.beyondMdc, isFalse);
      expect(c.reportLine, contains('within the 10 points measurement error'));
    });

    test('no claim either way when the scale has no error figure', () {
      final t = [
        OutcomeScore.fromRecord(
          rec(const {}, scaleId: 'tug', value: 20, at: DateTime(2026, 10, 1)),
        ).scoreWith(kTugScale),
        OutcomeScore.fromRecord(
          rec(const {}, scaleId: 'tug', value: 14, at: DateTime(2026, 11, 5)),
        ).scoreWith(kTugScale),
      ];
      final c = scaleChange(t)!;
      expect(c.mdcKnown, isFalse);
      expect(c.beyondMdc, isFalse);
      expect(c.improved, isTrue, reason: 'a quicker TUG is better');
      expect(c.reportLine, isNot(contains('detectable')));
      expect(c.reportLine, isNot(contains('error')));
    });

    test('a rise on a walk distance is the improvement', () {
      final t = [
        OutcomeScore.fromRecord(
          rec(
            const {},
            scaleId: 'sixmwt',
            value: 300,
            at: DateTime(2026, 10, 1),
          ),
        ).scoreWith(kSixMinuteWalkScale),
        OutcomeScore.fromRecord(
          rec(
            const {},
            scaleId: 'sixmwt',
            value: 420,
            at: DateTime(2026, 11, 1),
          ),
        ).scoreWith(kSixMinuteWalkScale),
      ];
      expect(scaleChange(t)!.improved, isTrue);
    });

    test('no change reads as unchanged rather than as a direction', () {
      final c = scaleChange(
        trend([
          rec({'a': 2, 'b': 2, 'c': 2, 'd': 2}, at: DateTime(2026, 10, 1)),
          rec({'a': 2, 'b': 2, 'c': 2, 'd': 2}, at: DateTime(2026, 11, 5)),
        ]),
      )!;
      expect(c.size, 0);
      expect(c.reportLine, contains('unchanged at 50%'));
    });

    test('two half-finished questionnaires are not a trend', () {
      final c = scaleChange(
        trend([
          rec({'a': 2}, at: DateTime(2026, 10, 1)),
          rec({'a': 1, 'b': 1}, at: DateTime(2026, 11, 1)),
        ]),
      );
      expect(c, isNull);
    });

    test('an incomplete taking is skipped, not compared', () {
      final t = trend([
        rec({'a': 3, 'b': 3, 'c': 3, 'd': 3}, at: DateTime(2026, 10, 1)),
        rec({'a': 1}, at: DateTime(2026, 10, 20)),
        rec({'a': 1, 'b': 1, 'c': 1, 'd': 1}, at: DateTime(2026, 11, 12)),
      ]);
      expect(t.length, 3);
      expect(latestResult(t)!.rounded, 25);
      expect(scaleChange(t)!.size, 50);
    });

    test('records of another scale are not mixed in', () {
      final t = scaleTrend(fixture, [
        rec({'a': 2, 'b': 2, 'c': 2, 'd': 2}),
        rec(const {}, scaleId: 'tug', value: 12),
      ]);
      expect(t.length, 1);
    });
  });

  group('loading from assets', () {
    /// A bundle holding exactly what the test puts in it.
    AssetBundle bundleOf(Map<String, String> files) {
      return _MapBundle(files);
    }

    Map<String, dynamic> validJson() => {
      'id': 'x',
      'name': 'Example',
      'short': 'X',
      'region': 'Test',
      'kind': 'questionnaire',
      'unit': '%',
      'higherIsBetter': false,
      'source': 'test',
      'minAnswered': 1,
      'items': [
        {
          'id': 'i1',
          'label': 'One',
          'options': ['no', 'yes'],
        },
        {
          'id': 'i2',
          'label': 'Two',
          'options': ['no', 'yes'],
        },
      ],
    };

    Future<ScaleLoad> loadOne(Object json) => loadOutcomeScales(
      bundle: bundleOf({'x.json': jsonEncode(json)}),
      assets: ['x.json'],
    );

    test('the built-in measures are always there', () async {
      final load = await loadOutcomeScales(
        bundle: bundleOf(const {}),
        assets: const [],
      );
      expect(load.byId('tug'), isNotNull);
      expect(load.byId('sixmwt'), isNotNull);
      expect(load.problems, isEmpty);
    });

    test('a valid file loads', () async {
      final load = await loadOne(validJson());
      expect(load.problems, isEmpty);
      expect(load.byId('x')!.items.length, 2);
    });

    test('a missing file is reported, not swallowed', () async {
      final load = await loadOutcomeScales(
        bundle: bundleOf(const {}),
        assets: ['gone.json'],
      );
      expect(load.byId('gone'), isNull);
      expect(load.problems.single, contains('gone.json'));
      // The built-ins still load, so one bad file does not lose the rest.
      expect(load.byId('tug'), isNotNull);
    });

    test('items that do not all score alike are refused', () async {
      final json = validJson();
      (json['items'] as List)[1] = {
        'id': 'i2',
        'label': 'Two',
        'options': ['a', 'b', 'c'],
      };
      final load = await loadOne(json);
      expect(load.byId('x'), isNull);
      expect(load.problems.single, contains('must score alike'));
    });

    test('a duplicate item id is refused', () async {
      final json = validJson();
      (json['items'] as List)[1] = {
        'id': 'i1',
        'label': 'Two',
        'options': ['no', 'yes'],
      };
      expect((await loadOne(json)).problems.single, contains('twice'));
    });

    test('a questionnaire with no items is refused', () async {
      final json = validJson()..['items'] = <Object>[];
      expect(
        (await loadOne(json)).problems.single,
        contains('cannot be scored'),
      );
    });

    test('minAnswered beyond the item count is refused', () async {
      final json = validJson()..['minAnswered'] = 5;
      expect((await loadOne(json)).problems.single, contains('minAnswered'));
    });

    test('a missing higherIsBetter is refused rather than assumed', () async {
      // Guessing the direction would decide whether a falling score reads as
      // recovery or decline.
      final json = validJson()..remove('higherIsBetter');
      expect((await loadOne(json)).problems.single, contains('higherIsBetter'));
    });

    test('a file that clashes with a built-in id is skipped', () async {
      final json = validJson()..['id'] = 'tug';
      final load = await loadOne(json);
      expect(load.problems.single, contains('already'));
      // The built-in survives rather than being replaced.
      expect(load.byId('tug')!.kind, ScaleKind.measured);
    });

    test('malformed JSON is reported with its file name', () async {
      final load = await loadOutcomeScales(
        bundle: bundleOf({'x.json': '{not json'}),
        assets: ['x.json'],
      );
      expect(load.problems.single, contains('x.json'));
    });
  });

  group('the shipped ODI asset', () {
    test('parses, and scores the way the instrument says', () async {
      // Reads the real asset off disk rather than through the bundle, so
      // this fails if the file is edited into an unscoreable state.
      final load = await loadOutcomeScales(
        bundle: _FileBundle(),
        assets: ['assets/outcome_scales/odi.json'],
      );
      expect(load.problems, isEmpty, reason: load.problems.join('; '));
      final odi = load.byId('odi')!;
      expect(odi.items.length, 10);
      expect(odi.maxRaw, 50);
      expect(odi.unit, '%');
      expect(odi.higherIsBetter, isFalse);
      // Every section answered at 1 of 5 → 10 of 50.
      final r = OutcomeScore.fromRecord(
        rec({for (final i in odi.items) i.id: 1}, scaleId: 'odi'),
      ).scoreWith(odi);
      expect(r.rounded, 20);
      expect(r.band!.label, isNotEmpty);
    });
  });
}

/// An [AssetBundle] over a literal map, for load tests.
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw Exception('not in bundle: $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}

/// An [AssetBundle] that reads the repository's own asset files.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final file = _localFile(key);
    return ByteData.sublistView(await file);
  }
}

Future<Uint8List> _localFile(String path) async {
  // ignore: avoid_slow_async_io
  final f = File(path);
  if (!await f.exists()) throw Exception('missing asset file: $path');
  return f.readAsBytes();
}
