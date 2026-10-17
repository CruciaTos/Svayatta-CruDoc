import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';

/// Losing a permission has to take effect on the device, not just on the
/// server: rows already downloaded stay readable offline otherwise. These
/// cover the decision about what gets dropped; the deletion itself is glue.
void main() {
  ClinicAccess access(Set<ClinicPermission> perms, {String roleId = 'doctor'}) =>
      ClinicAccess(
        clinicId: 'clinic-1',
        uid: 'user-1',
        roleId: roleId,
        roleName: roleId,
        kind: MemberKind.doctor,
        perms: perms,
      );

  group('purgeTargetsFor', () {
    test('purges nothing while access is still resolving', () {
      final t = FirestoreSyncService.purgeTargetsFor(null);
      expect(t.tables, isEmpty);
      expect(t.watermarks, isEmpty,
          reason: 'wiping the cache on every sign-in would be worse than '
              'waiting for the real answer');
    });

    test('purges nothing for an owner, who may read everything', () {
      final t = FirestoreSyncService.purgeTargetsFor(ClinicAccess.owner('u1'));
      expect(t.tables, isEmpty);
    });

    test('drops clinical tables when a doctor is demoted to the front desk', () {
      // The case from the audit: a doctor becomes a receptionist and their
      // device still holds dental records and radiology documents.
      final receptionist = access({
        ClinicPermission.patientsView,
        ClinicPermission.patientsEdit,
        ClinicPermission.schedule,
        ClinicPermission.billing,
        ClinicPermission.messaging,
      });
      final t = FirestoreSyncService.purgeTargetsFor(receptionist);

      expect(t.tables, contains('dental_records'));
      expect(t.tables, contains('radiology_docs'));
      // Still theirs to hold.
      expect(t.tables, isNot(contains('patients')));
      expect(t.tables, isNot(contains('visits')));
      expect(t.tables, isNot(contains('pending_payments')));
    });

    test('drops both visit collections together when scheduling is lost', () {
      // appointments and visitations share the `visits` table and the same
      // permission, so they can only be dropped as a pair.
      final t = FirestoreSyncService.purgeTargetsFor(
        access({ClinicPermission.patientsView}),
      );
      expect(t.tables, contains('visits'));
      expect(t.watermarks, containsAll(['appointments', 'visitations']),
          reason: 'both watermarks must reset or a regained permission would '
              'resume from a watermark that no longer matches an empty table');
    });

    test('drops revenue but keeps billing records when only revenue is lost', () {
      final t = FirestoreSyncService.purgeTargetsFor(
        access({
          ClinicPermission.patientsView,
          ClinicPermission.schedule,
          ClinicPermission.billing,
        }),
      );
      expect(t.tables, contains('revenue_entries'));
      expect(t.tables, isNot(contains('pending_payments')));
    });

    test('drops inventory tables when inventory is lost', () {
      final t = FirestoreSyncService.purgeTargetsFor(
        access({ClinicPermission.patientsView}),
      );
      expect(t.tables, containsAll(['medicines', 'stock_transactions']));
    });

    test('drops everything permission-gated for a member holding nothing', () {
      final t = FirestoreSyncService.purgeTargetsFor(access({}));
      expect(
        t.tables,
        containsAll([
          'patients',
          'visits',
          'revenue_entries',
          'pending_payments',
          'medicines',
          'stock_transactions',
          'walk_in_queue',
          'dental_records',
          'radiology_docs',
        ]),
      );
    });

    test('an admin stripped of clinical access loses its cached records', () {
      // Separating administrative authority from clinical privilege has to
      // reach the device too, not only the rules.
      final strippedAdmin = access(
        ClinicPermission.values.toSet().difference(kClinicalPermissions),
        roleId: 'admin',
      );
      final t = FirestoreSyncService.purgeTargetsFor(strippedAdmin);
      expect(t.tables, containsAll(['dental_records', 'radiology_docs']));
      expect(t.tables, isNot(contains('patients')));
      expect(t.tables, isNot(contains('revenue_entries')));
    });

    test('a watermark is cleared for every table that is dropped', () {
      final t = FirestoreSyncService.purgeTargetsFor(access({}));
      for (final table in t.tables) {
        expect(t.watermarks, contains(table),
            reason: '$table was emptied without resetting its watermark');
      }
    });
  });
}
