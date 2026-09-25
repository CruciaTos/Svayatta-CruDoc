// Unit tests for the dashboard's pure data layer: `buildDashboard` and
// `DashFormat`. Every test pins `now` explicitly; nothing here reads the
// wall clock.

import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_builder.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';

import 'dashboard_fixtures.dart';

// ---------------------------------------------------------------------------
// Local builders, so each test's data is explicit.
// ---------------------------------------------------------------------------

/// Wednesday 23 September 2026 at [h]:[m] (the Day fixture's date).
DateTime at(int h, int m) => DateTime(2026, 9, 23, h, m);

final DateTime _created = DateTime(2026, 1, 1);

Patient mkPatient(
  String id, {
  String first = 'Test',
  String last = 'Patient',
  String gender = 'Female',
  DateTime? dob,
  List<String> diagnosis = const [],
}) =>
    Patient(
      id: id,
      firstName: first,
      lastName: last,
      phone: '9800000000',
      gender: gender,
      dateOfBirth: dob ?? DateTime(1990, 1, 1),
      diagnosis: diagnosis,
      packageBalance: 0,
      isArchived: false,
      createdAt: _created,
      updatedAt: _created,
    );

Visit mkVisit(
  String id,
  String patientId,
  DateTime start, {
  VisitStatus status = VisitStatus.scheduled,
  VisitType type = VisitType.clinic,
  String? treatment,
  bool deleted = false,
}) =>
    Visit(
      id: id,
      patientId: patientId,
      scheduledStart: start,
      durationMinutes: 15,
      address: '',
      status: status,
      visitType: type,
      treatmentType: treatment,
      isDeleted: deleted,
      createdAt: _created,
      updatedAt: _created,
    );

/// A queue token. `queueDate` defaults to the check-in's local date.
QueueEntry mkToken(
  String id, {
  required DateTime checkedIn,
  int number = 1,
  QueueStatus status = QueueStatus.waiting,
  QueuePriority priority = QueuePriority.normal,
  String? patientId,
  String? walkInName,
  String? visitId,
  String? reason,
  String? queueDate,
  bool deleted = false,
}) =>
    QueueEntry(
      id: id,
      patientId: patientId,
      walkInName: walkInName,
      tokenNumber: number,
      queueDate: queueDate ?? queueDateKeyFor(checkedIn),
      status: status,
      priority: priority,
      reason: reason,
      checkedInAt: checkedIn,
      linkedVisitId: visitId,
      isDeleted: deleted,
      createdAt: checkedIn,
      updatedAt: checkedIn,
    );

RevenueEntry mkRevenue(
  String id,
  DateTime date,
  double amount, {
  TransactionKind kind = TransactionKind.income,
  bool deleted = false,
}) =>
    RevenueEntry(
      id: id,
      date: date,
      description: 'Consultation',
      amount: amount,
      type: RevenueType.visit,
      kind: kind,
      isDeleted: deleted,
      createdAt: date,
      updatedAt: date,
    );

MedicineModel mkMedicine(
  String id,
  String name, {
  String unit = 'strips',
  int stock = 50,
  int reorder = 10,
  DateTime? expiry,
  bool active = true,
}) =>
    MedicineModel(
      id: id,
      name: name,
      unit: unit,
      currentStock: stock,
      reorderThreshold: reorder,
      expiryDate: expiry,
      isActive: active,
      createdAt: _created,
      updatedAt: _created,
    );

/// Builds the schedule-related sections with empty defaults.
DashboardData schedule({
  DateTime? now,
  List<QueueEntry> queue = const [],
  List<Visit> visits = const [],
  List<Patient> patients = const [],
}) =>
    buildDashboard(
      now: now ?? dayNow,
      queue: queue,
      visits: visits,
      patients: patients,
    );

DashboardData dayDashboard() => buildDashboard(
      now: dayNow,
      queue: dayQueue,
      visits: dayVisits,
      patients: fixturePatients,
    );

List<AttentionItem> attentionFor(
  List<MedicineModel> medicines, {
  DateTime? now,
  int max = 10,
}) =>
    buildDashboard(
      now: now ?? dayNow,
      medicines: medicines,
      maxAttentionItems: max,
    ).attention!;

