import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/homeopathy/data/homeopathy_remedies.dart';
import 'package:doctor_management_app/features/homeopathy/data/materia_medica_data.dart';

/// The materia medica is also the app's remedy name list: `homeopathyRemedies`
/// is built from these entries plus a list of extras. So a duplicate name, or
/// an entry that disagrees with an extra, splits one remedy into two across a
/// patient's prescriptions, dispensing records and stock.
///
/// The relationship fields are the other risk. A remedy named as
/// complementary that does not exist anywhere in the app is a dead end in the
/// UI: the chip shows and leads nowhere.
void main() {
  final names = {for (final e in kMateriaMedica) e.name};
  final allRemedyNames = {for (final r in homeopathyRemedies) r.name};

  group('one remedy, one name', () {
    test('no remedy appears twice', () {
      final seen = <String>{};
      final twice = <String>[];
      for (final e in kMateriaMedica) {
        if (!seen.add(e.name)) twice.add(e.name);
      }
      expect(twice, isEmpty, reason: 'duplicated:\n${twice.join('\n')}');
    });

    test('no abbreviation is used for two different remedies', () {
      final byAbbr = <String, List<String>>{};
      for (final e in kMateriaMedica) {
        (byAbbr[e.abbr] ??= []).add(e.name);
      }
      final clashes = [
        for (final entry in byAbbr.entries)
          if (entry.value.length > 1) '${entry.key}: ${entry.value.join(", ")}',
      ];
      expect(clashes, isEmpty, reason: clashes.join('\n'));
    });

    test('every entry reaches the app-wide remedy list', () {
      // homeopathyRemedies is what prescribing, dispensing and stock all
      // search. An entry missing from it could be read about but not used.
      for (final e in kMateriaMedica) {
        expect(allRemedyNames, contains(e.name), reason: e.name);
      }
    });

    test('a remedy is searchable by its own name', () {
      for (final e in kMateriaMedica) {
        final hits = searchRemedies(e.name, limit: 50);
        expect(
          [for (final h in hits) h.name],
          contains(e.name),
          reason: e.name,
        );
      }
    });
  });

  group('every entry is usable', () {
    test('each has keynotes, a mental picture and both modalities', () {
      for (final e in kMateriaMedica) {
        expect(e.name.trim(), isNotEmpty);
        expect(e.abbr.trim(), isNotEmpty, reason: e.name);
        expect(e.keynotes, isNotEmpty, reason: e.name);
        expect(e.mind.trim(), isNotEmpty, reason: e.name);
        expect(e.worse.trim(), isNotEmpty, reason: e.name);
        expect(e.better.trim(), isNotEmpty, reason: e.name);
      }
    });

    test('keynotes are neither blank nor padded', () {
      for (final e in kMateriaMedica) {
        for (final k in e.keynotes) {
          expect(k.trim(), isNotEmpty, reason: e.name);
          expect(k.trim(), k, reason: 'padded keynote on ${e.name}');
        }
      }
    });

    test('a remedy has enough keynotes to be recognised', () {
      for (final e in kMateriaMedica) {
        expect(e.keynotes.length, greaterThanOrEqualTo(3), reason: e.name);
      }
    });

    test('keynote lists stay short enough to scan', () {
      // This is a quick reference. Past about eight it stops being one.
      for (final e in kMateriaMedica) {
        expect(e.keynotes.length, lessThanOrEqualTo(8), reason: e.name);
      }
    });
  });

  group('relationships lead somewhere', () {
    test('every related remedy is one the app knows', () {
      final dangling = <String>[];
      for (final e in kMateriaMedica) {
        for (final (field, list) in [
          ('complementary', e.complementary),
          ('followsWell', e.followsWell),
          ('inimical', e.inimical),
          ('antidotes', e.antidotes),
        ]) {
          for (final other in list) {
            if (!allRemedyNames.contains(other)) {
              dangling.add('${e.name}.$field → $other');
            }
          }
        }
      }
      expect(
        dangling,
        isEmpty,
        reason:
            'relationships naming unknown remedies:\n'
            '${dangling.join('\n')}',
      );
    });

    test('no remedy is related to itself', () {
      for (final e in kMateriaMedica) {
        for (final list in [
          e.complementary,
          e.followsWell,
          e.inimical,
          e.antidotes,
        ]) {
          expect(list, isNot(contains(e.name)), reason: e.name);
        }
      }
    });

    test('a remedy is not both complementary and inimical to the same one', () {
      for (final e in kMateriaMedica) {
        final both = e.complementary.toSet().intersection(e.inimical.toSet());
        expect(both, isEmpty, reason: '${e.name}: ${both.join(", ")}');
      }
    });

    test('hasRelationships agrees with the lists', () {
      for (final e in kMateriaMedica) {
        final any =
            e.complementary.isNotEmpty ||
            e.followsWell.isNotEmpty ||
            e.inimical.isNotEmpty ||
            e.antidotes.isNotEmpty;
        expect(e.hasRelationships, any, reason: e.name);
      }
    });
  });

  test('the library is big enough to be worth searching', () {
    expect(names.length, greaterThanOrEqualTo(100));
  });

  test('no remedy appears under two well-known synonyms', () {
    // The prefix check below cannot see these: "Platina" and "Platinum
    // metallicum" share no prefix, but they are the same substance, and
    // having both would split one remedy across two picker entries.
    //
    // Caught exactly that while the library was growing. This list is the
    // alternative names a homeopath might reasonably reach for; only one of
    // each pair may exist in the app.
    const synonyms = [
      ['Platina', 'Platinum metallicum'],
      ['Cina', 'Cina maritima'],
      ['Borax', 'Borax veneta'],
      ['Sarsaparilla', 'Sarsaparilla officinalis'],
      ['Silicea', 'Silica'],
      ['Mercurius solubilis', 'Mercurius vivus'],
      ['Natrum muriaticum', 'Natrum chloratum'],
      ['Hepar sulphuris calcareum', 'Hepar sulphur'],
      ['China officinalis', 'Cinchona officinalis'],
      ['Pulsatilla nigricans', 'Pulsatilla pratensis'],
      ['Lycopodium clavatum', 'Lycopodium'],
      ['Digitalis purpurea', 'Digitalis'],
    ];

    final present = {for (final r in homeopathyRemedies) r.name.toLowerCase()};
    final both = <String>[];
    for (final pair in synonyms) {
      final found = [
        for (final n in pair)
          if (present.contains(n.toLowerCase())) n,
      ];
      if (found.length > 1) both.add(found.join(' / '));
    }
    expect(
      both,
      isEmpty,
      reason: 'the same remedy under two names:\n${both.join('\n')}',
    );
  });

  test('the same remedy is not listed under a short and a long name', () {
    // Caught three of these when the library grew: an entry named "Cina
    // maritima" alongside the existing "Cina" put one substance in the
    // picker twice, so a patient's history could split across both.
    //
    // A longer name beginning with a shorter one is the signature. Some
    // such pairs are genuinely different remedies, and those are listed
    // here deliberately — anything else is a split waiting to happen.
    const genuinelyDifferent = {'sulphur|sulphur iodatum'};

    final all = [for (final r in homeopathyRemedies) r.name.toLowerCase()];
    final splits = <String>[];
    for (final a in all) {
      for (final b in all) {
        if (a == b || !b.startsWith('$a ')) continue;
        if (genuinelyDifferent.contains('$a|$b')) continue;
        splits.add('$a / $b');
      }
    }
    expect(
      splits,
      isEmpty,
      reason: 'one remedy under two names:\n${splits.join('\n')}',
    );
  });
}
