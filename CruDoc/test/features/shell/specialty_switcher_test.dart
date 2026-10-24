import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/features/shell/components/specialty_switcher_dialog.dart';

void main() {
  group('Specialty Switcher List & Dialog Tests', () {
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

    test('DoctorSpecialty ofType and fromString resolve gracefully for legacy types', () {
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
    });

    testWidgets('SpecialtySwitcherDialog renders only the 4 specialties on PC width', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SpecialtySwitcherDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expected active specialties present
      expect(find.text('General Physician'), findsWidgets);
      expect(find.text('Physiotherapist'), findsOneWidget);
      expect(find.text('Homeopath'), findsOneWidget);
      expect(find.text('Dentist'), findsOneWidget);

      // Removed specialties must not be in the dialog
      expect(find.text('Cardiologist'), findsNothing);
      expect(find.text('Pediatrician'), findsNothing);
      expect(find.text('Dermatologist'), findsNothing);
      expect(find.text('Orthopedic'), findsNothing);
      expect(find.text('Gynecologist'), findsNothing);
      expect(find.text('Psychiatrist'), findsNothing);
    });

    testWidgets('SpecialtySwitcherDialog renders only the 4 specialties on Mobile width', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SpecialtySwitcherDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expected active specialties present
      expect(find.text('General Physician'), findsWidgets);
      expect(find.text('Physiotherapist'), findsOneWidget);
      expect(find.text('Homeopath'), findsOneWidget);
      expect(find.text('Dentist'), findsOneWidget);

      // Removed specialties must not be in the dialog
      expect(find.text('Cardiologist'), findsNothing);
      expect(find.text('Pediatrician'), findsNothing);
      expect(find.text('Dermatologist'), findsNothing);
      expect(find.text('Orthopedic'), findsNothing);
      expect(find.text('Gynecologist'), findsNothing);
      expect(find.text('Psychiatrist'), findsNothing);
    });
  });
}
