import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/services/firestore_sync_service.dart';

/// The two decisions the sync makes for a doctor confined to their own
/// patients: what comes off the device after a fresh server answer, and when
/// a patient's assignment is sent up.
void main() {
  Map<String, Object?> row(
    String id, {
    String syncStatus = 'synced',
    Object? lastSyncedAt = 1,
    Object? assigned = '',
  }) => {
    'id': id,
    'syncStatus': syncStatus,
    'lastSyncedAt': lastSyncedAt,
    'assignedDoctorUids': assigned,
  };

  group('rowsToDropAfterScopedAnswer', () {
    test('drops a cached patient the server no longer returns', () {
      // The case from the bug: reassigned to another doctor, possibly while
      // this device was off, so no change event ever reported it.
      final drop = FirestoreSyncService.rowsToDropAfterScopedAnswer(
        localRows: [row('mine'), row('reassigned')],
        serverIds: {'mine'},
      );
      expect(drop, {'reassigned'});
    });

    test('keeps everything the server still returns', () {
      final drop = FirestoreSyncService.rowsToDropAfterScopedAnswer(
        localRows: [row('a'), row('b')],
        serverIds: {'a', 'b', 'c'},
      );
      expect(drop, isEmpty);
    });

    test("never drops this device's unsent work", () {
      // A patient registered offline, or an edit not yet uploaded: the server
      // cannot have it yet, and dropping it would lose it.
      final drop = FirestoreSyncService.rowsToDropAfterScopedAnswer(
        localRows: [
          row('new-offline', syncStatus: 'pending', lastSyncedAt: null),
          row('edited', syncStatus: 'pending'),
        ],
        serverIds: const {},
      );
      expect(drop, isEmpty);
    });

    test('an empty server answer drops every synced row', () {
      // A doctor unassigned from everyone holds nothing of the clinic's.
      final drop = FirestoreSyncService.rowsToDropAfterScopedAnswer(
        localRows: [row('a'), row('b'), row('c', syncStatus: 'pending')],
        serverIds: const {},
      );
      expect(drop, {'a', 'b'});
    });
  });

  group('firstUploadAssignment', () {
    test("sends a doctor's own new patient with themselves assigned", () {
      expect(
        FirestoreSyncService.firstUploadAssignment(
          row('p', lastSyncedAt: null, assigned: '["doc-1"]'),
          'doc-1',
        ),
        {
          'assignedDoctorUids': ['doc-1'],
        },
      );
    });

    test('sends nothing once the patient has reached the server', () {
      // From then on the assignment is the server's; resending even the same
      // value invites a stale overwrite that the rules would refuse.
      expect(
        FirestoreSyncService.firstUploadAssignment(
          row('p', lastSyncedAt: 1700000000000, assigned: '["doc-1"]'),
          'doc-1',
        ),
        isEmpty,
      );
    });

    test('sends nothing for an unassigned new patient', () {
      expect(
        FirestoreSyncService.firstUploadAssignment(
          row('p', lastSyncedAt: null, assigned: ''),
          'doc-1',
        ),
        isEmpty,
      );
    });

    test('never sends someone else, or several people', () {
      // The only non-empty value the rules accept from a client is the
      // caller alone; anything else would be refused and stick unsent.
      expect(
        FirestoreSyncService.firstUploadAssignment(
          row('p', lastSyncedAt: null, assigned: '["doc-2"]'),
          'doc-1',
        ),
        isEmpty,
      );
      expect(
        FirestoreSyncService.firstUploadAssignment(
          row('p', lastSyncedAt: null, assigned: '["doc-1","doc-2"]'),
          'doc-1',
        ),
        isEmpty,
      );
    });

    test('sends nothing when nobody is signed in', () {
      expect(
        FirestoreSyncService.firstUploadAssignment(
          row('p', lastSyncedAt: null, assigned: '["doc-1"]'),
          null,
        ),
        isEmpty,
      );
    });
  });
}
