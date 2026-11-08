import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/patients/domain/duplicate_patient.dart';
import 'package:doctor_management_app/features/patients/domain/quick_patient.dart';

void main() {
  group('duplicateByPhone', () {
    final p1 = quickPatient('Rahul Sharma', phone: '9876543210');
    final p2 = quickPatient('Anita Rao', phone: '9123456789');
    final existing = [p1, p2];

    test('same number with spaces and "+91" matches', () {
      final match = duplicateByPhone(existing, '+91 98765 43210');
      expect(match, equals(p1));
    });

    test('fewer than 7 digits returns null', () {
      expect(duplicateByPhone(existing, '123456'), isNull);
      expect(duplicateByPhone(existing, '  123  '), isNull);
    });

    test('a different number returns null', () {
      expect(duplicateByPhone(existing, '9999999999'), isNull);
      expect(duplicateByPhone(existing, '9876500000'), isNull);
    });
  });
}

