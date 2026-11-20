import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_assess_models.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/package_no_show.dart';

/// Two numbers that leave the clinic: the headline on a report the patient
/// keeps and may show other people, and a session deducted from a package
/// they paid for. Both are pinned here, including the cases where the honest
/// answer is to say nothing.
void main() {
  final day0 = DateTime(2026, 4, 1);

  ProgressEntry entry(int pain, int days, {int function = 5}) =>
      ProgressEntry.fromRecord(
        DentalRecord.create('p1', RecKind.physioProgress, {
          'pain': pain,
          'worst': pain,
          'function': function,
          'note': '',
        }, at: day0.add(Duration(days: days))),
      );

  group('painChange', () {
    test('states the drop as a percentage of where the patient started', () {
      final c = painChange([entry(7, 0), entry(3, 42)])!;
      expect(c.from, 7);
      expect(c.to, 3);
      expect(c.percent, 57); // 4 of 7
      expect(c.weeks, 6);
      expect(c.improved, isTrue);
      expect(c.line, 'Pain down 57% over 6 weeks, from 7 to 3 out of 10');
    });

    test('says so plainly when the pain has gone up', () {
      final c = painChange([entry(4, 0), entry(6, 14)])!;
      expect(c.worse, isTrue);
      expect(c.percent, -50);
      expect(c.line, contains('Pain up 50%'));
      expect(c.line, isNot(contains('down')));
    });

    test('unchanged pain is not dressed up', () {
      final c = painChange([entry(5, 0), entry(5, 21)])!;
      expect(c.percent, 0);
      expect(c.line, 'Pain unchanged at 5 out of 10 over 3 weeks');
    });

    test('a single reading gives no percentage', () {
      expect(painChange([entry(7, 0)]), isNull);
      expect(painChange([]), isNull);
    });

    test('starting at zero pain gives no percentage, not a fake one', () {
      // There is no percentage of nothing, and inventing one would overstate
      // the result for exactly the patients who began well.
      expect(painChange([entry(0, 0), entry(0, 30)]), isNull);
      expect(painChange([entry(0, 0), entry(3, 30)]), isNull);
    });

    test('a full recovery is 100%', () {
      expect(painChange([entry(8, 0), entry(0, 56)])!.percent, 100);
    });

    group('weeks', () {
      test('rounds to whole weeks', () {
        expect(painChange([entry(6, 0), entry(3, 25)])!.weeks, 4);
        expect(painChange([entry(6, 0), entry(3, 10)])!.weeks, 1);
      });

      test('part of a week still reads as a week, not zero', () {
        expect(painChange([entry(6, 0), entry(3, 3)])!.weeks, 1);
      });

      test('two readings on the same day say "so far"', () {
        final c = painChange([entry(6, 0), entry(3, 0)])!;
        expect(c.weeks, 0);
        expect(c.line, contains('so far'));
      });
    });
  });

  group('packageForNoShow', () {
    SessionPackage pkg({
      String name = 'Knee rehab',
      int total = 10,
      int used = 0,
      DateTime? validUntil,
      DateTime? sold,
    }) => SessionPackage.fromRecord(
      DentalRecord.create('p1', RecKind.physioPackage, {
        'name': name,
        'total': total,
        'price': 5000,
        if (validUntil != null) 'validUntil': validUntil.millisecondsSinceEpoch,
        'note': '',
        'used': [
          for (var i = 0; i < used; i++)
            day0.add(Duration(days: i)).millisecondsSinceEpoch,
        ],
      }, at: sold ?? day0),
    );

    test('picks the live package', () {
      expect(packageForNoShow([pkg()])?.name, 'Knee rehab');
    });

    test('ignores a finished package, so nothing is over-deducted', () {
      expect(packageForNoShow([pkg(total: 4, used: 4)]), isNull);
    });

    test('ignores an expired package', () {
      expect(
        packageForNoShow([pkg(validUntil: DateTime(2020, 1, 1))]),
        isNull,
      );
    });

    test('with two live packages, takes the one started most recently', () {
      final found = packageForNoShow([
        pkg(name: 'Old', sold: DateTime(2026, 1, 1)),
        pkg(name: 'Current', sold: DateTime(2026, 5, 1)),
      ]);
      expect(found?.name, 'Current');
    });

    test('no packages means no prompt at all', () {
      expect(packageForNoShow(const []), isNull);
    });
  });
}
