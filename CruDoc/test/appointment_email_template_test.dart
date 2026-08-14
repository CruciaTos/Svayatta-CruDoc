import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/messaging/data/services/appointment_email_template.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

void main() {
  group('AppointmentEmailTemplate', () {
    late Patient testPatient;

    setUp(() {
      testPatient = Patient(
        id: 'patient_1',
        firstName: 'Aarav',
        lastName: 'Sharma',
        phone: '+919876543210',
        email: 'aarav.sharma@example.com',
        gender: 'Male',
        dateOfBirth: DateTime(1990, 5, 15),
        diagnosis: const ['Fever'],
        packageBalance: 0,
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
    });

    test('generates professional confirmation for In-Clinic consultation', () {
      final scheduledDate = DateTime(2026, 8, 20, 14, 30);
      final visit = Visit(
        id: 'visit_clinic_1',
        patientId: 'patient_1',
        scheduledStart: scheduledDate,
        durationMinutes: 30,
        address: '102 Health Avenue, Bandra West, Mumbai',
        visitType: VisitType.clinic,
        status: VisitStatus.scheduled,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final email = AppointmentEmailTemplate.buildConfirmation(
        visit: visit,
        patient: testPatient,
        doctorName: 'Dr. Vinit Parab',
        specialty: 'Cardiologist',
        clinicName: 'CruDoc Advanced Clinic',
      );

      expect(email.subject, contains('Appointment Confirmation: Dr. Vinit Parab'));
      expect(email.subject, contains('20 August 2026'));
      expect(email.body, contains('Dear Aarav Sharma'));
      expect(email.body, contains('Dr. Vinit Parab (Cardiologist)'));
      expect(email.body, contains('2:30 PM - 3:00 PM (30 mins)'));
      expect(email.body, contains('In-Clinic Consultation'));
      expect(email.body, contains('102 Health Avenue, Bandra West, Mumbai'));
    });

    test('generates confirmation for Home Visit consultation', () {
      final scheduledDate = DateTime(2026, 8, 22, 10, 0);
      final visit = Visit(
        id: 'visit_home_1',
        patientId: 'patient_1',
        scheduledStart: scheduledDate,
        durationMinutes: 45,
        address: 'Flat 402, Sunshine Heights, Andheri',
        visitType: VisitType.home,
        status: VisitStatus.scheduled,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final email = AppointmentEmailTemplate.buildConfirmation(
        visit: visit,
        patient: testPatient,
        doctorName: 'Dr. Vinit Parab',
        specialty: 'General Physician',
      );

      expect(email.body, contains('Home Visit Consultation'));
      expect(email.body, contains('Flat 402, Sunshine Heights, Andheri'));
      expect(email.body, contains('10:00 AM - 10:45 AM (45 mins)'));
    });
  });
}
