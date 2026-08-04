import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/core/services/doctor_encryption_service.dart';

void main() {
  group('DoctorEncryptionService', () {
    test('encrypts and decrypts doctor profile values for a specific doctor', () {
      const doctorId = 'doctor-123';
      const plainValue = 'Dr. Maya Patel';

      final encrypted = DoctorEncryptionService.encryptForDoctor(plainValue, doctorId);

      expect(encrypted, isNot(equals(plainValue)));
      expect(encrypted.startsWith('enc:v1:'), isTrue);
      expect(
        DoctorEncryptionService.decryptForDoctor(encrypted, doctorId),
        equals(plainValue),
      );
    });

    test('leaves already plain values unchanged', () {
      const doctorId = 'doctor-456';
      const plainValue = 'Clinic Name';

      expect(
        DoctorEncryptionService.decryptForDoctor(plainValue, doctorId),
        equals(plainValue),
      );
    });
  });
}
