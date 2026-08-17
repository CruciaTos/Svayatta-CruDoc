import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_notification_log.dart';
import 'package:doctor_management_app/features/messaging/data/repo/whatsapp_repository.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_log_local_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';

class MockPatientRepository extends Mock implements PatientRepository {}
class MockWhatsAppLogLocalService extends Mock implements WhatsAppLogLocalService {}
class MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(WhatsAppNotificationLog(
      id: '',
      doctorId: '',
      patientId: '',
      visitId: '',
      recipientPhone: '',
      recipientName: '',
      status: WhatsAppNotificationStatus.pending,
      attemptedAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    registerFallbackValue(WhatsAppNotificationStatus.pending);
  });

  late MockPatientRepository mockPatientRepo;
  late MockWhatsAppLogLocalService mockLocalLogService;
  late MockHttpClient mockHttpClient;
  late WhatsAppRepository repository;

  final samplePatient = Patient(
    id: 'patient-123',
    doctorId: 'doctor-abc',
    firstName: 'Amit',
    lastName: 'Verma',
    phone: '+91 98765 43210',
    email: 'amit@example.com',
    gender: 'Male',
    dateOfBirth: DateTime(1985, 3, 20),
    diagnosis: const ['Hypertension'],
    packageBalance: 0,
    isArchived: false,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final sampleVisit = Visit(
    id: 'visit-999',
    doctorId: 'doctor-abc',
    patientId: 'patient-123',
    scheduledStart: DateTime(2026, 8, 20, 11, 0),
    durationMinutes: 30,
    address: 'Clinic A',
    visitType: VisitType.clinic,
    status: VisitStatus.scheduled,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  setUp(() {
    mockPatientRepo = MockPatientRepository();
    mockLocalLogService = MockWhatsAppLogLocalService();
    mockHttpClient = MockHttpClient();

    repository = WhatsAppRepository(
      patientRepository: mockPatientRepo,
      logLocalService: mockLocalLogService,
      httpClient: mockHttpClient,
      currentDoctorId: 'doctor-abc',
    );

    when(() => mockPatientRepo.getPatient('patient-123')).thenAnswer((_) async => samplePatient);
    when(() => mockLocalLogService.insertLog(any())).thenAnswer((_) async {});
    when(() => mockLocalLogService.updateLogStatus(
          any(),
          any(),
          whatsappMessageId: any(named: 'whatsappMessageId'),
          failureReason: any(named: 'failureReason'),
          sentAt: any(named: 'sentAt'),
        )).thenAnswer((_) async {});
    when(() => mockLocalLogService.getLogByVisitId(any(), any())).thenAnswer((_) async => null);
  });

  group('WhatsAppRepository Tests', () {
    test('skips notification and records skipped log when patient has no valid phone', () async {
      final noPhonePatient = samplePatient.copyWith(phone: '');
      when(() => mockPatientRepo.getPatient('patient-no-phone')).thenAnswer((_) async => noPhonePatient);

      final visitNoPhone = Visit(
        id: 'visit-no-phone',
        doctorId: 'doctor-abc',
        patientId: 'patient-no-phone',
        scheduledStart: DateTime(2026, 8, 20, 11, 0),
        durationMinutes: 30,
        address: 'Clinic A',
        visitType: VisitType.clinic,
        status: VisitStatus.scheduled,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final result = await repository.sendAppointmentConfirmation(
        visit: visitNoPhone,
        patientOverride: noPhonePatient,
      );

      expect(result, isFalse);
      verify(() => mockLocalLogService.insertLog(any(that: predicate<WhatsAppNotificationLog>(
            (log) => log.status == WhatsAppNotificationStatus.skipped,
          )))).called(1);
    });

    test('idempotency: skips duplicate send if log is already completed', () async {
      final completedLog = WhatsAppNotificationLog(
        id: 'visit-999',
        doctorId: 'doctor-abc',
        patientId: 'patient-123',
        visitId: 'visit-999',
        recipientPhone: '919876543210',
        recipientName: 'Amit Verma',
        status: WhatsAppNotificationStatus.sent,
        whatsappMessageId: 'wamid.123',
        attemptedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => mockLocalLogService.getLogByVisitId('visit-999', any()))
          .thenAnswer((_) async => completedLog);

      final result = await repository.sendAppointmentConfirmation(
        visit: sampleVisit,
        patientOverride: samplePatient,
      );

      // Returns true (idempotent success) without dispatching new API call
      expect(result, isTrue);
      verifyNever(() => mockHttpClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')));
    });

    test('dispatches notification and updates status to sent on 200 OK', () async {
      when(() => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode({'success': true, 'messageId': 'wamid.HBgL98765'}),
            200,
          ));

      final result = await repository.sendAppointmentConfirmation(
        visit: sampleVisit,
        patientOverride: samplePatient,
      );

      expect(result, isTrue);
      verify(() => mockLocalLogService.insertLog(any())).called(1);
      verify(() => mockLocalLogService.updateLogStatus(
            any(),
            WhatsAppNotificationStatus.sent,
            whatsappMessageId: any(named: 'whatsappMessageId'),
            sentAt: any(named: 'sentAt'),
          )).called(1);
    });
  });
}
