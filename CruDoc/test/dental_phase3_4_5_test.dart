import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/dental/data/models/sterilization_log_model.dart';
import 'package:doctor_management_app/features/dental/data/repositories/dental_repository.dart';
import 'package:doctor_management_app/features/dental/presentation/dental_inventory_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/dental_sterilization_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/widgets/dental_quick_actions_row.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DentalRepository repository;
  const testDoctorId = 'doc-test-ph345';

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await LocalDatabaseService.instance.ensureLocalDataMatchesSignedInDoctor(testDoctorId);
    repository = DentalRepository();
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 4 Sterilization Log Integration Tests', () {
    final now = DateTime.now();

    test('sterilization logs can be saved and queried in chronological order', () async {
      final cycle1 = SterilizationLogModel(
        id: 'ster-01',
        doctorId: testDoctorId,
        cycleDate: now.subtract(const Duration(hours: 2)),
        operatorName: 'Dr. Dental Operator',
        loadDescription: '5 Examination Kits, 3 Scalers',
        result: 'pass',
        notes: '134C, 30 psi, 15 min cycle',
        createdAt: now,
        updatedAt: now,
      );

      final cycle2 = SterilizationLogModel(
        id: 'ster-02',
        doctorId: testDoctorId,
        cycleDate: now,
        operatorName: 'Nurse Assistant',
        loadDescription: '10 Forceps, 4 Elevators',
        result: 'fail',
        notes: 'Pressure drop during holding phase',
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveSterilizationLog(cycle1);
      await repository.saveSterilizationLog(cycle2);

      final logs = await repository.getSterilizationLogs(testDoctorId);
      expect(logs.length, equals(2));
      // Ordered by cycleDate DESC
      expect(logs.first.id, equals('ster-02'));
      expect(logs.first.result, equals('fail'));
      expect(logs.last.id, equals('ster-01'));
      expect(logs.last.result, equals('pass'));
    });
  });

  group('Phase 3 Dental Inventory Screen Widget Tests', () {
    testWidgets('DentalInventoryScreen displays consumable items and low stock tags',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final dentalItems = [
        MedicineModel(
          id: 'med-composite',
          name: 'Composite Shade A2',
          category: 'Dental Restorative',
          unit: 'Syringes',
          currentStock: 4,
          reorderThreshold: 5,
          createdAt: now,
          updatedAt: now,
        ),
        MedicineModel(
          id: 'med-anesthetic',
          name: 'Lidocaine 2% Cartridges',
          category: 'Dental Anesthetic',
          unit: 'Cartridges',
          currentStock: 50,
          reorderThreshold: 20,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            medicinesStreamProvider.overrideWith(
              (ref) => Stream.value(dentalItems),
            ),
          ],
          child: const MaterialApp(
            home: DentalInventoryScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Dental Consumables & Stock'), findsOneWidget);
      expect(find.text('Composite Shade A2'), findsOneWidget);
      expect(find.text('Lidocaine 2% Cartridges'), findsOneWidget);
      expect(find.text('1 Low Stock'), findsOneWidget);
      expect(find.text('Add Consumable'), findsOneWidget);
    });
  });

  group('Phase 4 Dental Sterilization Screen Widget Tests', () {
    testWidgets('DentalSterilizationScreen renders cycle records and result badges',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final cycle = SterilizationLogModel(
        id: 'ster-widget-01',
        doctorId: testDoctorId,
        cycleDate: now,
        operatorName: 'Dr. Dentist',
        loadDescription: 'Exam Trays & Forceps',
        result: 'pass',
        notes: 'Chemical strip passed',
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveSterilizationLog(cycle);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dentalRepositoryProvider.overrideWithValue(repository),
            sterilizationLogProvider.overrideWith((ref, docId) async {
              return repository.getSterilizationLogs(docId);
            }),
          ],
          child: const MaterialApp(
            home: DentalSterilizationScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Autoclave Sterilization Log'), findsOneWidget);
      expect(find.text('PASS'), findsWidgets);
      expect(find.text('Log Cycle'), findsOneWidget);
      expect(find.textContaining('Exam Trays & Forceps'), findsOneWidget);
    });
  });

  group('Phase 5 Dental Quick Actions Row Widget Tests', () {
    testWidgets('DentalQuickActionsRow renders the 4 core dental actions and responds to taps',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testPatient = Patient(
        id: 'patient-quick-1',
        doctorId: testDoctorId,
        firstName: 'Quick',
        lastName: 'Patient',
        phone: '9876543210',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: 'Male',
        diagnosis: const [],
        packageBalance: 0.0,
        isArchived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dentalRepositoryProvider.overrideWithValue(repository),
            patientsStreamProvider.overrideWith(
              (ref) => Stream.value([testPatient]),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DentalQuickActionsRow(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('DENTAL QUICK ACTIONS'), findsOneWidget);
      expect(find.text('Tooth Chart'), findsOneWidget);
      expect(find.text('Procedure Log'), findsOneWidget);
      expect(find.text('Sterilization'), findsOneWidget);
      expect(find.text('Dental Inv.'), findsOneWidget);

      // Tap Tooth Chart -> opens patient selection sheet
      await tester.tap(find.text('Tooth Chart'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Select Patient for Tooth Chart'), findsOneWidget);
      expect(find.text('Quick Patient'), findsOneWidget);
    });
  });
}
