// Test-only sample data mirroring the Patients mock-ups
// (design/patients-redesign/screens). Never imported by app code.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';

/// Wednesday 23 September 2026, 11:58, as in the mock-ups.
final DateTime patientsNow = DateTime(2026, 9, 23, 11, 58);

DateTime _d(int month, int day, [int h = 0, int m = 0]) =>
    DateTime(2026, month, day, h, m);

// ---------------------------------------------------------------------------
// Patients
// ---------------------------------------------------------------------------

Patient fixturePatient(
  String id,
  String first,
  String last, {
  required String gender,
  required DateTime dob,
  required String phone,
  List<String> diagnosis = const [],
  double balance = 0,
  DateTime? createdAt,
}) =>
    Patient(
      id: id,
      firstName: first,
      lastName: last,
      phone: phone,
      gender: gender,
      dateOfBirth: dob,
      diagnosis: diagnosis,
      packageBalance: balance,
      isArchived: false,
      createdAt: createdAt ?? DateTime(2025, 6, 1),
      updatedAt: createdAt ?? DateTime(2025, 6, 1),
    );

// Birthdays are kept well away from 23 September so the ages in the
// mock-ups (30, 42, 9, 35, 51, 19, 27, 63 …) hold for most of the year.
// `Patient.age` reads the real clock, so they shift once a year.
final Patient sohamBoridkar = fixturePatient(
  'p_soham', 'Soham', 'Boridkar',
  gender: 'Male', dob: DateTime(1996, 3, 14), phone: '9321559182',
  diagnosis: const ['Ectopic upper canine'], balance: 6000,
  createdAt: _d(9, 7, 19, 0),
);
final Patient meeraJoshi = fixturePatient(
  'p_meera', 'Meera', 'Joshi',
  gender: 'Female', dob: DateTime(1984, 2, 11), phone: '9820041736',
  diagnosis: const ['Crown, tooth 46'],
  createdAt: DateTime(2025, 11, 4),
);
final Patient aaravNair = fixturePatient(
  'p_aarav', 'Aarav', 'Nair',
  gender: 'Male', dob: DateTime(2017, 5, 20), phone: '9004027815',
  diagnosis: const ['Early caries, milk teeth'],
  createdAt: DateTime(2026, 3, 2),
);
final Patient rukhsanaShaikh = fixturePatient(
  'p_rukhsana', 'Rukhsana', 'Shaikh',
  gender: 'Female', dob: DateTime(1991, 1, 8), phone: '9769013308',
  diagnosis: const ['Gingivitis'], balance: 800,
  createdAt: DateTime(2026, 8, 19),
);
final Patient vivekPatil = fixturePatient(
  'p_vivek', 'Vivek', 'Patil',
  gender: 'Male', dob: DateTime(1975, 6, 2), phone: '9930176524',
  diagnosis: const ['Missing teeth 36, 37'], balance: 42000,
  createdAt: DateTime(2026, 7, 28),
);
final Patient ishitaVerma = fixturePatient(
  'p_ishita', 'Ishita', 'Verma',
  gender: 'Female', dob: DateTime(2007, 4, 25), phone: '7045188290',
  diagnosis: const ['Impacted wisdom tooth 38'],
  createdAt: _d(9, 10, 9, 30),
);
final Patient nehaDas = fixturePatient(
  'p_neha', 'Neha', 'Das',
  gender: 'Female', dob: DateTime(1999, 7, 19), phone: '8879320461',
  diagnosis: const ['Crowding, upper and lower'], balance: 12500,
  createdAt: DateTime(2026, 2, 16),
);
final Patient prakashRao = fixturePatient(
  'p_prakash', 'Prakash', 'Rao',
  gender: 'Male', dob: DateTime(1963, 2, 27), phone: '9422058107',
  diagnosis: const ['Complete dentures'],
  createdAt: DateTime(2025, 6, 12),
);
final Patient kiranMehta = fixturePatient(
  'p_kiran', 'Kiran', 'Mehta',
  gender: 'Male', dob: DateTime(1980, 5, 5), phone: '9819036457',
  diagnosis: const ['Crown, tooth 26'], balance: 5500,
  createdAt: DateTime(2026, 8, 12),
);
final Patient farzanaQureshi = fixturePatient(
  'p_farzana', 'Farzana', 'Qureshi',
  gender: 'Female', dob: DateTime(1988, 3, 30), phone: '9987042219',
  diagnosis: const ['Root canal, tooth 36'], balance: 4000,
  createdAt: _d(9, 11, 18, 0),
);
final Patient rajeshKulkarni = fixturePatient(
  'p_rajesh', 'Rajesh', 'Kulkarni',
  gender: 'Male', dob: DateTime(1968, 1, 21), phone: '9822410986',
  diagnosis: const ['Missing tooth 15'], balance: 3800,
  createdAt: DateTime(2026, 7, 1),
);
final Patient anjaliMenon = fixturePatient(
  'p_anjali', 'Anjali', 'Menon',
  gender: 'Female', dob: DateTime(1995, 4, 12), phone: '9082955173',
  diagnosis: const ['Gingivitis'], balance: 1200,
  createdAt: DateTime(2026, 8, 24),
);

