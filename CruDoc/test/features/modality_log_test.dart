import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/modality_catalog.dart';
import 'package:doctor_management_app/features/therapy/domain/modality_models.dart';

/// An electrotherapy log is a record of what was applied to a person. The
/// tests that matter are the ones proving it never says more than it knows:
/// a setting nobody typed stays absent, and a missing setting is visible
/// rather than quietly filled in.
void main() {
  final day = DateTime(2026, 11, 20, 10, 30);

  DentalRecord rec({
    String modalityId = 'tens',
    String site = 'R knee',
    int? minutes = 20,
    Map<String, String> params = const {'frequency': '80'},
    String note = '',
    DateTime? at,
  }) => DentalRecord.create(
    'p1',
    RecKind.physioModality,
    ModalityApplication.toData(
      modalityId: modalityId,
      site: site,
      minutes: minutes,
      params: params,
      note: note,
    ),
    at: at ?? day,
  );

  ModalityApplication app({
    String modalityId = 'tens',
    String site = 'R knee',
    int? minutes = 20,
    Map<String, String> params = const {'frequency': '80'},
    DateTime? at,
  }) => ModalityApplication.fromRecord(
    rec(
      modalityId: modalityId,
      site: site,
      minutes: minutes,
      params: params,
      at: at,
    ),
  );

  group('nothing is invented', () {
    test('a blank setting is not stored at all', () {
      final data = ModalityApplication.toData(
        modalityId: 'tens',
        site: 'R knee',
        minutes: 20,
        params: {'frequency': '80', 'pulseWidth': '  ', 'intensity': ''},
        note: '',
      );
      expect((data['params'] as Map).keys, ['frequency']);
    });

    test('an unrecorded time is absent, never zero', () {
      final data = ModalityApplication.toData(
        modalityId: 'tens',
        site: '',
        minutes: null,
        params: const {},
        note: '',
      );
      expect(data.containsKey('minutes'), isFalse);
      expect(
        ModalityApplication.fromRecord(rec(minutes: null)).minutes,
        isNull,
      );
    });

    test('a missing setting makes the application incomplete', () {
      // TENS asks for mode, frequency, pulse width and intensity.
      expect(app(params: const {'frequency': '80'}).isIncomplete, isTrue);
      expect(
        app(
          params: const {
            'mode': 'Burst',
            'frequency': '80',
            'pulseWidth': '200',
            'intensity': '18',
          },
        ).isIncomplete,
        isFalse,
      );
    });

    test('a complete set of settings with no time is still incomplete', () {
      expect(
        app(
          minutes: null,
          params: const {
            'mode': 'Burst',
            'frequency': '80',
            'pulseWidth': '200',
            'intensity': '18',
          },
        ).isIncomplete,
        isTrue,
      );
    });
  });

  group('reading it back', () {
    test('settings are ordered by the catalogue, with their units', () {
      final a = app(
        params: const {
          // Deliberately out of catalogue order.
          'intensity': '18',
          'frequency': '80',
          'pulseWidth': '200',
          'mode': 'Burst',
        },
      );
      expect(a.settingsLine, 'Burst · 80 Hz · 200 µs · 18 mA');
    });

    test('the summary reads as what was done', () {
      expect(
        app(params: const {'frequency': '80'}).summaryLine,
        'TENS · R knee · 20 min · 80 Hz',
      );
    });

    test(
      'a setting the catalogue no longer has is left out, not unlabelled',
      () {
        final a = app(params: const {'frequency': '80', 'obsolete': '7'});
        expect(a.settingsLine, '80 Hz');
      },
    );

    test('a modality no longer in the catalogue keeps its id as its name', () {
      final a = app(modalityId: 'diathermy-old', params: const {});
      expect(a.def, isNull);
      expect(a.label, 'diathermy-old');
      // Nothing to order them by, so the raw values are shown rather than
      // dropping the record's content entirely.
      expect(
        ModalityApplication.fromRecord(
          rec(modalityId: 'gone', params: const {'x': '5'}),
        ).settingsLine,
        '5',
      );
    });

    test('an unknown modality is never called incomplete', () {
      // There is no catalogue entry to judge it against, so claiming
      // settings are missing would be a guess.
      expect(app(modalityId: 'gone', params: const {}).isIncomplete, isFalse);
    });
  });

  group('grouping by session', () {
    test('applications come back newest first', () {
      final apps = modalityApplications([
        rec(at: DateTime(2026, 11, 1)),
        rec(at: DateTime(2026, 11, 20)),
        rec(at: DateTime(2026, 11, 10)),
      ]);
      expect([for (final a in apps) a.givenAt.day], [20, 10, 1]);
    });

    test('two machines on the same day are one session, newest day first', () {
      final apps = modalityApplications([
        rec(modalityId: 'ift', at: DateTime(2026, 11, 20, 9)),
        rec(modalityId: 'ultrasound', at: DateTime(2026, 11, 20, 9, 30)),
        rec(modalityId: 'tens', at: DateTime(2026, 11, 18, 9)),
      ]);
      final days = modalityDays(apps);
      expect(days.length, 2);
      expect(days.first.day, DateTime(2026, 11, 20));
      expect(days.first.applications.length, 2);
      // In the order they were given, each named once.
      expect(days.first.line, 'IFT · US');
    });

    test('the same machine twice in a day is named once', () {
      final days = modalityDays(
        modalityApplications([
          rec(modalityId: 'ift', site: 'L knee', at: DateTime(2026, 11, 20, 9)),
          rec(
            modalityId: 'ift',
            site: 'R knee',
            at: DateTime(2026, 11, 20, 9, 20),
          ),
        ]),
      );
      expect(days.single.applications.length, 2);
      expect(days.single.line, 'IFT');
    });
  });

  group('tally for the report', () {
    test('counts each modality, most used first', () {
      final apps = modalityApplications([
        for (var i = 0; i < 3; i++)
          rec(modalityId: 'ift', at: DateTime(2026, 11, i + 1)),
        rec(modalityId: 'ultrasound', at: DateTime(2026, 11, 5)),
      ]);
      expect(modalityTally(apps).first, (label: 'IFT', count: 3));
      expect(modalityTallyLine(apps), 'IFT ×3, US ×1');
    });

    test(
      'an equal count is ordered alphabetically, so it does not shuffle',
      () {
        final apps = modalityApplications([
          rec(modalityId: 'ultrasound', at: DateTime(2026, 11, 1)),
          rec(modalityId: 'ift', at: DateTime(2026, 11, 2)),
        ]);
        expect(modalityTallyLine(apps), 'IFT ×1, US ×1');
      },
    );

    test('says nothing when nothing was applied', () {
      expect(modalityTallyLine(const []), isNull);
    });
  });

  group('the catalogue itself', () {
    test('ids are unique, so a record can only mean one modality', () {
      final seen = <String>{};
      for (final m in kModalities) {
        expect(seen.add(m.id), isTrue, reason: 'twice: ${m.id}');
      }
    });

    test('parameter ids are unique within a modality', () {
      for (final m in kModalities) {
        final seen = <String>{};
        for (final p in m.params) {
          expect(seen.add(p.id), isTrue, reason: '${m.id}/${p.id}');
        }
      }
    });

    test('every modality carries its contraindications', () {
      for (final m in kModalities) {
        expect(m.cautions, isNotEmpty, reason: m.id);
        expect(m.minutePresets, isNotEmpty, reason: m.id);
      }
    });

    test('a choice parameter offers something to choose', () {
      for (final m in kModalities) {
        for (final p in m.params) {
          if (p.isChoice) {
            expect(p.presets, isNotEmpty, reason: '${m.id}/${p.id}');
          }
        }
      }
    });

    test('lookup by id finds every modality and nothing else', () {
      for (final m in kModalities) {
        expect(modalityById(m.id), same(m));
      }
      expect(modalityById('not-a-modality'), isNull);
    });
  });
}
