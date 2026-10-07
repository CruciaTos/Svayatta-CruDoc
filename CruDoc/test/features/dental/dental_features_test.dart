import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/dental_features.dart';

void main() {
  group('DentalFeature tests', () {
    test('1. parse tests', () {
      expect(
        DentalFeature.parse(['perio', 'bogus', 'radiology']),
        equals({DentalFeature.perio, DentalFeature.radiology}),
      );
      expect(DentalFeature.parse(null), isNull);
      expect(DentalFeature.parse('x'), isNull);
    });

    test('2. fromLegacySpecialty Periodontist', () {
      expect(
        DentalFeature.fromLegacySpecialty('Periodontist'),
        equals({
          DentalFeature.chairside,
          DentalFeature.radiology,
          DentalFeature.perio,
        }),
      );
    });

    test('3. fromLegacySpecialty Oral & Maxillofacial Radiologist, shortLabel, type name', () {
      expect(
        DentalFeature.fromLegacySpecialty('Oral & Maxillofacial Radiologist'),
        equals({DentalFeature.radiology}),
      );
      expect(
        DentalFeature.fromLegacySpecialty('OMR'),
        equals({DentalFeature.radiology}),
      );
      expect(
        DentalFeature.fromLegacySpecialty('oralRadiologist'),
        equals({DentalFeature.radiology}),
      );
    });

    test('4. fromLegacySpecialty Dentist and null returns defaults', () {
      expect(
        DentalFeature.fromLegacySpecialty('Dentist'),
        equals(DentalFeature.defaults),
      );
      expect(
        DentalFeature.fromLegacySpecialty(null),
        equals(DentalFeature.defaults),
      );
    });

    test('5. allowsTab tests', () {
      expect(
        DentalFeature.allowsTab(DesktopTab.labCases, {DentalFeature.chairside}),
        isFalse,
      );
      expect(
        DentalFeature.allowsTab(DesktopTab.labCases, {DentalFeature.chairside, DentalFeature.prostho}),
        isTrue,
      );
      expect(
        DentalFeature.allowsTab(DesktopTab.revenue, {}),
        isTrue,
      );
    });

    test('6. DoctorSpecialty.fromString Endodontist resolves to Dentist', () {
      expect(
        DoctorSpecialty.fromString('Endodontist').type,
        equals(DoctorSpecialtyType.dentist),
      );
    });

    test('7. "Ortho" stays Orthopedic (shared short label)', () {
      expect(
        DoctorSpecialty.fromString('Ortho').type,
        equals(DoctorSpecialtyType.orthopedic),
      );
      expect(
        DoctorSpecialty.fromString('Orthodontist').type,
        equals(DoctorSpecialtyType.dentist),
      );
    });
  });
}
