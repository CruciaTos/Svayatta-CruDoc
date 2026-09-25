// Test-only sample data mirroring design/clinic-redesign/screens/revenue.png.
// Never imported by app code.

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';

import '../patients/patients_fixtures.dart'
    show fixturePatient, fixturePlan, specialtyOf;

/// Wednesday 23 September 2026, 11:48 AM, as in the mock-up.
final DateTime revenueNow = DateTime(2026, 9, 23, 11, 48);

const DoctorIdentity revenueIdentity = DoctorIdentity(
  fullName: 'Dr. Ananya Deshpande',
  clinicName: 'Sanjeevani Clinic',
  specialty: 'General Physician',
);

var _seq = 0;

RevenueEntry _entry(
  DateTime at,
  double amount,
  String description, {
  String? payer,
  TransactionKind kind = TransactionKind.income,
  RevenueType type = RevenueType.visit,
}) =>
    RevenueEntry(
      id: 'r${_seq++}',
      date: at,
      description: description,
      amount: amount,
      type: kind == TransactionKind.expense ? RevenueType.miscellaneous : type,
      kind: kind,
      payer: payer,
      createdAt: at,
      updatedAt: at,
    );

RevenueEntry _out(DateTime at, double amount, String description) =>
    _entry(at, amount, description, kind: TransactionKind.expense);

/// Daily collections for 1 to 22 September (Sundays 6, 13 and 20 have
/// none). With today's ₹3,400 they add up to ₹67,300.
const Map<int, double> septemberDaily = {
  1: 2900, 2: 3300, 3: 3100, 4: 2700, 5: 4000,
  7: 3600, 8: 3200, 9: 3500, 10: 2800, 11: 3000, 12: 4200,
  14: 3700, 15: 3300, 16: 3100, 17: 3100, 18: 2700, 19: 4100,
  21: 3800, 22: 3800,
};

List<RevenueEntry> buildRevenueEntries() {
  _seq = 0;
  DateTime sep(int d, [int h = 18, int m = 0]) => DateTime(2026, 9, d, h, m);
  return [
    // Today, newest first as in the mock-up.
    _entry(sep(23, 11, 24), 900, 'Consultation and HbA1c', payer: 'Sunita Joshi'),
    _entry(sep(23, 11, 2), 400, 'Consultation', payer: 'Arjun Patil'),
    _entry(sep(23, 10, 31), 900, 'Consultation and TSH test', payer: 'Fatima Shaikh'),
    _entry(sep(23, 10, 6), 700, 'Consultation and ECG', payer: 'Rahul Verma'),
    _entry(sep(23, 9, 48), 500, 'Consultation', payer: 'Priya Nair'),
    _out(sep(23, 9, 15), 200, 'Medical Supplies (Gloves, 1 box)'),
    // Earlier in September.
    for (final e in septemberDaily.entries)
      _entry(sep(e.key), e.value, 'Consultations'),
    _out(sep(1, 10), 18000, 'Clinic Rent'),
    _out(sep(1, 10, 30), 15000, 'Staff Salary'),
    _out(sep(2, 12), 3200, 'Medical Supplies'),
    _out(sep(10, 12), 200, 'Utilities & Electric'),
    _out(sep(15, 12), 2100, 'Medical Supplies'),
    // 1 to 23 August: ₹63,500, so September is up 6%.
    _entry(DateTime(2026, 8, 10, 18), 63500, 'Consultations'),
    // After 23 August: not part of the comparison.
    _entry(DateTime(2026, 8, 28, 18), 5000, 'Consultations'),
  ];
}

PendingPayment _pending(
  String id,
  String patientId,
  String payer,
  DateTime date,
  double amount,
  String description,
) =>
    PendingPayment(
      id: id,
      date: date,
      description: description,
      amount: amount,
      payer: payer,
      patientId: patientId,
      createdAt: date,
      updatedAt: date,
    );

final List<PendingPayment> revenuePending = [
  _pending('pp1', 'p_rohan', 'Rohan Mehta', DateTime(2026, 9, 6, 11), 500, 'Visit'),
  _pending('pp2', 'p_lakshmi', 'Lakshmi Reddy', DateTime(2026, 9, 14, 10), 700, 'Visit'),
  _pending('pp3', 'p_anil', 'Anil Gupta', DateTime(2026, 9, 16, 12), 1200, 'Lab tests'),
];

final List<Patient> revenuePatients = [
  fixturePatient('p_rohan', 'Rohan', 'Mehta',
      gender: 'Male', dob: DateTime(1984, 2, 11), phone: '+91 98200 11223'),
  fixturePatient('p_lakshmi', 'Lakshmi', 'Reddy',
      gender: 'Female', dob: DateTime(1970, 4, 2), phone: '+91 98450 33445'),
  fixturePatient('p_anil', 'Anil', 'Gupta',
      gender: 'Male', dob: DateTime(1962, 12, 19), phone: '+91 99300 55667'),
];

/// Every provider the Revenue screen and the sidebar read, replaced with
/// fakes so no SQLite, Firebase or clock is touched.
List<Override> revenueOverrides({
  List<RevenueEntry>? entries,
  List<PendingPayment>? pending,
  List<Patient>? patients,
  DateTime? now,
  RevenueViewState view = const RevenueViewState(),
}) {
  return [
    dashboardNowProvider.overrideWithValue(now ?? revenueNow),
    recentRevenueEntriesProvider.overrideWith(
      (ref) => Stream.value(entries ?? buildRevenueEntries()),
    ),
    pendingPaymentsProvider.overrideWith(
      (ref) => Stream.value(pending ?? revenuePending),
    ),
    patientsStreamProvider.overrideWith(
      (ref) => Stream.value(patients ?? revenuePatients),
    ),
    revenueViewControllerProvider.overrideWith(() => RevenueViewController(view)),
    activeDoctorSpecialtyProvider.overrideWith(
      (ref) => Stream.value(specialtyOf(DoctorSpecialtyType.dentist)),
    ),
    // Who is signed in (sidebar).
    authStateProvider.overrideWith((ref) => Stream.value(null)),
    doctorProfileProvider.overrideWith((ref) => Stream.value(null)),
    doctorIdentityProvider.overrideWithValue(revenueIdentity),
    subscriptionInfoProvider.overrideWith((ref) => Stream.value(fixturePlan)),
    // Sidebar Queue badge ("• 2" in the mock-up).
    waitingNowCountProvider.overrideWithValue(2),
  ];
}
