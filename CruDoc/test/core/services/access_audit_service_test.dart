import 'package:doctor_management_app/core/services/access_audit_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('patientIdFromPath', () {
    test('reads the patient id from a patient file path', () {
      expect(
        AccessAuditService.patientIdFromPath(
          'doctors/d1/patients/p42/clinical/xrays/2026/09/a.jpg',
        ),
        'p42',
      );
    });

    test('is null for clinic-level files', () {
      expect(
        AccessAuditService.patientIdFromPath('doctors/d1/backups/2026/b.enc'),
        isNull,
      );
      expect(AccessAuditService.patientIdFromPath('doctors/d1/patients'), isNull);
      expect(AccessAuditService.patientIdFromPath('doctors/d1/patients/'), isNull);
    });
  });

  group('shouldLog', () {
    final service = AccessAuditService.instance;
    final t0 = DateTime(2026, 9, 30, 10);

    test('logs once per record within the window', () {
      expect(service.shouldLog('k1', t0), isTrue);
      expect(service.shouldLog('k1', t0.add(const Duration(minutes: 4))), isFalse);
      expect(service.shouldLog('k2', t0), isTrue);
    });

    test('logs again once the window has passed', () {
      expect(service.shouldLog('k3', t0), isTrue);
      expect(
        service.shouldLog('k3', t0.add(AccessAuditService.dedupeWindow)),
        isTrue,
      );
    });
  });

  test('does nothing, and does not throw, without Firebase', () {
    expect(() => AccessAuditService.instance.patientViewed('p1'), returnsNormally);
    expect(
      () => AccessAuditService.instance.fileDownloaded('doctors/d/patients/p/x.pdf'),
      returnsNormally,
    );
  });
}
