// Test-only sample data mirroring the design mock-ups
// (design/dashboard-redesign/screens). Never imported by app code.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';

/// Wednesday 23 September 2026, as in the mock-ups.
final DateTime dayNow = DateTime(2026, 9, 23, 11, 58);
final DateTime eveningNow = DateTime(2026, 9, 23, 18, 14);

DateTime _at(int h, int m) => DateTime(2026, 9, 23, h, m);

Patient _patient(
  String id,
  String first,
  String last,
  String gender,
  DateTime dob, {
  List<String> diagnosis = const [],
}) =>
    Patient(
      id: id,
      firstName: first,
      lastName: last,
      phone: '9820012345',
      gender: gender,
      dateOfBirth: dob,
      diagnosis: diagnosis,
      packageBalance: 0,
      isArchived: false,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

final List<Patient> fixturePatients = [
  _patient('priya', 'Priya', 'Nair', 'Female', DateTime(1990, 4, 2)),
  _patient('rahul', 'Rahul', 'Verma', 'Male', DateTime(1985, 7, 9)),
  _patient('fatima', 'Fatima', 'Shaikh', 'Female', DateTime(1979, 1, 30)),
  _patient('arjun', 'Arjun', 'Rao', 'Male', DateTime(2001, 11, 12)),
  _patient('sunita', 'Sunita', 'Joshi', 'Female', DateTime(1968, 6, 5)),
  _patient('vikram', 'Vikram', 'Singh', 'Male', DateTime(1981, 5, 2)),
  _patient('kavya', 'Kavya', 'Iyer', 'Female', DateTime(2003, 2, 10),
      diagnosis: ['seasonal allergy']),
  _patient('mohammed', 'Mohammed', 'Ansari', 'Male', DateTime(1988, 1, 15)),
  _patient('lakshmi', 'Lakshmi', 'Reddy', 'Female', DateTime(1959, 3, 3)),
  _patient('rohan', 'Rohan', 'Mehta', 'Male', DateTime(1995, 6, 20)),
  _patient('sneha', 'Sneha', 'Kulkarni', 'Female', DateTime(1992, 8, 8)),
  _patient('anil', 'Anil', 'Gupta', 'Male', DateTime(1970, 2, 14)),
  _patient('farah', 'Farah', 'Khan', 'Female', DateTime(1992, 3, 1)),
  _patient('neha', 'Neha', 'Das', 'Female', DateTime(1987, 12, 1)),
  _patient('karan', 'Karan', 'Malhotra', 'Male', DateTime(1975, 9, 30)),
  _patient('meera', 'Meera', 'Pillai', 'Female', DateTime(1999, 10, 21)),
  _patient('dev', 'Dev', 'Chopra', 'Male', DateTime(1983, 4, 17)),
  _patient('isha', 'Isha', 'Bose', 'Female', DateTime(1996, 7, 7)),
  _patient('omar', 'Omar', 'Qureshi', 'Male', DateTime(1964, 5, 25)),
];

Visit _visit(
  String id,
  String patientId,
  DateTime start, {
  VisitStatus status = VisitStatus.scheduled,
  String? reason,
}) =>
    Visit(
      id: id,
      patientId: patientId,
      scheduledStart: start,
      durationMinutes: 15,
      address: '',
      status: status,
      treatmentType: reason,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

QueueEntry _token(
  String id,
  int token,
  QueueStatus status,
  DateTime checkedIn, {
  String? patientId,
  String? visitId,
  String? reason,
}) =>
    QueueEntry(
      id: id,
      patientId: patientId,
      tokenNumber: token,
      queueDate: '2026-09-23',
      status: status,
      reason: reason,
      checkedInAt: checkedIn,
      linkedVisitId: visitId,
      createdAt: checkedIn,
      updatedAt: checkedIn,
    );

/// Earlier visits that make patients "Returning".
final List<Visit> _history = [
  _visit('h_kavya', 'kavya', DateTime(2026, 8, 14, 10),
      status: VisitStatus.completed),
  _visit('h_vikram', 'vikram', DateTime(2026, 7, 2, 11),
      status: VisitStatus.completed),
  _visit('h_lakshmi', 'lakshmi', DateTime(2026, 6, 20, 12),
      status: VisitStatus.completed),
  _visit('h_rohan', 'rohan', DateTime(2026, 9, 1, 17),
      status: VisitStatus.completed),
  _visit('h_anil', 'anil', DateTime(2026, 8, 30, 17),
      status: VisitStatus.completed),
];

/// Day mock-up: 5 seen, Vikram in consultation, Kavya and Mohammed
/// waiting, two booked, three booked for the evening.
final List<Visit> dayVisits = [
  ..._history,
  _visit('v_priya', 'priya', _at(9, 30), status: VisitStatus.completed),
  _visit('v_rahul', 'rahul', _at(9, 50), status: VisitStatus.completed),
  _visit('v_fatima', 'fatima', _at(10, 10), status: VisitStatus.completed),
  _visit('v_arjun', 'arjun', _at(10, 30), status: VisitStatus.completed),
  _visit('v_sunita', 'sunita', _at(11, 0), status: VisitStatus.completed),
  _visit('v_vikram', 'vikram', _at(11, 30), reason: 'Lower back pain'),
  _visit('v_kavya', 'kavya', _at(11, 50),
      reason: 'Skin rash on both forearms, itching for 5 days.'),
  _visit('v_lakshmi', 'lakshmi', _at(12, 30), reason: 'BP review, knee pain'),
  _visit('v_rohan', 'rohan', _at(12, 50), reason: 'Viral fever'),
  _visit('v_sneha', 'sneha', _at(17, 0), reason: 'Thyroid review'),
  _visit('v_anil', 'anil', _at(17, 30), reason: 'Diabetes review'),
  _visit('v_farah', 'farah', _at(18, 10), reason: 'Dry cough'),
];

final List<QueueEntry> dayQueue = [
  _token('q_vikram', 6, QueueStatus.inConsultation, _at(11, 30),
      patientId: 'vikram', visitId: 'v_vikram'),
  _token('q_kavya', 7, QueueStatus.waiting, _at(11, 50),
      patientId: 'kavya', visitId: 'v_kavya'),
  _token('q_mohammed', 8, QueueStatus.waiting, _at(11, 55),
      patientId: 'mohammed', reason: 'General check-up'),
];

/// Evening mock-up: 11 seen, Anil in consultation, Farah waiting.
final List<Visit> eveningVisits = [
  ..._history,
  for (final (id, h, m) in [
    ('priya', 9, 30), ('rahul', 9, 50), ('fatima', 10, 10),
    ('arjun', 10, 30), ('sunita', 11, 0), ('vikram', 11, 30),
    ('kavya', 11, 50), ('lakshmi', 12, 30), ('rohan', 12, 50),
    ('sneha', 17, 0),
  ])
    _visit('v_$id', id, _at(h, m), status: VisitStatus.completed),
  _visit('v_anil', 'anil', _at(17, 30), reason: 'Diabetes review'),
  _visit('v_farah', 'farah', _at(18, 10),
      reason: 'Dry cough for a week, worse at night.'),
];

final List<QueueEntry> eveningQueue = [
  _token('q_mohammed', 8, QueueStatus.completed, _at(11, 55),
      patientId: 'mohammed', reason: 'General check-up'),
  _token('q_anil', 12, QueueStatus.inConsultation, _at(17, 30),
      patientId: 'anil', visitId: 'v_anil'),
  _token('q_farah', 13, QueueStatus.waiting, _at(18, 10),
      patientId: 'farah', visitId: 'v_farah'),
];

/// Tomorrow's bookings (for the evening Wrap up).
final List<Visit> tomorrowVisits = [
  for (var i = 0; i < 9; i++)
    _visit('t_$i', fixturePatients[i].id,
        DateTime(2026, 9, 24, 9, 30).add(Duration(minutes: 20 * i))),
];

RevenueEntry _income(DateTime day, double amount) => RevenueEntry(
      id: 'r_${day.toIso8601String()}',
      date: day.add(const Duration(hours: 12)),
      description: 'Consultations',
      amount: amount,
      type: RevenueType.visit,
      createdAt: day,
      updatedAt: day,
    );

List<RevenueEntry> revenueFor({required double today}) => [
      _income(DateTime(2026, 9, 16), today == 3400 ? 2800 : 5800),
      _income(DateTime(2026, 9, 17), 3100),
      _income(DateTime(2026, 9, 18), 2800),
      _income(DateTime(2026, 9, 19), 4200),
      // Sunday closed.
      _income(DateTime(2026, 9, 21), 3900),
      _income(DateTime(2026, 9, 22), 3900),
      _income(DateTime(2026, 9, 23), today),
    ];

final List<MedicineModel> fixtureMedicines = [
  MedicineModel(
    id: 'm_para',
    name: 'Paracetamol 650',
    unit: 'strips',
    currentStock: 12,
    reorderThreshold: 20,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  ),
  MedicineModel(
    id: 'm_cet',
    name: 'Cetirizine 10',
    unit: 'strips',
    currentStock: 40,
    reorderThreshold: 10,
    expiryDate: DateTime(2026, 10, 2),
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  ),
];

const DoctorIdentity fixtureIdentity = DoctorIdentity(
  fullName: 'Dr. Ananya Deshpande',
  clinicName: 'Sanjeevani Clinic',
  specialty: 'General Physician',
);

const DoctorSubscriptionInfo fixturePlan = DoctorSubscriptionInfo(
  planName: 'Starter',
  doctorStatus: 'trial',
  isExpired: false,
  daysRemaining: 12,
  enabledModules: [],
);

/// Provider overrides for the Day (11:58) or Evening (18:14) mock-up.
List<Override> dashboardOverrides({
  required bool evening,
  bool emptyQueue = false,
}) {
  final now = evening ? eveningNow : dayNow;
  final visits = [...(evening ? eveningVisits : dayVisits), ...tomorrowVisits];
  final queue = emptyQueue
      ? const <QueueEntry>[]
      : (evening ? eveningQueue : dayQueue);
  return [
    dashboardNowProvider.overrideWithValue(now),
    todaysQueueProvider.overrideWith((ref) => Stream.value(queue)),
    allVisitsProvider.overrideWith((ref) => Stream.value(visits)),
    patientsStreamProvider.overrideWith((ref) => Stream.value(fixturePatients)),
    recentRevenueEntriesProvider.overrideWith(
      (ref) => Stream.value(revenueFor(today: evening ? 6900 : 3400)),
    ),
    medicinesStreamProvider.overrideWith(
      (ref) => Stream.value(fixtureMedicines),
    ),
    doctorIdentityProvider.overrideWithValue(fixtureIdentity),
    subscriptionInfoProvider.overrideWith((ref) => Stream.value(fixturePlan)),
  ];
}

bool _geistLoaded = false;

/// Loads the bundled Geist TTFs so text renders with real metrics.
Future<void> loadGeist() async {
  if (_geistLoaded) return;
  final loader = FontLoader('Geist');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/Geist/Geist-$w.ttf'));
  }
  await loader.load();
  _geistLoaded = true;
}
