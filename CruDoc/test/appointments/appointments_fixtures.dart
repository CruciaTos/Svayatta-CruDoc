// Test-only sample data mirroring the Appointments mock-ups
// (design/clinic-redesign/screens/appointments-1-day.png and
// appointments-2-day-overlap.png). Never imported by app code.

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';

/// Wednesday 23 September 2026, 11:48 AM, as in the mock-ups.
final DateTime apptsNow = DateTime(2026, 9, 23, 11, 48);

/// The mock-up day (date only).
final DateTime apptsDay = DateTime(2026, 9, 23);

DateTime _today(int h, int m) => DateTime(2026, 9, 23, h, m);

// ---------------------------------------------------------------------------
// Patients
// ---------------------------------------------------------------------------

Patient apptPatient(
  String id,
  String first,
  String last, {
  required String gender,
  required DateTime dob,
  String phone = '98200 00000',
}) =>
    Patient(
      id: id,
      firstName: first,
      lastName: last,
      phone: phone,
      gender: gender,
      dateOfBirth: dob,
      diagnosis: const [],
      packageBalance: 0,
      isArchived: false,
      createdAt: DateTime(2025, 6, 1),
      updatedAt: DateTime(2025, 6, 1),
    );

final Patient priyaNair = apptPatient('a_priya', 'Priya', 'Nair',
    gender: 'Female', dob: DateTime(1991, 3, 4), phone: '9820011001');
final Patient rahulVerma = apptPatient('a_rahul', 'Rahul', 'Verma',
    gender: 'Male', dob: DateTime(1968, 1, 19), phone: '9820011002');
final Patient fatimaShaikh = apptPatient('a_fatima', 'Fatima', 'Shaikh',
    gender: 'Female', dob: DateTime(1979, 5, 30), phone: '9820011003');
final Patient arjunPatil = apptPatient('a_arjun', 'Arjun', 'Patil',
    gender: 'Male', dob: DateTime(2014, 2, 8), phone: '9820011004');
final Patient sunitaJoshi = apptPatient('a_sunita', 'Sunita', 'Joshi',
    gender: 'Female', dob: DateTime(1961, 4, 2), phone: '9820011005');
final Patient vikramSingh = apptPatient('a_vikram', 'Vikram', 'Singh',
    gender: 'Male', dob: DateTime(1983, 12, 11), phone: '9820011006');

/// 23 y · Female · Returning · Token 7, allergic to penicillin.
final Patient kavyaIyer = apptPatient('a_kavya', 'Kavya', 'Iyer',
    gender: 'Female', dob: DateTime(2003, 2, 14), phone: '9820011007');
final Patient mohammedAnsari = apptPatient('a_mohammed', 'Mohammed', 'Ansari',
    gender: 'Male', dob: DateTime(1975, 7, 21), phone: '9820011008');
final Patient lakshmiReddy = apptPatient('a_lakshmi', 'Lakshmi', 'Reddy',
    gender: 'Female', dob: DateTime(1958, 6, 17), phone: '9820011009');
final Patient rohanMehta = apptPatient('a_rohan', 'Rohan', 'Mehta',
    gender: 'Male', dob: DateTime(1996, 1, 25), phone: '9820011010');
final Patient snehaKulkarni = apptPatient('a_sneha', 'Sneha', 'Kulkarni',
    gender: 'Female', dob: DateTime(1993, 11, 3), phone: '9820011011');
final Patient anilGupta = apptPatient('a_anil', 'Anil', 'Gupta',
    gender: 'Male', dob: DateTime(1964, 8, 9), phone: '9820011012');
final Patient farahKhan = apptPatient('a_farah', 'Farah', 'Khan',
    gender: 'Female', dob: DateTime(1999, 10, 28), phone: '9820011013');

/// Booked today at 10:52 AM for 12:30 PM, on top of Lakshmi Reddy.
final Patient nehaJoshi = apptPatient('a_neha', 'Neha', 'Joshi',
    gender: 'Female', dob: DateTime(1997, 5, 12), phone: '9820011014');

final List<Patient> apptsPatients = [
  priyaNair,
  rahulVerma,
  fatimaShaikh,
  arjunPatil,
  sunitaJoshi,
  vikramSingh,
  kavyaIyer,
  mohammedAnsari,
  lakshmiReddy,
  rohanMehta,
  snehaKulkarni,
  anilGupta,
  farahKhan,
  nehaJoshi,
];

// ---------------------------------------------------------------------------
// Visits
// ---------------------------------------------------------------------------

Visit apptVisit(
  String id,
  Patient patient,
  DateTime start, {
  int minutes = 20,
  VisitStatus status = VisitStatus.scheduled,
  String? reason,
  DateTime? createdAt,
}) =>
    Visit(
      id: id,
      patientId: patient.id,
      scheduledStart: start,
      durationMinutes: minutes,
      address: 'Clinic',
      status: status,
      treatmentType: reason,
      createdAt: createdAt ?? DateTime(2026, 9, 16, 10),
      updatedAt: createdAt ?? DateTime(2026, 9, 16, 10),
    );

