// Firestore marks these classes sealed; mocking them is the only way to test
// the repository without a live database.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:doctor_management_app/features/messaging/data/models/whatsapp_notification_log.dart';
import 'package:doctor_management_app/features/messaging/data/repo/whatsapp_repository.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_log_local_service.dart';

class MockWhatsAppLogLocalService extends Mock implements WhatsAppLogLocalService {}
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}
class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}
class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

void main() {
  final now = DateTime(2026, 8, 19, 18, 0);

  WhatsAppNotificationLog logFor(String visitId, WhatsAppNotificationStatus status) {
    return WhatsAppNotificationLog(
      id: visitId,
      doctorId: 'doctor-abc',
      patientId: 'patient-123',
      visitId: visitId,
      recipientPhone: '919876543210',
      recipientName: 'Amit Verma',
      status: status,
      attemptedAt: now,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUpAll(() {
    registerFallbackValue(logFor('', WhatsAppNotificationStatus.pending));
  });

  late MockWhatsAppLogLocalService mockLocalLogService;
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference mockCollection;
  late MockDocumentReference mockDoc;
  late MockDocumentSnapshot mockSnapshot;
  late WhatsAppRepository repository;

  setUp(() {
    mockLocalLogService = MockWhatsAppLogLocalService();
    mockFirestore = MockFirebaseFirestore();
    mockCollection = MockCollectionReference();
    mockDoc = MockDocumentReference();
    mockSnapshot = MockDocumentSnapshot();

    repository = WhatsAppRepository(
      logLocalService: mockLocalLogService,
      firestore: mockFirestore,
      currentDoctorId: 'doctor-abc',
    );

    when(() => mockFirestore.collection('whatsapp_notification_logs'))
        .thenReturn(mockCollection);
    when(() => mockCollection.doc(any())).thenReturn(mockDoc);
    when(() => mockDoc.get()).thenAnswer((_) async => mockSnapshot);
    when(() => mockLocalLogService.getLogByVisitId(any(), any()))
        .thenAnswer((_) async => null);
    when(() => mockLocalLogService.insertLog(any())).thenAnswer((_) async {});
  });

  group('WhatsAppRepository.getLogForVisit', () {
    test('returns null for an empty visit id without reading anything', () async {
      final result = await repository.getLogForVisit('');

      expect(result, isNull);
      verifyNever(() => mockLocalLogService.getLogByVisitId(any(), any()));
      verifyNever(() => mockFirestore.collection(any()));
    });

    test('returns the local copy without going to Firestore', () async {
      final local = logFor('visit-999', WhatsAppNotificationStatus.delivered);
      when(() => mockLocalLogService.getLogByVisitId('visit-999', 'doctor-abc'))
          .thenAnswer((_) async => local);

      final result = await repository.getLogForVisit('visit-999');

      expect(result, same(local));
      verifyNever(() => mockFirestore.collection(any()));
    });

    test('falls back to Firestore and caches what it finds', () async {
      when(() => mockSnapshot.exists).thenReturn(true);
      when(() => mockSnapshot.id).thenReturn('visit-999');
      when(() => mockSnapshot.data()).thenReturn({
        'doctorId': 'doctor-abc',
        'patientId': 'patient-123',
        'appointmentId': 'visit-999',
        'recipientPhone': '919876543210',
        'recipientName': 'Amit Verma',
        'status': WhatsAppNotificationStatus.sent.value,
        'whatsappMessageId': 'wamid.HBgL98765',
        'attemptedAt': now.millisecondsSinceEpoch,
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      });

      final result = await repository.getLogForVisit('visit-999');

      expect(result, isNotNull);
      expect(result!.visitId, 'visit-999');
      expect(result.status, WhatsAppNotificationStatus.sent);
      expect(result.whatsappMessageId, 'wamid.HBgL98765');
      verify(() => mockCollection.doc('visit-999')).called(1);
      verify(() => mockLocalLogService.insertLog(any(that: predicate<WhatsAppNotificationLog>(
            (log) => log.visitId == 'visit-999',
          )))).called(1);
    });

    test('returns null when no reminder was recorded', () async {
      when(() => mockSnapshot.exists).thenReturn(false);
      when(() => mockSnapshot.data()).thenReturn(null);

      final result = await repository.getLogForVisit('visit-999');

      expect(result, isNull);
      verifyNever(() => mockLocalLogService.insertLog(any()));
    });

    test('returns null instead of throwing when Firestore fails', () async {
      when(() => mockDoc.get()).thenThrow(Exception('offline'));

      final result = await repository.getLogForVisit('visit-999');

      expect(result, isNull);
    });
  });

  group('WhatsAppRepository.watchVisitWhatsAppStatus', () {
    test('emits null for an empty visit id', () async {
      expect(await repository.watchVisitWhatsAppStatus('').first, isNull);
      verifyNever(() => mockFirestore.collection(any()));
    });
  });
}
