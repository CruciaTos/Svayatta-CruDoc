import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/homeopathy/domain/lesion_photo_models.dart';

/// A before-and-after photograph is a claim about treatment, so the whole
/// point of these tests is that two images only ever get put side by side
/// when they are of the same place, and that one photograph is never dressed
/// up as a comparison.
void main() {
  DentalRecord rec({
    required DateTime date,
    required Map<String, String> sites,
    required Map<String, String> photos,
    String notes = '',
  }) => DentalRecord.create(
    'p1',
    RecKind.homeoLesionPhoto,
    LesionPhotoSet.toData(
      date: date,
      notes: notes,
      sites: sites,
      photos: photos,
    ),
    at: date,
  );

  group('site keys', () {
    test('a label becomes a key that is safe as a file name', () {
      expect(lesionSiteKey('Left thumb'), 'left_thumb');
      expect(lesionSiteKey('R. elbow (outer)'), 'r_elbow_outer');
    });

    test('the same place typed differently is the same site', () {
      // Otherwise a series silently splits in two and the comparison is
      // taken against the wrong baseline.
      const variants = ['Left thumb', 'left thumb', '  LEFT THUMB  '];
      final keys = {for (final v in variants) lesionSiteKey(v)};
      expect(keys.length, 1);
    });

    test('a label with nothing usable gives an empty key, not a bad one', () {
      expect(lesionSiteKey('***'), '');
      expect(lesionSiteKey('   '), '');
    });

    test('keys never start or end with an underscore', () {
      for (final label in ['(left thumb)', '  -- scalp --  ', '...wart...']) {
        final key = lesionSiteKey(label);
        expect(key.startsWith('_'), isFalse, reason: label);
        expect(key.endsWith('_'), isFalse, reason: label);
      }
    });
  });

  group('reading a set back', () {
    test('a set keeps its date, sites and photographs', () {
      final s = LesionPhotoSet.fromRecord(
        rec(
          date: DateTime(2026, 10, 1),
          sites: const {'left_thumb': 'Left thumb'},
          photos: const {'left_thumb': '/photos/a.jpg'},
          notes: 'Wart, raised',
        ),
      );
      expect(s.date, DateTime(2026, 10, 1));
      expect(s.labelFor('left_thumb'), 'Left thumb');
      expect(s.pathFor('left_thumb'), '/photos/a.jpg');
      expect(s.notes, 'Wart, raised');
      expect(s.photographed, ['left_thumb']);
    });

    test('a site named but not yet photographed is not counted', () {
      final s = LesionPhotoSet.fromRecord(
        rec(
          date: DateTime(2026, 10, 1),
          sites: const {'scalp': 'Scalp', 'elbow': 'Elbow'},
          photos: const {'scalp': '/photos/a.jpg'},
        ),
      );
      expect(s.photographed, ['scalp']);
    });

    test('a photograph whose label was lost still shows under its key', () {
      // Better a series labelled "left_thumb" than a photograph that
      // vanishes from the record.
      final s = LesionPhotoSet.fromRecord(
        rec(
          date: DateTime(2026, 10, 1),
          sites: const {},
          photos: const {'left_thumb': '/photos/a.jpg'},
        ),
      );
      expect(s.labelFor('left_thumb'), 'left_thumb');
      expect(s.photographed, ['left_thumb']);
    });

    test('an empty path is not a photograph', () {
      final s = LesionPhotoSet.fromRecord(
        rec(
          date: DateTime(2026, 10, 1),
          sites: const {'scalp': 'Scalp'},
          photos: const {'scalp': '   '},
        ),
      );
      expect(s.photographed, isEmpty);
    });
  });

  group('following a site across visits', () {
    List<LesionPhotoSet> threeVisits() => lesionPhotoSets([
      rec(
        date: DateTime(2026, 10, 1),
        sites: const {'left_thumb': 'Left thumb'},
        photos: const {'left_thumb': '/1.jpg'},
      ),
      rec(
        date: DateTime(2026, 11, 12),
        sites: const {'left_thumb': 'Left thumb', 'scalp': 'Scalp'},
        photos: const {'left_thumb': '/2.jpg', 'scalp': '/s1.jpg'},
      ),
      rec(
        date: DateTime(2026, 10, 22),
        sites: const {'left_thumb': 'Left thumb'},
        photos: const {'left_thumb': '/3.jpg'},
      ),
    ]);

    test('sets come back newest visit first', () {
      expect([for (final s in threeVisits()) s.date.day], [12, 22, 1]);
    });

    test('a series runs oldest first, so the first shot is the baseline', () {
      final series = lesionSeriesOf(threeVisits());
      final thumb = series.firstWhere((s) => s.key == 'left_thumb');
      expect(
        [for (final s in thumb.shots) s.path],
        ['/1.jpg', '/3.jpg', '/2.jpg'],
      );
      expect(thumb.first.path, '/1.jpg');
      expect(thumb.latest.path, '/2.jpg');
    });

    test('the most recently photographed site leads', () {
      final series = lesionSeriesOf(threeVisits());
      // Both were last shot on 12 Nov; thumb and scalp are both current.
      expect(series.map((s) => s.key), containsAll(['left_thumb', 'scalp']));
      expect(series.first.latest.date, DateTime(2026, 11, 12));
    });

    test('a site keeps the name it was first given', () {
      final series = lesionSeriesOf(
        lesionPhotoSets([
          rec(
            date: DateTime(2026, 10, 1),
            sites: const {'left_thumb': 'Left thumb'},
            photos: const {'left_thumb': '/1.jpg'},
          ),
          rec(
            date: DateTime(2026, 11, 1),
            sites: const {'left_thumb': 'left THUMB wart'},
            photos: const {'left_thumb': '/2.jpg'},
          ),
        ]),
      );
      expect(series.single.label, 'Left thumb');
    });

    test('one photograph is not a comparison', () {
      final series = lesionSeriesOf(
        lesionPhotoSets([
          rec(
            date: DateTime(2026, 10, 1),
            sites: const {'scalp': 'Scalp'},
            photos: const {'scalp': '/1.jpg'},
          ),
        ]),
      );
      expect(series.single.canCompare, isFalse);
      expect(lesionSeriesLine(series.single), '1 photograph');
    });

    test('two photographs can be compared, and the span is stated', () {
      final series = lesionSeriesOf(threeVisits());
      final thumb = series.firstWhere((s) => s.key == 'left_thumb');
      expect(thumb.canCompare, isTrue);
      expect(thumb.days, 42);
      expect(thumb.weeks, 6);
      expect(lesionSeriesLine(thumb), '3 photographs over 6 weeks');
    });

    test('a span under a week is said in days, not rounded to zero', () {
      final series = lesionSeriesOf(
        lesionPhotoSets([
          rec(
            date: DateTime(2026, 10, 1),
            sites: const {'scalp': 'Scalp'},
            photos: const {'scalp': '/1.jpg'},
          ),
          rec(
            date: DateTime(2026, 10, 4),
            sites: const {'scalp': 'Scalp'},
            photos: const {'scalp': '/2.jpg'},
          ),
        ]),
      );
      expect(lesionSeriesLine(series.single), '2 photographs over 3 days');
    });

    test('the line never claims the lesion got better or worse', () {
      // Judging a lesion from a photograph is the homeopath's call.
      final thumb = lesionSeriesOf(
        threeVisits(),
      ).firstWhere((s) => s.key == 'left_thumb');
      final line = lesionSeriesLine(thumb).toLowerCase();
      for (final claim in [
        'better',
        'worse',
        'improv',
        'clear',
        'resolv',
        'heal',
      ]) {
        expect(line, isNot(contains(claim)), reason: 'claimed "$claim"');
      }
    });

    test('sites with no photographs produce no series', () {
      final series = lesionSeriesOf(
        lesionPhotoSets([
          rec(
            date: DateTime(2026, 10, 1),
            sites: const {'scalp': 'Scalp'},
            photos: const {},
          ),
        ]),
      );
      expect(series, isEmpty);
    });

    test('known sites are offered back for reuse on the next visit', () {
      final sites = knownLesionSites(threeVisits());
      expect([
        for (final s in sites) s.label,
      ], containsAll(['Left thumb', 'Scalp']));
      expect(sites.length, 2);
    });
  });
}
