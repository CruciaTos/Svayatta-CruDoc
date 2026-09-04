import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_details.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/presentation/dental_patient_details_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';

void main() {
  final now = DateTime.now();
  final testPatient = Patient(
    id: 'pat-gate-1',
    doctorId: 'doc-gate-1',
    firstName: 'Arun',
    lastName: 'Kulkarni',
    phone: '9876543210',
    email: 'arun@example.com',
    gender: 'Male',
    dateOfBirth: DateTime(1988, 5, 12),
    diagnosis: const ['Dental checkup'],
    notes: 'Regular checkup',
    packageBalance: 0.0,
    isArchived: false,
    createdAt: now,
    updatedAt: now,
  );

  group('Dental Patient Details Specialty Gating Tests', () {
    testWidgets('Dentist specialty routes to DentalPatientDetailsScreen with Odontogram', (tester) async {
      final dentistSpecialty = DoctorSpecialty.all.firstWhere(
        (s) => s.type == DoctorSpecialtyType.dentist,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeDoctorSpecialtyProvider.overrideWith((ref) => Stream.value(dentistSpecialty)),
            patientsStreamProvider.overrideWith((ref) => Stream.value([testPatient])),
            visitsForPatientProvider(testPatient.id).overrideWith((ref) => Stream.value(<Visit>[])),
            patientToothChartProvider(testPatient.id).overrideWith((ref) => Future.value(<ToothChartEntryModel>[])),
          ],
          child: MaterialApp(
            home: PatientDetailsPage(patient: testPatient),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should render DentalPatientDetailsScreen
      expect(find.byType(DentalPatientDetailsScreen), findsOneWidget);
      expect(find.text('DENTAL CLINIC'), findsOneWidget);
      expect(find.text('Tooth Chart (Odontogram)'), findsOneWidget);
    });

    testWidgets('General Physician specialty does NOT show dental Odontogram', (tester) async {
      final gpSpecialty = DoctorSpecialty.all.firstWhere(
        (s) => s.type == DoctorSpecialtyType.generalPhysician,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeDoctorSpecialtyProvider.overrideWith((ref) => Stream.value(gpSpecialty)),
            patientsStreamProvider.overrideWith((ref) => Stream.value([testPatient])),
            visitsForPatientProvider(testPatient.id).overrideWith((ref) => Stream.value(<Visit>[])),
          ],
          child: MaterialApp(
            home: PatientDetailsPage(patient: testPatient),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should NOT render Dental screen or Odontogram
      expect(find.byType(DentalPatientDetailsScreen), findsNothing);
      expect(find.text('DENTAL CLINIC'), findsNothing);
      expect(find.text('Tooth Chart (Odontogram)'), findsNothing);
    });
  });
}
