import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';

void main() {
  group('DoctorSpecialty', () {
    test('DoctorSpecialty.all only contains the 4 active specialties', () {
      final labels = DoctorSpecialty.all.map((s) => s.label).toList();
      final types = DoctorSpecialty.all.map((s) => s.type).toList();

      expect(DoctorSpecialty.all.length, 4);

      // Verify active specialties exist
      expect(types, contains(DoctorSpecialtyType.generalPhysician));
      expect(types, contains(DoctorSpecialtyType.physiotherapy));
      expect(types, contains(DoctorSpecialtyType.homeopathy));
      expect(types, contains(DoctorSpecialtyType.dentist));

      // Verify removed specialties are NOT in all
      expect(types, isNot(contains(DoctorSpecialtyType.cardiologist)));
      expect(types, isNot(contains(DoctorSpecialtyType.pediatrician)));
      expect(types, isNot(contains(DoctorSpecialtyType.dermatologist)));
      expect(types, isNot(contains(DoctorSpecialtyType.orthopedic)));
      expect(types, isNot(contains(DoctorSpecialtyType.gynecologist)));
      expect(types, isNot(contains(DoctorSpecialtyType.psychiatrist)));

      expect(labels, isNot(contains('Cardiologist')));
      expect(labels, isNot(contains('Pediatrician')));
      expect(labels, isNot(contains('Dermatologist')));
      expect(labels, isNot(contains('Orthopedic')));
      expect(labels, isNot(contains('Gynecologist')));
      expect(labels, isNot(contains('Psychiatrist')));
    });

    test(
      'DoctorSpecialty ofType and fromString resolve gracefully for legacy types',
      () {
        expect(
          DoctorSpecialty.ofType(DoctorSpecialtyType.cardiologist).label,
          'Cardiologist',
        );
        expect(
          DoctorSpecialty.fromString('Cardiologist').type,
          DoctorSpecialtyType.cardiologist,
        );
        expect(
          DoctorSpecialty.fromString('Orthopedic').type,
          DoctorSpecialtyType.orthopedic,
        );
        expect(
          DoctorSpecialty.fromString('Dentist').type,
          DoctorSpecialtyType.dentist,
        );
      },
    );
  });
}
