import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/patient_import.dart';
import 'package:doctor_management_app/features/patients/data/visit_import.dart';

/// A visit attached to the wrong patient is worse than one not imported at
/// all: it puts a stranger's treatment in someone's record and nothing about
/// the result looks wrong. So the matching rules, and every parser a row
/// passes through on the way, are pinned here.
void main() {
  Patient patient({
    required String id,
    String first = 'Alice',
    String last = 'Smith',
    String phone = '',
    String oldId = '',
    String notes = '',
    bool archived = false,
  }) => Patient(
    id: id,
    doctorId: 'clinic-1',
    firstName: first,
    lastName: last,
    phone: phone,
    gender: 'female',
    dateOfBirth: DateTime(1990, 5, 20),
    diagnosis: const [],
    notes: notes,
    oldId: oldId,
    packageBalance: 0,
    isArchived: archived,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 2),
  );

  group('oldIdForMatching', () {
    test('uses the field when it is set', () {
      expect(oldIdForMatching(patient(id: 'p1', oldId: 'REG-7')), 'REG-7');
    });

    test('falls back to the notes line older imports wrote', () {
      final p = patient(
        id: 'p1',
        notes: 'Age at import: 40\nOld ID: 1234\nAddress: MG Road',
      );
      expect(oldIdForMatching(p), '1234');
    });

    test('prefers the field over a stale notes line', () {
      final p = patient(id: 'p1', oldId: 'NEW-1', notes: 'Old ID: OLD-9');
      expect(oldIdForMatching(p), 'NEW-1');
    });

    test('is empty when neither says anything', () {
      expect(oldIdForMatching(patient(id: 'p1', notes: 'No ID here')), '');
    });
  });

  group('PatientIndex', () {
    final alice = patient(
      id: 'p1',
      phone: '+919876543210',
      oldId: 'REG-7',
    );
    final bob = patient(
      id: 'p2',
      first: 'Bob',
      last: 'Jones',
      phone: '9123456789',
    );
    final index = PatientIndex([alice, bob]);

    test('matches on the old id, ignoring case and punctuation', () {
      expect(
        index.match(oldId: 'reg 7', phone: '', name: '').patient?.id,
        'p1',
      );
    });

    test('matches on the last 10 digits of the phone', () {
      expect(
        index.match(oldId: '', phone: '+91 91234 56789', name: '').patient?.id,
        'p2',
      );
    });

    test('matches on the full name', () {
      expect(
        index.match(oldId: '', phone: '', name: 'bob jones').patient?.id,
        'p2',
      );
    });

    test('the old id wins over a phone pointing elsewhere', () {
      final hit = index.match(
        oldId: 'REG-7',
        phone: '9123456789',
        name: 'Bob Jones',
      );
      expect(hit.patient?.id, 'p1');
    });

    test('a name two patients share matches nobody, and says why', () {
      final twins = PatientIndex([
        patient(id: 'p1', first: 'Ravi', last: 'Kumar'),
        patient(id: 'p2', first: 'Ravi', last: 'Kumar'),
      ]);
      final hit = twins.match(oldId: '', phone: '', name: 'Ravi Kumar');
      expect(hit.patient, isNull);
      expect(hit.reason, contains('More than one patient named'));
    });

    test('an archived patient is never matched', () {
      final gone = PatientIndex([
        patient(id: 'p9', oldId: 'REG-9', archived: true),
      ]);
      expect(gone.match(oldId: 'REG-9', phone: '', name: '').patient, isNull);
    });

    test('a row naming nobody says so rather than guessing', () {
      final hit = index.match(oldId: '', phone: '', name: '');
      expect(hit.patient, isNull);
      expect(hit.reason, 'The row does not say whose visit it is');
    });

    test('a phone too short to identify anyone is not matched on', () {
      final hit = index.match(oldId: '', phone: '12345', name: '');
      expect(hit.patient, isNull);
    });
  });

  // Shared with the patient import, where it reads the date of birth.
  group('parseImportDate', () {
    final now = DateTime(2026, 6, 1, 12);

    test('reads a four-digit year, not its first two digits', () {
      expect(parseImportDate('12/03/2025', now), DateTime(2025, 3, 12));
      expect(parseImportDate('20-05-1990', now), DateTime(1990, 5, 20));
      expect(parseImportDate('1.7.2001', now), DateTime(2001, 7, 1));
    });

    test('reads day before month, the Indian order', () {
      expect(parseImportDate('12/03/2025', now), DateTime(2025, 3, 12));
    });

    test('still reads a two-digit year', () {
      expect(parseImportDate('12/03/25', now), DateTime(2025, 3, 12));
      expect(parseImportDate('20/05/90', now), DateTime(1990, 5, 20));
    });

    test('reads the other forms it documents', () {
      expect(parseImportDate('2025-03-12', now), DateTime(2025, 3, 12));
      expect(parseImportDate('12-Mar-2025', now), DateTime(2025, 3, 12));
    });

    test('refuses a date that is not real, or in the future', () {
      expect(parseImportDate('31/02/2025', now), isNull);
      expect(parseImportDate('12/03/2027', now), isNull);
      expect(parseImportDate('someday', now), isNull);
    });
  });

  group('parseImportTime', () {
    test('reads 24-hour and 12-hour forms', () {
      expect(parseImportTime('14:30'), (hour: 14, minute: 30));
      expect(parseImportTime('9'), (hour: 9, minute: 0));
      expect(parseImportTime('9.45'), (hour: 9, minute: 45));
      expect(parseImportTime('4:15 pm'), (hour: 16, minute: 15));
      expect(parseImportTime('12:05 AM'), (hour: 0, minute: 5));
      expect(parseImportTime('12:05 pm'), (hour: 12, minute: 5));
    });

    test('rejects what is not a time', () {
      expect(parseImportTime(''), isNull);
      expect(parseImportTime('morning'), isNull);
      expect(parseImportTime('25:00'), isNull);
      expect(parseImportTime('10:75'), isNull);
    });
  });

  group('status', () {
    final now = DateTime(2026, 6, 1, 12);

    test('reads what the file says', () {
      expect(parseImportStatus('Done'), VisitStatus.completed);
      expect(parseImportStatus('no show'), VisitStatus.missed);
      expect(parseImportStatus('Cancelled'), VisitStatus.cancelled);
      expect(parseImportStatus('booked'), VisitStatus.scheduled);
    });

    test('unrecognised text is not forced into a status', () {
      expect(parseImportStatus('came in late'), isNull);
    });

    test('with nothing said, the date decides', () {
      expect(
        statusForRow('', DateTime(2025, 1, 1), now),
        VisitStatus.completed,
      );
      expect(
        statusForRow('', DateTime(2027, 1, 1), now),
        VisitStatus.scheduled,
      );
    });

    test('what the file says beats the date', () {
      expect(
        statusForRow('missed', DateTime(2025, 1, 1), now),
        VisitStatus.missed,
      );
    });
  });

  group('parseImportAmount', () {
    test('strips currency, separators and a trailing slash', () {
      expect(parseImportAmount('1,200'), 1200);
      expect(parseImportAmount('Rs. 500'), 500);
      expect(parseImportAmount('₹ 2,500.50'), 2500.5);
      expect(parseImportAmount('800/-'), 800);
      expect(parseImportAmount('INR 300'), 300);
    });

    test('rejects what is not an amount', () {
      expect(parseImportAmount(''), isNull);
      expect(parseImportAmount('free'), isNull);
      expect(parseImportAmount('-50'), isNull);
    });
  });

  group('parseImportPaid', () {
    test('reads yes and no', () {
      expect(parseImportPaid('Yes'), isTrue);
      expect(parseImportPaid('UPI'), isTrue);
      expect(parseImportPaid('unpaid'), isFalse);
      expect(parseImportPaid('due'), isFalse);
    });

    test('says nothing when the cell says nothing', () {
      expect(parseImportPaid(''), isNull);
      expect(parseImportPaid('partial'), isNull);
    });
  });

  group('buildVisitPlan', () {
    final alice = patient(id: 'p1', phone: '9876543210', oldId: 'REG-7');
    final now = DateTime(2026, 6, 1, 12);

    const headers = [
      'Patient ID',
      'Visit date',
      'Visit time',
      'Status',
      'Treatment',
      'Amount',
    ];
    const mapping = {
      VisitImportField.patientOldId: 0,
      VisitImportField.date: 1,
      VisitImportField.time: 2,
      VisitImportField.status: 3,
      VisitImportField.treatment: 4,
      VisitImportField.amount: 5,
      VisitImportField.patientPhone: null,
      VisitImportField.patientName: null,
      VisitImportField.notes: null,
      VisitImportField.paid: null,
    };

    VisitImportPlan planFor(
      List<List<String>> rows, {
      Set<String> existingDays = const {},
    }) => buildVisitPlan(
      table: ParsedTable(headers: headers, rows: rows),
      mapping: mapping,
      existingPatients: [alice],
      existingVisitDays: existingDays,
      now: now,
    );

    test('a matched row with a date is ready', () {
      final plan = planFor([
        ['REG-7', '12/03/2025', '10:30', 'Done', 'Cleaning', '1,200'],
      ]);
      expect(plan.ready, 1);
      expect(plan.errors, 0);
      final row = plan.rows.single;
      expect(row.patient?.id, 'p1');
      expect(row.start, DateTime(2025, 3, 12, 10, 30));
      expect(row.visitStatus, VisitStatus.completed);
      expect(row.treatment, 'Cleaning');
      expect(row.amount, 1200);
      expect(row.hadTime, isTrue);
    });

    test('no time is still ready, placed at the default hour', () {
      final plan = planFor([
        ['REG-7', '12/03/2025', '', '', '', ''],
      ]);
      final row = plan.rows.single;
      expect(row.status, RowStatus.ready);
      expect(row.start, DateTime(2025, 3, 12, kVisitImportDefaultHour));
      expect(row.hadTime, isFalse);
      expect(plan.noTime, 1);
    });

    test('a row matching no patient is an error, not a guess', () {
      final plan = planFor([
        ['REG-999', '12/03/2025', '', '', '', ''],
      ]);
      expect(plan.errors, 1);
      expect(plan.rows.single.reason, contains('No patient here matches'));
    });

    test('a row with no readable date is an error', () {
      final plan = planFor([
        ['REG-7', 'last winter', '', '', '', ''],
      ]);
      expect(plan.errors, 1);
      expect(plan.rows.single.reason, contains('not recognised'));
    });

    test('a visit already in CruDoc that day is a duplicate', () {
      final plan = planFor(
        [
          ['REG-7', '12/03/2025', '', '', '', ''],
        ],
        existingDays: {visitDayKey('p1', DateTime(2025, 3, 12, 9))},
      );
      expect(plan.duplicates, 1);
      expect(plan.rows.single.reason, contains('already has a visit'));
    });

    test('the same patient twice on one day is a duplicate of the first', () {
      final plan = planFor([
        ['REG-7', '12/03/2025', '10:00', '', '', ''],
        ['REG-7', '12/03/2025', '16:00', '', '', ''],
      ]);
      expect(plan.ready, 1);
      expect(plan.duplicates, 1);
      expect(plan.rows.last.reason, contains('row 2'));
    });

    test('blank rows are skipped entirely', () {
      final plan = planFor([
        ['', '', '', '', '', ''],
        ['REG-7', '12/03/2025', '', '', '', ''],
      ]);
      expect(plan.rows, hasLength(1));
    });

    test('counts the distinct patients it would touch', () {
      final plan = planFor([
        ['REG-7', '12/03/2025', '', '', '', ''],
        ['REG-7', '13/03/2025', '', '', '', ''],
      ]);
      expect(plan.patients, 1);
    });
  });

  group('visitForRow', () {
    final alice = patient(id: 'p1', oldId: 'REG-7');
    final now = DateTime(2026, 6, 1, 12);

    VisitImportRow row({double? amount, bool? paid, String notes = ''}) =>
        VisitImportRow(
          number: 2,
          raw: const [],
          status: RowStatus.ready,
          patient: alice,
          start: DateTime(2025, 3, 12, 10, 30),
          visitStatus: VisitStatus.completed,
          treatment: 'Cleaning',
          notes: notes,
          amount: amount,
          paid: paid,
          hadTime: true,
        );

    test('carries the row onto the visit', () {
      final v = visitForRow(row(amount: 1200), fileName: 'old.csv', now: now);
      expect(v.patientId, 'p1');
      expect(v.scheduledStart, DateTime(2025, 3, 12, 10, 30));
      expect(v.status, VisitStatus.completed);
      expect(v.visitType, VisitType.clinic);
      expect(v.treatmentType, 'Cleaning');
      expect(v.amountCharged, 1200);
      expect(v.durationMinutes, kVisitImportDurationMinutes);
    });

    test('an amount alone does not claim the money was collected', () {
      final v = visitForRow(row(amount: 1200), fileName: 'old.csv', now: now);
      expect(v.isPaid, isFalse);
    });

    test('a paid column is believed', () {
      final v = visitForRow(
        row(amount: 1200, paid: true),
        fileName: 'old.csv',
        now: now,
      );
      expect(v.isPaid, isTrue);
    });

    test('the note says where the visit came from', () {
      final v = visitForRow(
        row(notes: 'Patient came with mother'),
        fileName: 'old clinic.xlsx',
        now: now,
      );
      expect(v.therapistNotes, contains('Patient came with mother'));
      expect(v.therapistNotes, contains('Imported from old clinic.xlsx'));
    });

    test('no address, so nothing is geocoded', () {
      final v = visitForRow(row(), fileName: 'old.csv', now: now);
      expect(v.address, isEmpty);
    });

    test('the duration is one CruDoc will accept', () {
      expect(
        kVisitImportDurationMinutes,
        inInclusiveRange(kMinVisitDurationMinutes, kMaxVisitDurationMinutes),
      );
    });
  });
}
