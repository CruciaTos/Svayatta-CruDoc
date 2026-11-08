import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/patients/domain/quick_patient.dart';

void main() {
  group('quickPatient', () {
    test('"Smit Mhatre" gives first "Smit", last "Mhatre"', () {
      final p = quickPatient('Smit Mhatre');
      expect(p.firstName, 'Smit');
      expect(p.lastName, 'Mhatre');
    });

    test('"Smit" gives an empty last name', () {
      final p = quickPatient('Smit');
      expect(p.firstName, 'Smit');
      expect(p.lastName, '');
    });

    test('the phone is trimmed', () {
      final p = quickPatient('Smit Mhatre', phone: '  9321559866  ');
      expect(p.phone, '9321559866');
    });

    test(
      'patientDetailsPending is true for empty phone and false for "9321559866"',
      () {
        final pNoPhone = quickPatient('Smit Mhatre');
        expect(patientDetailsPending(pNoPhone), isTrue);

        final pWhitespace = quickPatient('Smit Mhatre', phone: '   ');
        expect(patientDetailsPending(pWhitespace), isTrue);

        final pWithPhone = quickPatient('Smit Mhatre', phone: '9321559866');
        expect(patientDetailsPending(pWithPhone), isFalse);
      },
    );
  });
}
