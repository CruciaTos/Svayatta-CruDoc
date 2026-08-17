import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

void main() {
  group('WhatsAppTemplateService Phone Normalization & Validation', () {
    test('normalizes 10-digit Indian numbers with default country code 91', () {
      expect(WhatsAppTemplateService.normalizePhone('9876543210'), equals('919876543210'));
      expect(WhatsAppTemplateService.normalizePhone('98765 43210'), equals('919876543210'));
      expect(WhatsAppTemplateService.normalizePhone('98765-43210'), equals('919876543210'));
    });

    test('normalizes numbers with leading 0 or +91 prefix', () {
      expect(WhatsAppTemplateService.normalizePhone('09876543210'), equals('919876543210'));
      expect(WhatsAppTemplateService.normalizePhone('+91 9876543210'), equals('919876543210'));
      expect(WhatsAppTemplateService.normalizePhone('+91-98765-43210'), equals('919876543210'));
    });

    test('normalizes international numbers correctly', () {
      expect(WhatsAppTemplateService.normalizePhone('+1 (555) 234-5678'), equals('15552345678'));
      expect(WhatsAppTemplateService.normalizePhone('+44 7911 123456'), equals('447911123456'));
      expect(WhatsAppTemplateService.normalizePhone('+971 50 123 4567'), equals('971501234567'));
    });

    test('rejects empty, malformed, too short, or too long numbers', () {
      expect(WhatsAppTemplateService.normalizePhone(null), isNull);
      expect(WhatsAppTemplateService.normalizePhone(''), isNull);
      expect(WhatsAppTemplateService.normalizePhone('   '), isNull);
      expect(WhatsAppTemplateService.normalizePhone('12345'), isNull);
      expect(WhatsAppTemplateService.normalizePhone('abcdef'), isNull);
      expect(WhatsAppTemplateService.normalizePhone('+12345678901234567890'), isNull); // > 15 digits
    });

    test('isValidWhatsAppPhone accurately determines validity', () {
      expect(WhatsAppTemplateService.isValidWhatsAppPhone('9876543210'), isTrue);
      expect(WhatsAppTemplateService.isValidWhatsAppPhone('+91 98765 43210'), isTrue);
      expect(WhatsAppTemplateService.isValidWhatsAppPhone('+1 555 234 5678'), isTrue);
      expect(WhatsAppTemplateService.isValidWhatsAppPhone(''), isFalse);
      expect(WhatsAppTemplateService.isValidWhatsAppPhone('invalid'), isFalse);
    });

    test('formats display phone gracefully', () {
      expect(WhatsAppTemplateService.formatDisplayPhone('9876543210'), equals('+91 98765 43210'));
      expect(WhatsAppTemplateService.formatDisplayPhone('+15552345678'), equals('+15552345678'));
      expect(WhatsAppTemplateService.formatDisplayPhone('invalid'), equals('invalid'));
    });
  });

  group('WhatsAppTemplateService Message Generation & Privacy Preservation', () {
    final samplePatient = Patient(
      id: 'patient-101',
      doctorId: 'doctor-abc',
      firstName: 'Rahul',
      lastName: 'Sharma',
      phone: '+91 98765 43210',
      email: 'rahul@example.com',
      gender: 'Male',
      dateOfBirth: DateTime(1990, 5, 15),
      diagnosis: const ['Hypertension Stage 2', 'Acute Bronchitis'], // Sensitive medical data
      notes: 'Patient exhibits severe chest pain and requires prescription refills.', // Sensitive clinical note
      packageBalance: 0,
      isArchived: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final clinicVisit = Visit(
      id: 'visit-101',
      doctorId: 'doctor-abc',
      patientId: 'patient-101',
      scheduledStart: DateTime(2026, 8, 20, 10, 30),
      durationMinutes: 30,
      address: '',
      visitType: VisitType.clinic,
      status: VisitStatus.scheduled,
      treatmentType: 'Routine checkup',
      therapistNotes: 'Check blood pressure and ECG.', // Sensitive note
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final homeVisit = Visit(
      id: 'visit-102',
      doctorId: 'doctor-abc',
      patientId: 'patient-101',
      scheduledStart: DateTime(2026, 8, 21, 14, 00),
      durationMinutes: 45,
      address: 'Flat 402, Lotus Towers, Bangalore',
      visitType: VisitType.home,
      status: VisitStatus.scheduled,
      treatmentType: 'Physiotherapy',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('generates in-clinic appointment confirmation with correct operational details', () {
      final msg = WhatsAppTemplateService.buildConfirmationMessage(
        visit: clinicVisit,
        patient: samplePatient,
        doctorName: 'Dr. Sarah Jenkins',
        clinicName: 'Moody Clinic',
      );

      expect(msg, contains('Appointment Confirmation'));
      expect(msg, contains('Rahul Sharma'));
      expect(msg, contains('Dr. Sarah Jenkins'));
      expect(msg, contains('Moody Clinic'));
      expect(msg, contains('In-Clinic Consultation'));
      expect(msg, contains('10:30 AM'));

      // STRICT PRIVACY VERIFICATION: Ensure NO clinical notes or diagnoses leak
      expect(msg, isNot(contains('Hypertension')));
      expect(msg, isNot(contains('Bronchitis')));
      expect(msg, isNot(contains('chest pain')));
      expect(msg, isNot(contains('prescription')));
      expect(msg, isNot(contains('ECG')));
    });

    test('generates home visit confirmation with location address and zero medical notes', () {
      final msg = WhatsAppTemplateService.buildConfirmationMessage(
        visit: homeVisit,
        patient: samplePatient,
        doctorName: 'Dr. Sarah Jenkins',
        clinicName: 'Moody Clinic',
      );

      expect(msg, contains('Home Visit Consultation'));
      expect(msg, contains('Flat 402, Lotus Towers, Bangalore'));
      expect(msg, contains('2:00 PM'));

      // PRIVACY VERIFICATION
      expect(msg, isNot(contains('Hypertension')));
      expect(msg, isNot(contains('chest pain')));
    });

    test('builds wa.me direct URL with proper URI encoding', () {
      final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(
        rawPhone: '+91 98765 43210',
        message: 'Hello Rahul, your appointment is confirmed.',
      );

      expect(uri, isNotNull);
      expect(uri!.scheme, equals('https'));
      expect(uri.host, equals('wa.me'));
      expect(uri.path, equals('/919876543210'));
      expect(uri.queryParameters['text'], equals('Hello Rahul, your appointment is confirmed.'));
    });
  });
}
