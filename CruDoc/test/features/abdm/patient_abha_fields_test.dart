import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

void main() {
  group('Patient ABHA fields', () {
    test('toMap / fromMap round trip preserves ABHA fields', () {
      final verifiedAt = DateTime(2026, 11, 27, 10, 30);
      final dob = DateTime(1990, 8, 15);
      final created = DateTime(2026, 1, 1);
      final updated = DateTime(2026, 11, 27);

      final p = Patient(
        id: 'p1',
        doctorId: 'd1',
        firstName: 'Asha',
        lastName: 'Rao',
        phone: '9876543210',
        gender: 'Female',
        dateOfBirth: dob,
        diagnosis: const [],
        packageBalance: 0,
        isArchived: false,
        createdAt: created,
        updatedAt: updated,
        abhaNumber: '91-1234-5678-9012',
        abhaAddress: 'asha@sbx',
        abhaVerifiedAt: verifiedAt,
      );

      final map = p.toMap();
      expect(map['abhaNumber'], '91-1234-5678-9012');
      expect(map['abhaAddress'], 'asha@sbx');
      expect(map['abhaVerifiedAt'], isA<Timestamp>());

      final decoded = Patient.fromMap(map, id: 'p1');
      expect(decoded.abhaNumber, '91-1234-5678-9012');
      expect(decoded.abhaAddress, 'asha@sbx');
      expect(decoded.abhaVerifiedAt, verifiedAt);
    });

    test('legacy map without ABHA fields loads with defaults', () {
      final legacyMap = <String, dynamic>{
        'doctorId': 'd1',
        'firstName': 'Ramesh',
        'lastName': 'Patil',
        'phone': '9822011111',
        'gender': 'Male',
        'dateOfBirth': Timestamp.fromDate(DateTime(1985, 5, 10)),
        'diagnosis': '[]',
        'packageBalance': 0,
        'isArchived': false,
        'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
      };

      final p = Patient.fromMap(legacyMap, id: 'p2');
      expect(p.abhaNumber, '');
      expect(p.abhaAddress, '');
      expect(p.abhaVerifiedAt, isNull);
    });
  });
}
