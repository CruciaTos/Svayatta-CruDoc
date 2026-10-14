import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/features/appointments/data/services/visits_local_service.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/repo/queue_repository.dart';
import 'package:doctor_management_app/features/queue/data/services/queue_local_service.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/presentation/consultation_scribe_launcher.dart';

class _FakeQueueLocal implements QueueLocalService {
  _FakeQueueLocal(this.entry);

  QueueEntry entry;

  @override
  Future<QueueEntry?> getEntry(String entryId) async =>
      entryId == entry.id ? entry : null;

  @override
  Future<void> updateEntry(
    String entryId,
    Map<String, dynamic> data, {
    int? lastSyncedAt,
    bool? pendingDelete,
    String syncStatus = 'pending',
  }) async {
    entry = entry.copyWith(
      status: QueueStatus.fromValue(data['status'] as String?),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSync implements FirestoreSyncService {
  @override
  Future<void> triggerPostWriteSync() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePatients implements PatientRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVisits implements VisitLocalService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

QueueEntry _token(QueueStatus status) {
  final now = DateTime(2026, 10, 11, 10);
  return QueueEntry(
    id: 'q1',
    doctorId: 'clinic-1',
    patientId: 'p1',
    tokenNumber: 4,
    queueDate: '2026-10-11',
    status: status,
    checkedInAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

QueueRepository _repo(QueueEntry entry) => QueueRepository(
  localService: _FakeQueueLocal(entry),
  syncService: _FakeSync(),
  patientRepository: _FakePatients(),
  visitLocalService: _FakeVisits(),
);

void main() {
  group('autoScribeSpecialtyFor', () {
    test('records homeopathy and physiotherapy consultations', () {
      expect(
        autoScribeSpecialtyFor(DoctorSpecialtyType.homeopathy),
        SessionSpecialty.homeopathy,
      );
      expect(
        autoScribeSpecialtyFor(DoctorSpecialtyType.physiotherapy),
        SessionSpecialty.physiotherapy,
      );
    });

    test('leaves every other specialty alone', () {
      for (final type in DoctorSpecialtyType.values) {
        if (type == DoctorSpecialtyType.homeopathy ||
            type == DoctorSpecialtyType.physiotherapy) {
          continue;
        }
        expect(autoScribeSpecialtyFor(type), isNull, reason: type.name);
      }
    });
  });

  test('a walk-in keeps its draft under an id tied to its token', () {
    expect(walkInVisitIdFor('q1'), 'queue_q1');
    expect(walkInVisitIdFor('q1'), walkInVisitIdFor('q1'));
  });

  group('QueueRepository.consultationStarts', () {
    test('announces a consultation started on this device', () async {
      final heard = <QueueEntry>[];
      final sub = QueueRepository.consultationStarts.listen(heard.add);
      addTearDown(sub.cancel);

      await _repo(_token(QueueStatus.called)).startConsultation('q1');
      await Future<void>.delayed(Duration.zero);

      expect(heard, hasLength(1));
      expect(heard.single.id, 'q1');
      expect(heard.single.patientId, 'p1');
      expect(heard.single.tokenNumber, 4);
      expect(heard.single.status, QueueStatus.inConsultation);
      expect(heard.single.consultationStartedAt, isNotNull);
    });

    test('stays quiet when asked not to (demo data)', () async {
      final heard = <QueueEntry>[];
      final sub = QueueRepository.consultationStarts.listen(heard.add);
      addTearDown(sub.cancel);

      await _repo(
        _token(QueueStatus.called),
      ).startConsultation('q1', announce: false);
      await Future<void>.delayed(Duration.zero);

      expect(heard, isEmpty);
    });

    test('announces nothing when the token cannot start', () async {
      final heard = <QueueEntry>[];
      final sub = QueueRepository.consultationStarts.listen(heard.add);
      addTearDown(sub.cancel);

      await expectLater(
        _repo(_token(QueueStatus.waiting)).startConsultation('q1'),
        throwsA(isA<QueueInvalidTransitionException>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(heard, isEmpty);
    });
  });
}