const _done = VisitStatus.completed;

/// An earlier visit, so the patient reads "Returning" (no "New").
Visit _earlier(Patient p) => apptVisit(
      'past_${p.id}',
      p,
      DateTime(2026, 6, 10, 10),
      status: _done,
      reason: 'Consultation',
      createdAt: DateTime(2026, 6, 1),
    );

/// The 13 visits of the mock-up day (5 seen, 1 in consultation,
/// 2 waiting, 5 booked) plus earlier visits for returning patients.
final List<Visit> apptsVisits = [
  for (final p in [
    priyaNair,
    rahulVerma,
    fatimaShaikh,
    arjunPatil,
    sunitaJoshi,
    vikramSingh,
    kavyaIyer,
    lakshmiReddy,
    rohanMehta,
    anilGupta,
  ])
    _earlier(p),
  apptVisit('v_priya', priyaNair, _today(9, 30),
      status: _done, reason: 'Fever for 3 days'),
  apptVisit('v_rahul', rahulVerma, _today(9, 50),
      status: _done, reason: 'BP follow-up'),
  apptVisit('v_fatima', fatimaShaikh, _today(10, 15),
      status: _done, reason: 'Thyroid review'),
  apptVisit('v_arjun', arjunPatil, _today(10, 40),
      status: _done, reason: 'Cough and cold'),
  apptVisit('v_sunita', sunitaJoshi, _today(11, 5),
      status: _done, reason: 'Diabetes follow-up'),
  apptVisit('v_vikram', vikramSingh, _today(11, 30), reason: 'Lower back pain'),
  apptVisit('v_kavya', kavyaIyer, _today(11, 50), reason: 'Skin rash'),
  apptVisit('v_mohammed', mohammedAnsari, _today(12, 10),
      reason: 'General check-up'),
  apptVisit('v_lakshmi', lakshmiReddy, _today(12, 30),
      reason: 'BP review, knee pain', createdAt: DateTime(2026, 9, 20, 17, 5)),
  apptVisit('v_rohan', rohanMehta, _today(12, 50), reason: 'Viral fever'),
  apptVisit('v_sneha', snehaKulkarni, _today(17, 0), reason: 'Migraine'),
  apptVisit('v_anil', anilGupta, _today(17, 30), reason: 'Diabetes review'),
  apptVisit('v_farah', farahKhan, _today(18, 10), reason: 'Dry cough'),
];

/// Neha Joshi, booked today at 10:52 AM into Lakshmi Reddy's 12:30 slot.
final Visit nehaOverlapVisit = apptVisit(
  'v_neha',
  nehaJoshi,
  _today(12, 30),
  reason: 'Fever, body ache',
  createdAt: _today(10, 52),
);

/// The overlap mock-up: the day plus Neha's visit (listed after
/// Lakshmi's, so Lakshmi takes the left column).
final List<Visit> apptsOverlapVisits = [...apptsVisits, nehaOverlapVisit];

// ---------------------------------------------------------------------------
// Today's queue: Vikram in consultation, Kavya (8 min) and Mohammed waiting.
// ---------------------------------------------------------------------------

QueueEntry _queue(
  String id,
  Patient p,
  String visitId,
  int token,
  QueueStatus status,
  DateTime checkedIn,
) =>
    QueueEntry(
      id: id,
      patientId: p.id,
      tokenNumber: token,
      queueDate: '2026-09-23',
      status: status,
      checkedInAt: checkedIn,
      consultationStartedAt:
          status == QueueStatus.inConsultation ? _today(11, 34) : null,
      linkedVisitId: visitId,
      createdAt: checkedIn,
      updatedAt: checkedIn,
    );

final List<QueueEntry> apptsQueue = [
  _queue('q_vikram', vikramSingh, 'v_vikram', 6, QueueStatus.inConsultation,
      _today(11, 22)),
  _queue('q_kavya', kavyaIyer, 'v_kavya', 7, QueueStatus.waiting,
      _today(11, 40)),
  _queue('q_mohammed', mohammedAnsari, 'v_mohammed', 8, QueueStatus.waiting,
      _today(11, 45)),
];

// ---------------------------------------------------------------------------
// Case sheets: the one recorded allergy.
// ---------------------------------------------------------------------------

final Map<String, HomeopathyCaseSheet> apptsCaseSheets = {
  kavyaIyer.id: HomeopathyCaseSheet.empty(
    id: 'cs_kavya',
    patientId: kavyaIyer.id,
    doctorId: '',
  ).copyWith(
    medicalHistory: const HomeopathyMedicalHistory(allergies: 'penicillin'),
  ),
};