/// 12 patients (not first-week). Stored order is deliberately not the
/// display order, so sorting is exercised.
final List<Patient> fixturePatients = [
  prakashRao,
  meeraJoshi,
  rajeshKulkarni,
  sohamBoridkar,
  vivekPatil,
  aaravNair,
  kiranMehta,
  rukhsanaShaikh,
  ishitaVerma,
  anjaliMenon,
  nehaDas,
  farzanaQureshi,
];

// ---------------------------------------------------------------------------
// Visits
// ---------------------------------------------------------------------------

Visit fixtureVisit(
  String id,
  String patientId,
  DateTime start, {
  VisitStatus status = VisitStatus.completed,
  String? treatment,
  String? notes,
  bool isDeleted = false,
}) =>
    Visit(
      id: id,
      patientId: patientId,
      scheduledStart: start,
      durationMinutes: 30,
      address: '',
      status: status,
      treatmentType: treatment,
      therapistNotes: notes,
      isDeleted: isDeleted,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

const _booked = VisitStatus.scheduled;

const String sohamTodayNote =
    'Exposed 13 under local anaesthesia and bonded a gold chain. Mild '
    'bleeding, controlled. Soft diet for 3 days, chlorhexidine rinse twice '
    'daily. Check healing before bonding brackets.';
const String sohamConsultNote =
    'OPG shows 13 impacted palatally, 53 retained. Explained exposure and '
    'traction with fixed braces, about 12 months. Patient agreed to the '
    'package.';
const String meeraNote = 'Zirconia crown cemented on 46. Occlusion checked, '
    'no high points. Review in 6 months.';
const String vivekNote = 'CBCT reviewed, bone height adequate for both '
    'sites. Placement planned for 16 Oct. HbA1c advised before surgery.';

/// Soham Boridkar: consultation Mon 7 Sep, a pre-surgery check on Tue
/// 15 Sep that was never recorded, surgical exposure today 10:25 and
/// bracket bonding booked for Wed 30 Sep 10:00.
final List<Visit> sohamVisits = [
  fixtureVisit('v_soham_0907', 'p_soham', _d(9, 7, 19, 15),
      treatment: 'Consultation and OPG', notes: sohamConsultNote),
  fixtureVisit('v_soham_0915', 'p_soham', _d(9, 15, 11, 0),
      status: _booked, treatment: 'Pre-surgery check'),
  fixtureVisit('v_soham_0923', 'p_soham', _d(9, 23, 10, 25),
      treatment: 'Surgical exposure', notes: sohamTodayNote),
  fixtureVisit('v_soham_0930', 'p_soham', _d(9, 30, 10, 0),
      status: _booked, treatment: 'Bracket bonding'),
];

final List<Visit> fixtureVisits = [
  ...sohamVisits,
  // Meera Joshi: seen today 9:40, nothing booked, no balance.
  fixtureVisit('v_meera_0826', 'p_meera', _d(8, 26, 9, 30),
      treatment: 'Crown preparation'),
  fixtureVisit('v_meera_0909', 'p_meera', _d(9, 9, 9, 40),
      treatment: 'Crown try-in'),
  fixtureVisit('v_meera_0923', 'p_meera', _d(9, 23, 9, 40),
      treatment: 'Crown fitted', notes: meeraNote),
  // Aarav Nair: Mon 21 Sep 5:30 PM, next Mon 5 Oct 5:30 PM.
  fixtureVisit('v_aarav_0921', 'p_aarav', _d(9, 21, 17, 30),
      treatment: 'Sealants'),
  fixtureVisit('v_aarav_1005', 'p_aarav', _d(10, 5, 17, 30),
      status: _booked, treatment: 'Sealants'),
  // Rukhsana Shaikh: Sat 19 Sep 11:10 AM; booked Tue 22 Sep, never
  // recorded, nothing booked since: overdue since Tue 22 Sep.
  fixtureVisit('v_rukhsana_0919', 'p_rukhsana', _d(9, 19, 11, 10),
      treatment: 'Scaling'),
  fixtureVisit('v_rukhsana_0922', 'p_rukhsana', _d(9, 22, 11, 0),
      status: _booked, treatment: 'Scaling'),
  // Vivek Patil: Fri 18 Sep 6:40 PM, next Fri 16 Oct 6:00 PM.
  fixtureVisit('v_vivek_0918', 'p_vivek', _d(9, 18, 18, 40),
      treatment: 'Implants', notes: vivekNote),
  fixtureVisit('v_vivek_1016', 'p_vivek', _d(10, 16, 18, 0),
      status: _booked, treatment: 'Implant placement'),
  // Ishita Verma: Thu 17 Sep 10:00 AM, nothing booked.
  fixtureVisit('v_ishita_0917', 'p_ishita', _d(9, 17, 10, 0),
      treatment: 'Extraction'),
  // Neha Das: monthly braces reviews, last Wed 16 Sep 4:15 PM, next Fri
  // 16 Oct 4:00 PM.
  fixtureVisit('v_neha_0716', 'p_neha', _d(7, 16, 16, 15),
      treatment: 'Braces'),
  fixtureVisit('v_neha_0813', 'p_neha', _d(8, 13, 16, 15),
      treatment: 'Braces'),
  fixtureVisit('v_neha_0916', 'p_neha', _d(9, 16, 16, 15),
      treatment: 'Braces'),
  fixtureVisit('v_neha_1016', 'p_neha', _d(10, 16, 16, 0),
      status: _booked, treatment: 'Braces'),
  // Prakash Rao: Wed 16 Sep 12:20 PM; a cancelled booking ahead must not
  // count as the next visit.
  fixtureVisit('v_prakash_0916', 'p_prakash', _d(9, 16, 12, 20),
      treatment: 'Denture review'),
  fixtureVisit('v_prakash_0929', 'p_prakash', _d(9, 29, 12, 0),
      status: VisitStatus.cancelled, treatment: 'Denture review'),
  // Balance-due patients seen earlier.
  fixtureVisit('v_kiran_0909', 'p_kiran', _d(9, 9, 12, 0),
      treatment: 'Crown fitted'),
  fixtureVisit('v_farzana_0911', 'p_farzana', _d(9, 11, 18, 15),
      treatment: 'Root canal'),
  fixtureVisit('v_farzana_0925', 'p_farzana', _d(9, 25, 18, 0),
      status: _booked, treatment: 'Root canal'),
  fixtureVisit('v_rajesh_0901', 'p_rajesh', _d(9, 1, 11, 30),
      treatment: 'Bridge, 14 to 16'),
  fixtureVisit('v_anjali_0914', 'p_anjali', _d(9, 14, 18, 10),
      treatment: 'Scaling'),
  fixtureVisit('v_anjali_0928', 'p_anjali', _d(9, 28, 18, 0),
      status: _booked, treatment: 'Scaling'),
];

// ---------------------------------------------------------------------------
// First week: one patient, seen today, nothing due.
// ---------------------------------------------------------------------------

final Patient firstWeekSoham = fixturePatient(
  'p_soham', 'Soham', 'Boridkar',
  gender: 'Male', dob: DateTime(1996, 3, 14), phone: '9321559182',
  diagnosis: const ['Ectopic upper canine'],
  // Before this month, so the header reads "1 patient" as in the mock-up.
  createdAt: DateTime(2026, 8, 28),
);

final List<Patient> firstWeekPatients = [firstWeekSoham];

final List<Visit> firstWeekVisits = [
  fixtureVisit('v_soham_0923', 'p_soham', _d(9, 23, 10, 25)),
];

// ---------------------------------------------------------------------------
// Dentist extras (Patient details for Soham Boridkar)
// ---------------------------------------------------------------------------

TreatmentPlanLineItemModel _planItem(
  String id,
  String name,
  int sequence,
  double price,
  String status, {
  List<String> teeth = const ['13'],
}) =>
    TreatmentPlanLineItemModel(
      id: id,
      doctorId: '',
      patientId: 'p_soham',
      treatmentPlanId: 'tp_soham',
      procedureName: name,
      toothNumbers: teeth,
      estimatedPrice: price,
      sequence: sequence,
      status: status,
      createdAt: _d(9, 7, 19, 30),
      updatedAt: _d(9, 23, 10, 50),
    );

/// "Canine exposure and alignment": 2 of 4 done (₹18,000 in all).
final List<TreatmentPlanLineItemModel> sohamPlan = [
  _planItem('tp_1', 'Consultation and OPG X-ray', 1, 1500, 'invoiced',
      teeth: const []),
  _planItem('tp_2', 'Surgical exposure and chain bonding', 2, 6500,
      'invoiced'),
  _planItem('tp_3', 'Bracket bonding and traction', 3, 7000, 'accepted'),
  _planItem('tp_4', 'Alignment review', 4, 3000, 'proposed'),
];

/// Today's surgical exposure note was dictated with Scribe and confirmed.
final Map<String, List<ConsultationNote>> fixtureScribeNotes = {
  'v_soham_0923': [
    ConsultationNote(
      id: 'cn_soham_0923',
      doctorId: '',
      patientId: 'p_soham',
      visitId: 'v_soham_0923',
      status: ConsultationNoteStatus.confirmed,
      createdAt: _d(9, 23, 10, 45),
      confirmedAt: _d(9, 23, 10, 52),
    ),
  ],
};

// ---------------------------------------------------------------------------
// Shell
// ---------------------------------------------------------------------------

const DoctorIdentity fixtureIdentity = DoctorIdentity(
  fullName: 'Dr. Ananya Deshpande',
  clinicName: 'Sanjeevani Clinic',
  specialty: 'Dentist',
);

const DoctorSubscriptionInfo fixturePlan = DoctorSubscriptionInfo(
  planName: 'Starter',
  doctorStatus: 'trial',
  isExpired: false,
  daysRemaining: 12,
  enabledModules: [],
);

DoctorSpecialty specialtyOf(DoctorSpecialtyType type) =>
    DoctorSpecialty.all.firstWhere((s) => s.type == type);

/// Every provider the Patients list, the preview pane, Patient details
/// and the sidebar read, replaced with fakes so no SQLite, Firebase or
/// platform channel is touched. Extend here (one place) when a screen
/// starts watching another provider.
List<Override> patientsOverrides({
  required List<Patient> patients,
  required List<Visit> visits,
  DateTime? now,
  DoctorSpecialtyType specialty = DoctorSpecialtyType.dentist,
  Map<String, List<TreatmentPlanLineItemModel>>? treatmentPlans,
  Map<String, List<ConsultationNote>>? scribeNotes,
  int waiting = 2,
}) {
  final plans = treatmentPlans ?? {'p_soham': sohamPlan};
  final notes = scribeNotes ?? fixtureScribeNotes;
  return [
    // Data the Patients screens are built from.
    dashboardNowProvider.overrideWithValue(now ?? patientsNow),
    patientsStreamProvider.overrideWith((ref) => Stream.value(patients)),
    allVisitsProvider.overrideWith((ref) => Stream.value(visits)),
    visitsForPatientProvider.overrideWith(
      (ref, patientId) => Stream.value(
        [for (final v in visits) if (v.patientId == patientId) v],
      ),
    ),
    activeDoctorSpecialtyProvider.overrideWith(
      (ref) => Stream.value(specialtyOf(specialty)),
    ),
    // Specialty extras on Patient details.
    homeopathyCaseSheetProvider.overrideWith(
      (ref, patientId) => Stream.value(null),
    ),
    patientTreatmentPlanProvider.overrideWith(
      (ref, patientId) async =>
          plans[patientId] ?? const <TreatmentPlanLineItemModel>[],
    ),
    patientToothChartProvider.overrideWith(
      (ref, patientId) async => const <ToothChartEntryModel>[],
    ),
    notesForVisitProvider.overrideWith(
      (ref, visitId) =>
          Stream.value(notes[visitId] ?? const <ConsultationNote>[]),
    ),
    // Who is signed in (sidebar, "reviewed by Dr. Deshpande").
    authStateProvider.overrideWith((ref) => Stream.value(null)),
    doctorProfileProvider.overrideWith((ref) => Stream.value(null)),
    doctorIdentityProvider.overrideWithValue(fixtureIdentity),
    subscriptionInfoProvider.overrideWith((ref) => Stream.value(fixturePlan)),
    // Sidebar Queue badge ("• 2" in the mock-ups).
    waitingNowCountProvider.overrideWithValue(waiting),
  ];
}

/// The full 12-patient clinic.
List<Override> fixtureOverrides() =>
    patientsOverrides(patients: fixturePatients, visits: fixtureVisits);

/// A clinic in its first week: one patient.
List<Override> firstWeekOverrides() =>
    patientsOverrides(patients: firstWeekPatients, visits: firstWeekVisits);

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