void main() {
  // -------------------------------------------------------------------------
  group('Glance', () {
    test('Day fixture: 5 seen of 13, 8 still to see, 2 waiting, avg 6 min',
        () {
      final glance = dayDashboard().glance!;

      // seen: Priya, Rahul, Fatima, Arjun and Sunita have completed visits
      // today and no queue token, so each is a "done" visit row -> 5.
      expect(glance.seen, 5);

      // total = seen + open rows. Open: Vikram (in consultation), Kavya and
      // Mohammed (waiting), and 5 booked visits not in the queue (Lakshmi,
      // Rohan, Sneha, Anil, Farah). Vikram's and Kavya's visits are linked
      // to their tokens so they are not counted twice -> 5 + 8 = 13.
      expect(glance.total, 13);

      // stillToSee = total - seen = 13 - 5.
      expect(glance.stillToSee, 8);

      // waiting: Kavya (pre-booked for 11:50, which is before 11:58, so she
      // has arrived) and Mohammed (walk-in) -> 2.
      expect(glance.waiting, 2);

      // Kavya waits 11:50 -> 11:58 = 8 min, Mohammed 11:55 -> 11:58 = 3 min.
      // (8 + 3) / 2 = 5.5, which rounds half away from zero -> 6.
      expect(glance.averageWaitMinutes, 6);
    });

    test('Evening fixture: 11 seen of 13, Farah waiting 4 min', () {
      final glance = buildDashboard(
        now: eveningNow,
        queue: eveningQueue,
        // Tomorrow's bookings must not leak into today's counts.
        visits: [...eveningVisits, ...tomorrowVisits],
        patients: fixturePatients,
      ).glance!;

      // 10 completed visits (Priya..Sneha) + Mohammed's completed token.
      expect(glance.seen, 11);
      // Open: Anil (in consultation) and Farah (waiting) -> 11 + 2.
      expect(glance.total, 13);
      expect(glance.stillToSee, 2);
      expect(glance.waiting, 1);
      // Farah's appointment 18:10, now 18:14.
      expect(glance.averageWaitMinutes, 4);
    });

    test('averageWaitMinutes is null when nobody is waiting', () {
      final glance = schedule(
        visits: [mkVisit('v1', 'p1', at(12, 30))],
        patients: [mkPatient('p1')],
      ).glance!;

      expect(glance.waiting, 0);
      expect(glance.averageWaitMinutes, isNull);
      expect(glance.total, 1);
    });
  });

  // -------------------------------------------------------------------------
  group('Up next', () {
    test('Day fixture: Kavya (token 7) is up next while Vikram is served', () {
      final upNext = dayDashboard().upNext!;

      expect(upNext.entryId, 'q_kavya');
      expect(upNext.name, 'Kavya Iyer');
      expect(upNext.tokenNumber, 7);
      expect(upNext.waitMinutes, 8); // 11:50 -> 11:58
      expect(upNext.isNextInCallOrder, isTrue);
      expect(upNext.servingName, 'Vikram Singh');
      expect(upNext.patient?.id, 'kavya');
    });

    test('urgent tokens come before normal ones, then the lower token', () {
      final upNext = schedule(queue: [
        mkToken('t2',
            number: 2,
            status: QueueStatus.completed,
            checkedIn: at(9, 0),
            walkInName: 'Done Already'),
        mkToken('t3', number: 3, checkedIn: at(10, 0), walkInName: 'Asha'),
        mkToken('t5',
            number: 5,
            priority: QueuePriority.urgent,
            checkedIn: at(10, 30),
            walkInName: 'Bala'),
        mkToken('t4',
            number: 4,
            priority: QueuePriority.urgent,
            checkedIn: at(10, 40),
            walkInName: 'Chetan'),
      ]).upNext!;

      expect(upNext.entryId, 't4');
      expect(upNext.name, 'Chetan');
      expect(upNext.tokenNumber, 4);
      expect(upNext.waitMinutes, 78); // 10:40 -> 11:58
      expect(upNext.isNextInCallOrder, isTrue);
    });

    test('among equal priority, the lower token wins over earlier check-in',
        () {
      final upNext = schedule(queue: [
        mkToken('t9', number: 9, checkedIn: at(10, 0), walkInName: 'Nine'),
        mkToken('t7', number: 7, checkedIn: at(10, 20), walkInName: 'Seven'),
      ]).upNext!;

      expect(upNext.entryId, 't7');
    });

    test('a pre-booked token checked in for a future time is booked, '
        'not waiting, and cannot be Up next', () {
      final data = schedule(
        queue: [
          mkToken('tp',
              number: 2,
              checkedIn: at(12, 30), // appointment time, after 11:58
              patientId: 'p1',
              visitId: 'v1'),
        ],
        visits: [mkVisit('v1', 'p1', at(12, 30))],
        patients: [mkPatient('p1')],
      );

      expect(data.upNext, isNull);
      expect(data.schedule, hasLength(1));
      final row = data.schedule!.single;
      expect(row.id, 'q_tp');
      expect(row.status, ScheduleStatus.booked);
      expect(row.waitMinutes, isNull);
      expect(data.glance!.waiting, 0);
      expect(data.nextBooking, at(12, 30));
    });

    test('a pre-booked token counts as waiting once its time has come', () {
      final data = schedule(
        queue: [
          mkToken('tp',
              number: 2, checkedIn: dayNow, patientId: 'p1', visitId: 'v1'),
        ],
        visits: [mkVisit('v1', 'p1', dayNow)],
        patients: [mkPatient('p1')],
      );

      expect(data.schedule!.single.status, ScheduleStatus.waiting);
      expect(data.upNext?.entryId, 'tp');
      expect(data.upNext?.waitMinutes, 0);
    });

    test('isNextInCallOrder is false when a future pre-booked token has a '
        'lower token number', () {
      final upNext = schedule(
        queue: [
          mkToken('future',
              number: 2,
              checkedIn: at(12, 30),
              patientId: 'p1',
              visitId: 'v1'),
          mkToken('arrived',
              number: 3, checkedIn: at(11, 40), walkInName: 'Deepak Kumar'),
        ],
        visits: [mkVisit('v1', 'p1', at(12, 30))],
        patients: [mkPatient('p1')],
      ).upNext!;

      expect(upNext.entryId, 'arrived');
      expect(upNext.name, 'Deepak Kumar');
      expect(upNext.waitMinutes, 18); // 11:40 -> 11:58
      expect(upNext.isNextInCallOrder, isFalse);
    });

    test('isNextInCallOrder is true when the future pre-booked token comes '
        'later in call order', () {
      final upNext = schedule(
        queue: [
          mkToken('arrived',
              number: 3, checkedIn: at(11, 40), walkInName: 'Deepak'),
          mkToken('future',
              number: 4,
              checkedIn: at(12, 30),
              patientId: 'p1',
              visitId: 'v1'),
        ],
        visits: [mkVisit('v1', 'p1', at(12, 30))],
        patients: [mkPatient('p1')],
      ).upNext!;

      expect(upNext.entryId, 'arrived');
      expect(upNext.isNextInCallOrder, isTrue);
    });

    test('servingName names the token in consultation', () {
      final upNext = schedule(
        queue: [
          mkToken('serving',
              number: 1,
              status: QueueStatus.inConsultation,
              checkedIn: at(11, 0),
              patientId: 'vik'),
          mkToken('next', number: 2, checkedIn: at(11, 30), walkInName: 'Esha'),
        ],
        patients: [mkPatient('vik', first: 'Vikram', last: 'Singh')],
      ).upNext!;

      expect(upNext.entryId, 'next');
      expect(upNext.servingName, 'Vikram Singh');
    });

    test('servingName names a called token (walk-in)', () {
      final upNext = schedule(queue: [
        mkToken('serving',
            number: 1,
            status: QueueStatus.called,
            checkedIn: at(11, 0),
            walkInName: 'Farhan'),
        mkToken('next', number: 2, checkedIn: at(11, 30), walkInName: 'Esha'),
      ]).upNext!;

      expect(upNext.servingName, 'Farhan');
    });

    test('servingName is null when nobody is being served', () {
      final upNext = schedule(queue: [
        mkToken('done',
            number: 1,
            status: QueueStatus.completed,
            checkedIn: at(10, 0),
            walkInName: 'Done'),
        mkToken('skipped',
            number: 2,
            status: QueueStatus.skipped,
            checkedIn: at(10, 30),
            walkInName: 'Skipped'),
        mkToken('next', number: 3, checkedIn: at(11, 30), walkInName: 'Esha'),
      ]).upNext!;

      expect(upNext.entryId, 'next');
      expect(upNext.servingName, isNull);
    });

    test('upNext is null when nobody is waiting', () {
      final data = schedule(queue: [
        mkToken('serving',
            number: 1,
            status: QueueStatus.inConsultation,
            checkedIn: at(11, 0),
            walkInName: 'Farhan'),
      ]);

      expect(data.upNext, isNull);
    });

    test('details for a returning patient (Kavya, Day fixture)', () {
      expect(
        dayDashboard().upNext!.details,
        '23 y · Female · Returning · Last visit 14 Aug, seasonal allergy',
      );
    });

    test('details use the most recent earlier non-cancelled visit', () {
      final upNext = schedule(
        queue: [mkToken('t1', checkedIn: at(11, 30), patientId: 'vik')],
        visits: [
          mkVisit('old', 'vik', DateTime(2026, 3, 1, 10),
              status: VisitStatus.completed),
          mkVisit('last', 'vik', DateTime(2026, 7, 2, 11),
              status: VisitStatus.completed),
          mkVisit('cancelled', 'vik', DateTime(2026, 9, 1, 10),
              status: VisitStatus.cancelled),
          mkVisit('deleted', 'vik', DateTime(2026, 9, 10, 10),
              status: VisitStatus.completed, deleted: true),
        ],
        patients: [
          mkPatient('vik',
              first: 'Vikram',
              last: 'Singh',
              gender: 'Male',
              dob: DateTime(1981, 5, 2)),
        ],
      ).upNext!;

      // No diagnosis recorded, so the last-visit part has no suffix.
      expect(upNext.details, '45 y · Male · Returning · Last visit 2 Jul');
    });

    test('details for a first-time patient', () {
      final upNext = schedule(
        queue: [mkToken('t1', checkedIn: at(11, 30), patientId: 'rohit')],
        patients: [
          mkPatient('rohit',
              first: 'Rohit',
              last: 'Sharma',
              gender: 'Male',
              dob: DateTime(1990, 1, 1)),
        ],
      ).upNext!;

      expect(upNext.details, '36 y · Male · New patient · First visit');
    });

    test('details for an unregistered walk-in', () {
      final upNext = schedule(queue: [
        mkToken('t1', checkedIn: at(11, 30), walkInName: 'Ramesh Patil'),
      ]).upNext!;

      expect(upNext.name, 'Ramesh Patil');
      expect(upNext.patient, isNull);
      expect(upNext.details, 'Walk-in · not registered');
    });

    test('reason falls back to the linked visit treatmentType', () {
      final data = schedule(
        queue: [
          mkToken('t1',
              number: 1,
              checkedIn: at(11, 30),
              patientId: 'p1',
              visitId: 'v1'),
        ],
        visits: [mkVisit('v1', 'p1', at(11, 30), treatment: 'Lower back pain')],
        patients: [mkPatient('p1')],
      );

      expect(data.upNext!.reason, 'Lower back pain');
      expect(data.schedule!.single.reason, 'Lower back pain');
    });

    test('a blank queue reason also falls back; a real one wins', () {
      final blank = schedule(
        queue: [
          mkToken('t1',
              checkedIn: at(11, 30),
              patientId: 'p1',
              visitId: 'v1',
              reason: '   '),
        ],
        visits: [mkVisit('v1', 'p1', at(11, 30), treatment: 'Viral fever')],
        patients: [mkPatient('p1')],
      );
      expect(blank.upNext!.reason, 'Viral fever');

      final own = schedule(
        queue: [
          mkToken('t1',
              checkedIn: at(11, 30),
              patientId: 'p1',
              visitId: 'v1',
              reason: ' Follow-up dressing '),
        ],
        visits: [mkVisit('v1', 'p1', at(11, 30), treatment: 'Viral fever')],
        patients: [mkPatient('p1')],
      );
      expect(own.upNext!.reason, 'Follow-up dressing');
    });
  });

  // -------------------------------------------------------------------------
  group('Schedule', () {
    test('Day fixture rows, in time order with the right statuses', () {
      final rows = dayDashboard().schedule!;

      expect(
        [for (final r in rows) '${DashFormat.time(r.time)} ${r.firstName}'],
        [
          '9:30 AM Priya',
          '9:50 AM Rahul',
          '10:10 AM Fatima',
          '10:30 AM Arjun',
          '11:00 AM Sunita',
          '11:30 AM Vikram',
          '11:50 AM Kavya',
          '11:55 AM Mohammed',
          '12:30 PM Lakshmi',
          '12:50 PM Rohan',
          '5:00 PM Sneha',
          '5:30 PM Anil',
          '6:10 PM Farah',
        ],
      );
      expect([for (final r in rows) r.status], [
        ...List.filled(5, ScheduleStatus.done),
        ScheduleStatus.inConsultation,
        ScheduleStatus.waiting,
        ScheduleStatus.waiting,
        ...List.filled(5, ScheduleStatus.booked),
      ]);
      expect([for (final r in rows) r.kindLabel], [
        'New patient', // Priya
        'New patient', // Rahul
        'New patient', // Fatima
        'New patient', // Arjun
        'New patient', // Sunita
        'Returning', // Vikram (2 Jul)
        'Returning', // Kavya (14 Aug)
        'New patient', // Mohammed
        'Returning', // Lakshmi (20 Jun)
        'Returning', // Rohan (1 Sep)
        'New patient', // Sneha
        'Returning', // Anil (30 Aug)
        'New patient', // Farah
      ]);
    });

    test('a queue token linked to a visit is one row, at the visit time', () {
      final rows = schedule(
        queue: [
          mkToken('q1',
              number: 6,
              status: QueueStatus.inConsultation,
              checkedIn: at(11, 35),
              patientId: 'p1',
              visitId: 'v1'),
        ],
        visits: [mkVisit('v1', 'p1', at(11, 30))],
        patients: [mkPatient('p1')],
      ).schedule!;

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.id, 'q_q1');
      expect(row.queueEntryId, 'q1');
      expect(row.visitId, 'v1');
      expect(row.time, at(11, 30));
      expect(row.status, ScheduleStatus.inConsultation);
      expect(row.tokenNumber, 6);
    });

    test('cancelled visits and cancelled tokens are excluded', () {
      final rows = schedule(
        queue: [
          mkToken('cancelledToken',
              number: 1,
              status: QueueStatus.cancelled,
              checkedIn: at(10, 0),
              walkInName: 'Gone'),
        ],
        visits: [
          mkVisit('cancelledVisit', 'p1', at(10, 30),
              status: VisitStatus.cancelled),
          mkVisit('kept', 'p2', at(12, 0)),
        ],
        patients: [mkPatient('p1'), mkPatient('p2')],
      ).schedule!;

      expect([for (final r in rows) r.id], ['v_kept']);
    });

    test('soft-deleted visits and tokens are excluded', () {
      final rows = schedule(
        queue: [
          mkToken('deletedToken',
              number: 1,
              checkedIn: at(10, 0),
              walkInName: 'Oops',
              deleted: true),
          mkToken('keptToken', number: 2, checkedIn: at(10, 5), walkInName: 'Ok'),
        ],
        visits: [
          mkVisit('deletedVisit', 'p1', at(10, 30), deleted: true),
          mkVisit('keptVisit', 'p2', at(12, 0)),
        ],
        patients: [mkPatient('p1'), mkPatient('p2')],
      ).schedule!;

      expect([for (final r in rows) r.id], ['q_keptToken', 'v_keptVisit']);
    });

    test('queue tokens and visits from another day are excluded', () {
      final rows = schedule(
        queue: [
          // Yesterday's token, still "waiting" because it was never closed.
          mkToken('yesterday',
              number: 4,
              checkedIn: DateTime(2026, 9, 22, 17, 0),
              walkInName: 'Stale'),
          // Checked in today but keyed to another queue date.
          mkToken('wrongKey',
              number: 5,
              checkedIn: at(9, 0),
              queueDate: '2026-09-22',
              walkInName: 'Mis-keyed'),
          mkToken('today', number: 1, checkedIn: at(9, 30), walkInName: 'Now'),
        ],
        visits: [
          mkVisit('vYesterday', 'p1', DateTime(2026, 9, 22, 12, 0)),
          mkVisit('vTomorrow', 'p1', DateTime(2026, 9, 24, 9, 30)),
        ],
        patients: [mkPatient('p1')],
      ).schedule!;

      expect([for (final r in rows) r.id], ['q_today']);
    });

    test('rows are sorted by time, ties broken by token number', () {
      final rows = schedule(
        queue: [
          mkToken('w5', number: 5, checkedIn: at(10, 15), walkInName: 'Five'),
          mkToken('w4', number: 4, checkedIn: at(10, 15), walkInName: 'Four'),
        ],
        visits: [
          mkVisit('evening', 'p1', at(17, 0)),
          mkVisit('morning', 'p2', at(9, 30)),
          mkVisit('noon', 'p3', at(12, 0)),
        ],
        patients: [mkPatient('p1'), mkPatient('p2'), mkPatient('p3')],
      ).schedule!;

      expect(
        [for (final r in rows) r.id],
        ['v_morning', 'q_w4', 'q_w5', 'v_noon', 'v_evening'],
      );
    });

    test("kindLabel 'Returning' when there is an earlier non-cancelled visit",
        () {
      final row = schedule(
        visits: [
          mkVisit('before', 'p1', DateTime(2026, 8, 1, 10),
              status: VisitStatus.completed),
          mkVisit('today', 'p1', at(12, 0)),
        ],
        patients: [mkPatient('p1')],
      ).schedule!.single;

      expect(row.kindLabel, 'Returning');
    });

    test("kindLabel 'New patient' when earlier visits were cancelled or "
        'deleted', () {
      final row = schedule(
        visits: [
          mkVisit('cancelled', 'p1', DateTime(2026, 8, 1, 10),
              status: VisitStatus.cancelled),
          mkVisit('deleted', 'p1', DateTime(2026, 8, 2, 10),
              status: VisitStatus.completed, deleted: true),
          mkVisit('today', 'p1', at(12, 0)),
        ],
        patients: [mkPatient('p1')],
      ).schedule!.single;

      expect(row.kindLabel, 'New patient');
    });

    test("an earlier visit today does not make a patient 'Returning'", () {
      final rows = schedule(
        visits: [
          mkVisit('morning', 'p1', at(9, 0), status: VisitStatus.completed),
          mkVisit('afternoon', 'p1', at(15, 0)),
        ],
        patients: [mkPatient('p1')],
      ).schedule!;

      expect([for (final r in rows) r.kindLabel], ['New patient', 'New patient']);
    });

    test("kindLabel 'Walk-in' for a token with no registered patient", () {
      final row = schedule(queue: [
        mkToken('w', checkedIn: at(10, 0), walkInName: 'Deepak Kumar'),
      ]).schedule!.single;

      expect(row.kindLabel, 'Walk-in');
      expect(row.name, 'Deepak Kumar');
      expect(row.firstName, 'Deepak');
      expect(row.ageSex, isNull);
      expect(row.patient, isNull);
    });

    test("kindLabel 'Home visit' for VisitType.home, even when returning", () {
      final rows = schedule(
        queue: [
          mkToken('qHome',
              number: 1, checkedIn: at(10, 0), patientId: 'p2', visitId: 'h2'),
        ],
        visits: [
          mkVisit('before', 'p1', DateTime(2026, 8, 1, 10),
              status: VisitStatus.completed),
          mkVisit('h1', 'p1', at(16, 0), type: VisitType.home),
          mkVisit('h2', 'p2', at(10, 0), type: VisitType.home),
        ],
        patients: [mkPatient('p1'), mkPatient('p2')],
      ).schedule!;

      expect([for (final r in rows) r.id], ['q_qHome', 'v_h1']);
      expect([for (final r in rows) r.kindLabel], ['Home visit', 'Home visit']);
    });

    test('Day fixture ageSex: Vikram 45 M, Kavya 23 F', () {
      final rows = dayDashboard().schedule!;
      String? ageSexOf(String first) =>
          rows.firstWhere((r) => r.firstName == first).ageSex;

      expect(ageSexOf('Vikram'), '45 M'); // born 2 May 1981
      expect(ageSexOf('Kavya'), '23 F'); // born 10 Feb 2003
    });

    test('ageSex is computed against now, not the wall clock', () {
      final now = DateTime(2031, 5, 5, 10, 0);
      DateTime on(int h) => DateTime(2031, 5, 5, h);
      final rows = schedule(
        now: now,
        visits: [
          mkVisit('a', 'birthdayToday', on(11)),
          mkVisit('b', 'birthdayTomorrow', on(12)),
          mkVisit('c', 'young', on(13)),
          mkVisit('d', 'noGender', on(14)),
        ],
        patients: [
          mkPatient('birthdayToday', gender: 'Male', dob: DateTime(1986, 5, 5)),
          mkPatient('birthdayTomorrow',
              gender: 'male', dob: DateTime(1990, 5, 6)),
          mkPatient('young', gender: 'Female', dob: DateTime(2008, 1, 1)),
          mkPatient('noGender', gender: '', dob: DateTime(1986, 1, 1)),
        ],
      ).schedule!;

      expect([for (final r in rows) r.ageSex], ['45 M', '40 M', '23 F', '45']);
    });

    test('waitMinutes is set only on waiting rows', () {
      final rows = schedule(
        queue: [
          mkToken('waiting', number: 1, checkedIn: at(11, 40), walkInName: 'W'),
          mkToken('called',
              number: 2,
              status: QueueStatus.called,
              checkedIn: at(11, 0),
              walkInName: 'C'),
          mkToken('consult',
              number: 3,
              status: QueueStatus.inConsultation,
              checkedIn: at(10, 50),
              walkInName: 'I'),
          mkToken('done',
              number: 4,
              status: QueueStatus.completed,
              checkedIn: at(10, 0),
              walkInName: 'D'),
          mkToken('skipped',
              number: 5,
              status: QueueStatus.skipped,
              checkedIn: at(10, 10),
              walkInName: 'S'),
        ],
        visits: [mkVisit('booked', 'p1', at(12, 30))],
        patients: [mkPatient('p1')],
      ).schedule!;

      final waits = {for (final r in rows) r.id: r.waitMinutes};
      expect(waits, {
        'q_done': null,
        'q_skipped': null,
        'q_consult': null,
        'q_called': null,
        'q_waiting': 18, // 11:40 -> 11:58
        'v_booked': null,
      });
    });

    test('tokenNumber is null when the token number is 0', () {
      final data = schedule(queue: [
        mkToken('zero', number: 0, checkedIn: at(11, 0), walkInName: 'Zero'),
        mkToken('five', number: 5, checkedIn: at(11, 10), walkInName: 'Five'),
      ]);

      final tokens = {for (final r in data.schedule!) r.id: r.tokenNumber};
      expect(tokens, {'q_zero': null, 'q_five': 5});
    });

    test('nextBooking is the first booked row not before now', () {
      final data = schedule(
        visits: [
          // Booked for 11:00 but never checked in: in the past, skipped.
          mkVisit('late', 'p1', at(11, 0)),
          mkVisit('done', 'p2', at(12, 0), status: VisitStatus.completed),
          mkVisit('evening', 'p3', at(17, 0)),
          mkVisit('next', 'p4', at(12, 30)),
        ],
        patients: [
          mkPatient('p1'),
          mkPatient('p2'),
          mkPatient('p3'),
          mkPatient('p4'),
        ],
      );

      expect(data.nextBooking, at(12, 30));
    });

    test('nextBooking includes a booking exactly at now', () {
      final data = schedule(
        visits: [mkVisit('now', 'p1', dayNow), mkVisit('later', 'p1', at(13, 0))],
        patients: [mkPatient('p1')],
      );

      expect(data.nextBooking, dayNow);
    });

    test('nextBooking is null when no booking is still ahead', () {
      final data = schedule(
        queue: [
          mkToken('w', number: 1, checkedIn: at(11, 30), walkInName: 'W'),
        ],
        visits: [
          mkVisit('late', 'p1', at(11, 0)),
          mkVisit('done', 'p2', at(12, 30), status: VisitStatus.completed),
          mkVisit('missed', 'p3', at(13, 0), status: VisitStatus.missed),
        ],
        patients: [mkPatient('p1'), mkPatient('p2'), mkPatient('p3')],
      );

      expect(data.nextBooking, isNull);
    });

    test('Day fixture nextBooking is Lakshmi at 12:30', () {
      expect(dayDashboard().nextBooking, at(12, 30));
    });
  });

  // -------------------------------------------------------------------------
  group('Revenue', () {
    test('collected today vs the same weekday last week, income only', () {
      final collected = buildDashboard(now: dayNow, revenue: [
        // Today (Wednesday 23 Sep).
        mkRevenue('t1', at(9, 15), 1500),
        mkRevenue('t2', at(18, 40), 1900),
        mkRevenue('tExpense', at(10, 0), 700, kind: TransactionKind.expense),
        mkRevenue('tDeleted', at(10, 5), 5000, deleted: true),
        // Wednesday 16 Sep.
        mkRevenue('w1', DateTime(2026, 9, 16, 10), 2800),
        mkRevenue('wExpense', DateTime(2026, 9, 16, 11), 300,
            kind: TransactionKind.expense),
        mkRevenue('wDeleted', DateTime(2026, 9, 16, 12), 1000, deleted: true),
        // Neither day.
        mkRevenue('yesterday', DateTime(2026, 9, 22, 10), 900),
        mkRevenue('eightDaysAgo', DateTime(2026, 9, 15, 10), 400),
      ]).collected!;

      expect(collected.today, 3400); // 1500 + 1900
      expect(collected.sameDayLastWeek, 2800);
      expect(collected.difference, 600);
      expect(collected.weekdayName, 'Wednesday');
    });

    test('collected is zero, not null, when nothing came in', () {
      final collected = buildDashboard(now: dayNow, revenue: const []).collected!;

      expect(collected.today, 0);
      expect(collected.sameDayLastWeek, 0);
    });

    test('collections: 7 days oldest first, today last, gaps are 0', () {
      final collections = buildDashboard(now: dayNow, revenue: [
        ...revenueFor(today: 3400),
        // On the closed Sunday: must not show up.
        mkRevenue('expense', DateTime(2026, 9, 20, 10), 999,
            kind: TransactionKind.expense),
        mkRevenue('deleted', DateTime(2026, 9, 20, 11), 999, deleted: true),
      ]).collections!;

      final days = collections.days;
      expect(days, hasLength(7));
      expect([for (final d in days) d.date], [
        for (var d = 17; d <= 23; d++) DateTime(2026, 9, d),
      ]);
      // 16 Sep is 7 days back, outside the window.
      expect(
        [for (final d in days) d.amount],
        [3100, 2800, 4200, 0, 3900, 3900, 3400],
      );
      expect([for (final d in days) d.isToday],
          [false, false, false, false, false, false, true]);
    });

    test('collections total and max', () {
      final collections = buildDashboard(
        now: dayNow,
        revenue: revenueFor(today: 3400),
      ).collections!;

      // 3100 + 2800 + 4200 + 0 + 3900 + 3900 + 3400.
      expect(collections.total, 21300);
      expect(collections.max, 4200);
    });

    test('collections span a month boundary', () {
      final days = buildDashboard(
        now: DateTime(2026, 10, 2, 9),
        revenue: [mkRevenue('r', DateTime(2026, 9, 27, 10), 500)],
      ).collections!.days;

      expect(days.first.date, DateTime(2026, 9, 26));
      expect(days.last.date, DateTime(2026, 10, 2));
      expect([for (final d in days) d.amount], [0, 500, 0, 0, 0, 0, 0]);
    });
  });

  // -------------------------------------------------------------------------
  group('Attention', () {
    test('low-stock items come first, most depleted first', () {
      final items = attentionFor([
        mkMedicine('a', 'Paracetamol 650', stock: 12, reorder: 20), // 0.6
        mkMedicine('b', 'Amoxicillin 500', stock: 0, reorder: 10), // 0.0
        mkMedicine('c', 'ORS', unit: 'sachets', stock: 5, reorder: 10), // 0.5
        mkMedicine('d', 'Ibuprofen 400', stock: 9, reorder: 10), // 0.9
        mkMedicine('e', 'Vitamin C', stock: 50, reorder: 10), // fine
      ]);

      expect([for (final i in items) i.title], [
        'Amoxicillin 500 is out of stock',
        'ORS is low',
        'Paracetamol 650 is low',
        'Ibuprofen 400 is low',
      ]);
      expect([for (final i in items) i.subtitle], [
        '0 strips · reorder level 10',
        '5 sachets · reorder level 10',
        '12 strips · reorder level 20',
        '9 strips · reorder level 10',
      ]);
      expect(items.every((i) => i.kind == AttentionKind.lowStock), isTrue);
      expect(items.every((i) => i.actionLabel == 'Reorder'), isTrue);
    });

    test('low-stock subtitle trims the unit and copes without one', () {
      final items = attentionFor([
        mkMedicine('a', 'Cotton rolls', unit: '', stock: 3, reorder: 10),
        mkMedicine('b', 'Betadine', unit: '  tubes ', stock: 2, reorder: 10),
      ]);

      expect([for (final i in items) i.subtitle], [
        '2 tubes · reorder level 10',
        '3 left · reorder level 10',
      ]);
    });

    test('expiring items follow low stock, soonest expiry first', () {
      final items = attentionFor([
        mkMedicine('cet', 'Cetirizine 10', expiry: DateTime(2026, 10, 2)),
        mkMedicine('para', 'Paracetamol 650', stock: 12, reorder: 20),
        mkMedicine('ins', 'Insulin pen',
            unit: 'pens', stock: 25, reorder: 5, expiry: DateTime(2026, 9, 20)),
        mkMedicine('azi', 'Azithromycin 500',
            stock: 30, expiry: DateTime(2026, 9, 23)),
        mkMedicine('vitd', 'Vitamin D3', stock: 60, expiry: DateTime(2099, 1, 1)),
      ]);

      expect([for (final i in items) i.kind], [
        AttentionKind.lowStock,
        AttentionKind.expiring,
        AttentionKind.expiring,
        AttentionKind.expiring,
      ]);
      expect([for (final i in items) i.title], [
        'Paracetamol 650 is low',
        'Insulin pen expired',
        'Azithromycin 500 expires today',
        'Cetirizine 10 expiring',
      ]);
      expect([for (final i in items) i.subtitle], [
        '12 strips · reorder level 20',
        '3 days ago · 25 pens in stock',
        '30 strips in stock',
        'In 9 days · 50 strips in stock',
      ]);
      expect(
        items.where((i) => i.kind == AttentionKind.expiring).map((i) => i.actionLabel),
        everyElement('Review'),
      );
    });

    test('expiry titles use singular days and ignore time of day', () {
      final items = attentionFor([
        mkMedicine('y', 'Cough syrup',
            unit: '', stock: 15, expiry: DateTime(2026, 9, 22, 23, 59)),
        mkMedicine('t', 'Ointment',
            unit: 'tubes', stock: 30, expiry: DateTime(2026, 9, 24, 0, 1)),
      ]);

      expect([for (final i in items) i.subtitle], [
        '1 day ago · 15 in stock',
        'In 1 day · 30 tubes in stock',
      ]);
    });

    test('a low-stock item that is also expiring is listed once, as low', () {
      final items = attentionFor([
        mkMedicine('cet', 'Cetirizine 10',
            stock: 5, reorder: 10, expiry: DateTime(2026, 10, 2)),
      ]);

      expect(items, hasLength(1));
      expect(items.single.kind, AttentionKind.lowStock);
      expect(items.single.title, 'Cetirizine 10 is low');
    });

    test('inactive medicines are excluded', () {
      final items = attentionFor([
        mkMedicine('a', 'Old stock', stock: 0, active: false),
        mkMedicine('b', 'Old batch',
            expiry: DateTime(2026, 9, 25), active: false),
        mkMedicine('c', 'Current', stock: 1, reorder: 10),
      ]);

      expect([for (final i in items) i.title], ['Current is low']);
    });

    test('at most maxAttentionItems (default 3), most urgent kept', () {
      final meds = [
        mkMedicine('a', 'A', stock: 8, reorder: 10),
        mkMedicine('b', 'B', stock: 1, reorder: 10),
        mkMedicine('c', 'C', stock: 6, reorder: 10),
        mkMedicine('d', 'D', stock: 3, reorder: 10),
        mkMedicine('e', 'E', expiry: DateTime(2026, 9, 30)),
      ];

      final byDefault = buildDashboard(now: dayNow, medicines: meds).attention!;
      expect([for (final i in byDefault) i.title],
          ['B is low', 'D is low', 'C is low']);

      final two = buildDashboard(
        now: dayNow,
        medicines: meds,
        maxAttentionItems: 2,
      ).attention!;
      expect(two, hasLength(2));
    });

    test('nothing to flag gives an empty list, not null', () {
      expect(
        attentionFor([mkMedicine('ok', 'Fine', stock: 100)]),
        isEmpty,
      );
    });

    // The builder is documented as pure ("everything it knows comes from
    // its arguments"), so the 30-day expiry window must be measured from
    // `now`, like the day count in the title is.
    test('expiry window is measured from now, not the wall clock '
        '(item 9 days out is listed)', () {
      final items = attentionFor(
        [mkMedicine('x', 'Adrenaline', expiry: DateTime(2040, 1, 10))],
        now: DateTime(2040, 1, 1, 9),
      );

      expect(
        [for (final i in items) i.subtitle],
        ['In 9 days · 50 strips in stock'],
        reason: '_buildAttention filters on MedicineModel.isExpiringSoon, '
            'which reads DateTime.now() instead of the `now` argument',
      );
    });

    test('expiry window is measured from now, not the wall clock '
        '(item 152 days out is not listed)', () {
      final items = attentionFor(
        [mkMedicine('x', 'Adrenaline', expiry: DateTime(2020, 6, 1))],
        now: DateTime(2020, 1, 1, 9),
      );

      expect(
        [for (final i in items) i.title],
        isEmpty,
        reason: '_buildAttention filters on MedicineModel.isExpiringSoon, '
            'which reads DateTime.now() instead of the `now` argument',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('Null inputs (still loading)', () {
    final revenue = revenueFor(today: 3400);

    void expectScheduleSectionsNull(DashboardData d) {
      expect(d.schedule, isNull);
      expect(d.glance, isNull);
      expect(d.upNext, isNull);
      expect(d.nextBooking, isNull);
      expect(d.scheduleReady, isFalse);
    }

    test('queue null -> schedule, glance and upNext null', () {
      final d = buildDashboard(
        now: dayNow,
        visits: dayVisits,
        patients: fixturePatients,
        revenue: revenue,
        medicines: fixtureMedicines,
      );
      expectScheduleSectionsNull(d);
      expect(d.collected, isNotNull);
      expect(d.attention, isNotNull);
    });

    test('visits null -> schedule, glance and upNext null', () {
      expectScheduleSectionsNull(buildDashboard(
        now: dayNow,
        queue: dayQueue,
        patients: fixturePatients,
      ));
    });

    test('patients null -> schedule, glance and upNext null', () {
      expectScheduleSectionsNull(buildDashboard(
        now: dayNow,
        queue: dayQueue,
        visits: dayVisits,
      ));
    });

    test('revenue null -> collected and collections null', () {
      final d = buildDashboard(
        now: dayNow,
        queue: dayQueue,
        visits: dayVisits,
        patients: fixturePatients,
        medicines: fixtureMedicines,
      );
      expect(d.collected, isNull);
      expect(d.collections, isNull);
      expect(d.schedule, isNotNull);
      expect(d.attention, isNotNull);
    });

    test('medicines null -> attention null', () {
      final d = buildDashboard(
        now: dayNow,
        queue: dayQueue,
        visits: dayVisits,
        patients: fixturePatients,
        revenue: revenue,
      );
      expect(d.attention, isNull);
      expect(d.collections, isNotNull);
      expect(d.glance, isNotNull);
    });

    test('everything null -> only now is set', () {
      final d = buildDashboard(now: dayNow);
      expect(d.now, dayNow);
      expectScheduleSectionsNull(d);
      expect(d.collected, isNull);
      expect(d.collections, isNull);
      expect(d.attention, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('DashFormat', () {
    test('rupees uses Indian digit grouping', () {
      expect(DashFormat.rupees(21300), '₹21,300');
      expect(DashFormat.rupees(100000), '₹1,00,000');
      expect(DashFormat.rupees(1234567), '₹12,34,567');
      expect(DashFormat.rupees(950), '₹950');
      expect(DashFormat.rupees(0), '₹0');
      expect(DashFormat.rupees(949.6), '₹950'); // rounded
    });

    test('rupeesCompact', () {
      expect(DashFormat.rupeesCompact(950), '₹950');
      expect(DashFormat.rupeesCompact(3400), '₹3.4k');
      expect(DashFormat.rupeesCompact(3000), '₹3k');
      expect(DashFormat.rupeesCompact(21300), '₹21.3k');
      expect(DashFormat.rupeesCompact(100000), '₹1L');
      expect(DashFormat.rupeesCompact(120000), '₹1.2L');
      expect(DashFormat.rupeesCompact(11000000), '₹1.1Cr');
      // Unit chosen after rounding: no "₹100k" or "₹100L".
      expect(DashFormat.rupeesCompact(99960), '₹1L');
      expect(DashFormat.rupeesCompact(9996000), '₹1Cr');
      expect(DashFormat.rupeesCompact(999.6), '₹1k');
    });

    test('timeParts splits clock time and AM/PM', () {
      expect(DashFormat.timeParts(at(11, 30)), ('11:30', 'AM'));
      expect(DashFormat.timeParts(at(18, 5)), ('6:05', 'PM'));
      expect(DashFormat.timeParts(at(0, 15)), ('12:15', 'AM'));
      expect(DashFormat.timeParts(at(12, 0)), ('12:00', 'PM'));
    });

    test('time', () {
      expect(DashFormat.time(at(9, 30)), '9:30 AM');
      expect(DashFormat.time(at(18, 10)), '6:10 PM');
    });

    test('timeRange within one half of the day names AM/PM once', () {
      expect(DashFormat.timeRange(at(17, 0), at(18, 10)), '5:00 to 6:10 PM');
      expect(DashFormat.timeRange(at(9, 30), at(11, 45)), '9:30 to 11:45 AM');
    });

    test('timeRange across noon names AM/PM on both ends', () {
      expect(
        DashFormat.timeRange(at(9, 30), at(18, 10)),
        '9:30 AM to 6:10 PM',
      );
      expect(
        DashFormat.timeRange(at(11, 30), at(12, 15)),
        '11:30 AM to 12:15 PM',
      );
    });

    test('greeting boundaries', () {
      expect(DashFormat.greeting(at(5, 0)), 'Good morning');
      expect(DashFormat.greeting(at(11, 59)), 'Good morning');
      expect(DashFormat.greeting(at(12, 0)), 'Good afternoon');
      expect(DashFormat.greeting(at(16, 59)), 'Good afternoon');
      expect(DashFormat.greeting(at(17, 0)), 'Good evening');
      expect(DashFormat.greeting(at(23, 30)), 'Good evening');
    });

    test('names lists up to 5, then "A, B, C, D and N more"', () {
      expect(DashFormat.names(const []), '');
      expect(DashFormat.names(const ['Priya']), 'Priya');
      expect(
        DashFormat.names(const ['Priya', 'Rahul', 'Fatima', 'Arjun', 'Sunita']),
        'Priya, Rahul, Fatima, Arjun, Sunita',
      );
      expect(
        DashFormat.names(
            const ['Priya', 'Rahul', 'Fatima', 'Arjun', 'Sunita', 'Vikram']),
        'Priya, Rahul, Fatima, Arjun and 2 more',
      );
      expect(
        DashFormat.names([for (var i = 0; i < 11; i++) 'P$i']),
        'P0, P1, P2, P3 and 7 more',
      );
      expect(DashFormat.names(const ['A', 'B', 'C'], max: 2), 'A and 2 more');
    });

    test('dayInitials', () {
      expect(DashFormat.dayInitials(DateTime(2026, 9, 23)), 'We');
      expect(DashFormat.dayInitials(DateTime(2026, 9, 24)), 'Th');
      expect(DashFormat.dayInitials(DateTime(2026, 9, 26)), 'Sa');
      expect(DashFormat.dayInitials(DateTime(2026, 9, 27)), 'Su');
    });

    test('dates', () {
      expect(DashFormat.dateLine(dayNow), 'Wednesday, 23 September');
      expect(DashFormat.shortDate(DateTime(2026, 8, 14)), '14 Aug');
      expect(DashFormat.weekday(dayNow), 'Wednesday');
    });

    test('plural', () {
      expect(DashFormat.plural(1, 'day'), '1 day');
      expect(DashFormat.plural(0, 'day'), '0 days');
      expect(DashFormat.plural(3, 'day'), '3 days');
      expect(DashFormat.plural(1, 'person', 'people'), '1 person');
      expect(DashFormat.plural(2, 'person', 'people'), '2 people');
    });

    test('minutes', () {
      expect(DashFormat.minutes(12), '12 min');
    });
  });
}
