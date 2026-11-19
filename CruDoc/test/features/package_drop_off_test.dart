import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/domain/package_drop_off.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';

/// These suggestions end in a message to a real patient, so the rules that
/// decide who is chased are pinned here: chasing somebody who is booked in
/// for tomorrow, or who already finished their package, costs the clinic
/// more than the recall is worth.
void main() {
  final now = DateTime(2026, 6, 1, 12);
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  SessionPackage package({
    String patientId = 'p1',
    String name = 'Knee rehab',
    int total = 10,
    List<DateTime> used = const [],
    DateTime? validUntil,
    DateTime? sold,
  }) => SessionPackage.fromRecord(
    DentalRecord.create(patientId, RecKind.physioPackage, {
      'name': name,
      'total': total,
      'price': 5000,
      if (validUntil != null) 'validUntil': validUntil.millisecondsSinceEpoch,
      'note': '',
      'used': [for (final u in used) u.millisecondsSinceEpoch],
    }, at: sold ?? daysAgo(60)),
  );

  List<PackageDropOff> run(
    List<SessionPackage> packages, {
    Set<String> active = const {'p1', 'p2'},
    Set<String> booked = const {},
    Set<String> recalled = const {},
  }) => packageDropOffs(
    packages: packages,
    activePatientIds: active,
    patientsWithUpcomingVisit: booked,
    patientsWithOpenRecall: recalled,
    now: now,
  );

  group('who is suggested', () {
    test('sessions left and nothing used for three weeks', () {
      final found = run([
        package(used: [daysAgo(40), daysAgo(30)]),
      ]);
      expect(found, hasLength(1));
      expect(found.single.patientId, 'p1');
      expect(found.single.sessionsLeft, 8);
      expect(found.single.since, daysAgo(30));
      expect(found.single.expired, isFalse);
    });

    test('a package sold but never started is counted from the sale', () {
      final found = run([package(sold: daysAgo(45))]);
      expect(found, hasLength(1));
      expect(found.single.since, daysAgo(45));
      expect(found.single.sessionsLeft, 10);
    });

    test('an expired package with sessions left is chased at once', () {
      final found = run([
        package(used: [daysAgo(3)], validUntil: daysAgo(1)),
      ]);
      expect(found, hasLength(1));
      expect(found.single.expired, isTrue);
    });
  });

  group('who is left alone', () {
    test('a finished package', () {
      final used = [for (var i = 0; i < 10; i++) daysAgo(60 - i)];
      expect(run([package(used: used)]), isEmpty);
    });

    test('a package used within the stall window', () {
      final found = run([
        package(used: [daysAgo(kPackageStallDays - 1)]),
      ]);
      expect(found, isEmpty);
    });

    test('a patient who already has a visit booked', () {
      final found = run([
        package(used: [daysAgo(40)]),
      ], booked: {'p1'});
      expect(found, isEmpty);
    });

    test('a patient who already has an open recall', () {
      final found = run([
        package(used: [daysAgo(40)]),
      ], recalled: {'p1'});
      expect(found, isEmpty);
    });

    test('an archived patient, who is not in the active set', () {
      final found = run([
        package(used: [daysAgo(40)]),
      ], active: {'p2'});
      expect(found, isEmpty);
    });

    test('a clinic-wide record with no patient on it', () {
      final found = run([package(patientId: '')]);
      expect(found, isEmpty);
    });
  });

  group('one patient, one call', () {
    test('two stalled packages give one suggestion, the older one', () {
      final found = run([
        package(name: 'Shoulder', used: [daysAgo(30)]),
        package(name: 'Knee rehab', used: [daysAgo(50)]),
      ]);
      expect(found, hasLength(1));
      expect(found.single.package.name, 'Knee rehab');
      expect(found.single.since, daysAgo(50));
    });

    test('different patients each get their own', () {
      final found = run([
        package(used: [daysAgo(30)]),
        package(patientId: 'p2', used: [daysAgo(50)]),
      ]);
      expect(found, hasLength(2));
    });

    test('the longest stalled comes first', () {
      final found = run([
        package(used: [daysAgo(30)]),
        package(patientId: 'p2', used: [daysAgo(50)]),
      ]);
      expect(found.first.patientId, 'p2');
    });
  });

  // The reason is written into the recall, which both the recall list shows
  // and the reminder drops into "about your {reason}." So it has to read as
  // part of that sentence, in lower case, without a date.
  group('reasonLine', () {
    test('reads as part of the reminder sentence', () {
      final found = run([
        package(used: [daysAgo(40)]),
      ]);
      expect(found.single.reasonLine, 'Knee rehab package, 9 of 10 sessions left');
      expect(
        'about your ${found.single.reasonLine.toLowerCase()}.',
        'about your knee rehab package, 9 of 10 sessions left.',
      );
    });

    test('an unnamed package still reads as a sentence', () {
      final found = run([
        package(name: '', used: [daysAgo(40)]),
      ]);
      expect(found.single.reasonLine, 'package, 9 of 10 sessions left');
    });

    test('carries no date, since a package has no due date', () {
      final found = run([
        package(used: [daysAgo(40)]),
      ]);
      expect(found.single.reasonLine, isNot(contains('days ago')));
    });
  });

  group('summary', () {
    test('says what is left and how long it has been', () {
      final found = run([
        package(used: [daysAgo(34)]),
      ]);
      final line = found.single.summary(now);
      expect(line, contains('Knee rehab'));
      expect(line, contains('9 of 10 sessions left'));
      expect(line, contains('34 days ago'));
    });

    test('an expired package says so instead of counting days', () {
      final found = run([
        package(used: [daysAgo(3)], validUntil: daysAgo(1)),
      ]);
      expect(found.single.summary(now), contains('package expired'));
    });

    test('an unnamed package still reads properly', () {
      final found = run([
        package(name: '', used: [daysAgo(40)]),
      ]);
      expect(found.single.summary(now), startsWith('9 of 10 sessions left'));
    });
  });
}
