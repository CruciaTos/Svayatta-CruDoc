import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/services/firestore_sync_service.dart';

void main() {
  group('omitsClinicalFields', () {
    test('a clinical role always sends notes and conditions', () {
      expect(
        FirestoreSyncService.omitsClinicalFields({'lastSyncedAt': 1}, true),
        isFalse,
      );
      expect(FirestoreSyncService.omitsClinicalFields({}, true), isFalse);
    });

    test('the front desk never overwrites an existing patient\'s', () {
      expect(
        FirestoreSyncService.omitsClinicalFields({'lastSyncedAt': 1}, false),
        isTrue,
      );
    });

    test('the front desk still sends the condition of a new patient', () {
      expect(
        FirestoreSyncService.omitsClinicalFields({'lastSyncedAt': null}, false),
        isFalse,
      );
    });
  });
}
