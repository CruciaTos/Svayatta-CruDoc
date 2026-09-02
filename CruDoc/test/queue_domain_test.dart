import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/core/errors/queue_exceptions.dart';

void main() {
  group('QueueEntry Model & Date Helpers', () {
    test('queueDateKeyFor formats local calendar date correctly', () {
      final date = DateTime(2026, 9, 2, 14, 30);
      expect(queueDateKeyFor(date), '2026-09-02');
    });

    test('QueueStatus and QueuePriority fromValue parse correctly with fallbacks', () {
      expect(QueueStatus.fromValue('waiting'), QueueStatus.waiting);
      expect(QueueStatus.fromValue('called'), QueueStatus.called);
      expect(QueueStatus.fromValue('inConsultation'), QueueStatus.inConsultation);
      expect(QueueStatus.fromValue('completed'), QueueStatus.completed);
      expect(QueueStatus.fromValue('skipped'), QueueStatus.skipped);
      expect(QueueStatus.fromValue('cancelled'), QueueStatus.cancelled);
      expect(QueueStatus.fromValue('unknown_status'), QueueStatus.waiting);

      expect(QueuePriority.fromValue('normal'), QueuePriority.normal);
      expect(QueuePriority.fromValue('urgent'), QueuePriority.urgent);
      expect(QueuePriority.fromValue('unknown'), QueuePriority.normal);
    });

    test('QueueEntry isActiveServing returns true only for called and inConsultation', () {
      final now = DateTime.now();
      final base = QueueEntry(
        id: 'q-1',
        tokenNumber: 1,
        queueDate: '2026-09-02',
        status: QueueStatus.waiting,
        checkedInAt: now,
        createdAt: now,
        updatedAt: now,
      );

      expect(base.isActiveServing, isFalse);
      expect(base.copyWith(status: QueueStatus.called).isActiveServing, isTrue);
      expect(base.copyWith(status: QueueStatus.inConsultation).isActiveServing, isTrue);
      expect(base.copyWith(status: QueueStatus.completed).isActiveServing, isFalse);
      expect(base.copyWith(status: QueueStatus.skipped).isActiveServing, isFalse);
    });

    test('QueueEntry map conversion and copyWith preserve all properties', () {
      final now = DateTime.now();
      final entry = QueueEntry(
        id: 'token-123',
        doctorId: 'doc-abc',
        patientId: 'patient-456',
        walkInName: null,
        walkInPhone: null,
        tokenNumber: 5,
        queueDate: '2026-09-02',
        status: QueueStatus.called,
        priority: QueuePriority.urgent,
        reason: 'Severe headache',
        checkedInAt: now,
        calledAt: now,
        createdAt: now,
        updatedAt: now,
      );

      final map = entry.toMap();
      expect(map['doctorId'], 'doc-abc');
      expect(map['tokenNumber'], 5);
      expect(map['status'], 'called');
      expect(map['priority'], 'urgent');
      expect(map['reason'], 'Severe headache');

      final copied = entry.copyWith(status: QueueStatus.inConsultation);
      expect(copied.status, QueueStatus.inConsultation);
      expect(copied.tokenNumber, 5);
      expect(copied.id, 'token-123');
    });

    test('QueueExceptions instantiate with descriptive messages', () {
      const valEx = QueueValidationException('Missing name');
      expect(valEx.message, 'Missing name');

      final archivedEx = QueuePatientArchivedException('pat-1');
      expect(archivedEx.message, contains('archived'));

      const emptyEx = QueueEmptyException();
      expect(emptyEx.message, contains('no one waiting'));
    });
  });
}
