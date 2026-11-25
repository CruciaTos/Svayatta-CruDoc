import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/homeopathy/data/homeopathy_remedies.dart';
import 'package:doctor_management_app/features/homeopathy/data/tissue_salts.dart';

/// The twelve salts are a closed, numbered set, and eight of them are also
/// classical remedies already in the app. The tests that matter are the ones
/// keeping those two facts true: the set stays complete and correctly
/// numbered, and a salt prescribed here writes the same remedy name as the
/// same substance prescribed classically.
void main() {
  group('the set is closed and complete', () {
    test('there are exactly twelve', () {
      expect(kTissueSalts.length, 12);
    });

    test('numbered 1 to 12, each once, in order', () {
      expect(
        [for (final s in kTissueSalts) s.number],
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
      );
    });

    test('lookup finds every number and nothing outside the set', () {
      for (var n = 1; n <= 12; n++) {
        expect(tissueSaltByNumber(n)!.number, n);
      }
      expect(tissueSaltByNumber(0), isNull);
      expect(tissueSaltByNumber(13), isNull);
      expect(tissueSaltByNumber(-1), isNull);
    });

    test('no salt appears twice under two numbers', () {
      final names = {for (final s in kTissueSalts) s.remedy};
      expect(names.length, 12);
    });

    test('every salt says where it acts and what it is for', () {
      for (final s in kTissueSalts) {
        expect(s.tissue.trim(), isNotEmpty, reason: s.abbr);
        expect(s.indications, isNotEmpty, reason: s.abbr);
        expect(s.potency.trim(), isNotEmpty, reason: s.abbr);
        for (final i in s.indications) {
          expect(i.trim(), i, reason: 'padded indication on ${s.abbr}');
          expect(i.trim(), isNotEmpty, reason: s.abbr);
        }
      }
    });
  });

  group('one remedy name everywhere', () {
    test('every salt matches a remedy in the app list, exactly', () {
      // The invariant this file exists to protect. A salt whose name does
      // not match cannot be dispensed, and worse, splits one patient's
      // history across two spellings of the same substance.
      final known = {for (final r in homeopathyRemedies) r.name};
      for (final s in kTissueSalts) {
        expect(
          known,
          contains(s.remedy),
          reason:
              '"${s.remedy}" (No. ${s.number}) is not a remedy name the app '
              'knows, so it could not be prescribed or dispensed',
        );
      }
    });

    test('searching the remedy list by a salt name finds it', () {
      for (final s in kTissueSalts) {
        final hits = searchRemedies(s.remedy, limit: 50);
        expect(
          [for (final h in hits) h.name],
          contains(s.remedy),
          reason: s.remedy,
        );
      }
    });
  });

  group('search', () {
    test('an empty query gives the whole set, still in order', () {
      expect(searchTissueSalts('  ').length, 12);
      expect(searchTissueSalts('').first.number, 1);
    });

    test('a bare number is treated as the salt number', () {
      // How a clinic and a label both refer to these.
      expect(searchTissueSalts('4').single.abbr, 'Ferrum phos.');
      expect(searchTissueSalts('12').single.remedy, 'Silicea');
      expect(searchTissueSalts('99'), isEmpty);
    });

    test('finds by name and by abbreviation, with or without full stops', () {
      expect(searchTissueSalts('silicea').single.number, 12);
      expect(searchTissueSalts('mag phos').single.number, 8);
      expect(searchTissueSalts('mag phos.').single.number, 8);
    });

    test('finds by indication, which is how the system is prescribed', () {
      // Looking up a symptom has to reach the salt for it.
      expect([
        for (final s in searchTissueSalts('cramp')) s.number,
      ], contains(8));
      expect([
        for (final s in searchTissueSalts('splinter')) s.number,
      ], contains(12));
      expect([
        for (final s in searchTissueSalts('varicose')) s.number,
      ], contains(1));
    });

    test('finds by tissue', () {
      expect([
        for (final s in searchTissueSalts('nerve')) s.number,
      ], containsAll([6, 8]));
    });

    test('case does not matter', () {
      expect(searchTissueSalts('SILICEA').single.number, 12);
      expect(searchTissueSalts('Cramp').isNotEmpty, isTrue);
    });

    test('a query matching nothing returns nothing, not everything', () {
      expect(searchTissueSalts('zzzznotathing'), isEmpty);
    });
  });

  group('labels and dosing', () {
    test('the label carries the number, which is how patients know them', () {
      expect(tissueSaltByNumber(4)!.label, 'No. 4 — Ferrum phos.');
    });

    test('dosing is stated once for the whole system', () {
      // Per-salt figures would imply a precision the system does not claim.
      expect(kTissueSaltDosing, contains('6X'));
      expect(kTissueSaltDosing.trim(), kTissueSaltDosing);
    });
  });
}
