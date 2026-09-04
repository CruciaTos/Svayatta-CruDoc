import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_catalog_model.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/data/repositories/dental_repository.dart';
import 'package:doctor_management_app/features/dental/data/seed/dental_catalog_seed.dart';
import 'package:doctor_management_app/features/dental/presentation/dental_procedure_catalog_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/widgets/dental_procedure_log_sheet.dart';
import 'package:doctor_management_app/features/dental/presentation/widgets/dental_treatment_plan_sheet.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/services/invoice_local_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DentalRepository repository;
  const testDoctorId = 'doc-test-ph2';
  const testPatientId = 'pat-test-ph2';

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await LocalDatabaseService.instance.ensureLocalDataMatchesSignedInDoctor(testDoctorId);
    repository = DentalRepository();
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 2 Dental Catalog & Repository Tests', () {
    final now = DateTime.now();

    test('archive and restore catalog items with includeArchived flag', () async {
      await DentalCatalogSeed.seedIfNeeded(repository, testDoctorId);
      final activeProcedures = await repository.getProcedureCatalog(testDoctorId);
      expect(activeProcedures, isNotEmpty);

      final first = activeProcedures.first;
      await repository.archiveCatalogItem(first.id);

      // Default active query should exclude it
      final afterArchive = await repository.getProcedureCatalog(testDoctorId, includeArchived: false);
      expect(afterArchive.any((p) => p.id == first.id), isFalse);

      // includeArchived query should include it with isActive = false
      final withArchived = await repository.getProcedureCatalog(testDoctorId, includeArchived: true);
      final archivedItem = withArchived.firstWhere((p) => p.id == first.id);
      expect(archivedItem.isActive, isFalse);

      // Restore it
      await repository.restoreCatalogItem(first.id);
      final restoredList = await repository.getProcedureCatalog(testDoctorId, includeArchived: false);
      expect(restoredList.any((p) => p.id == first.id), isTrue);
    });

    test('procedure logs can be saved, listed by patient/visit, and deleted', () async {
      final log = DentalProcedureLogModel(
        id: 'proc-log-01',
        doctorId: testDoctorId,
        patientId: testPatientId,
        visitId: 'visit-99',
        procedureCatalogId: 'cat-01',
        procedureName: 'Composite Restoration',
        toothNumbers: ['16'],
        status: 'completed',
        notes: 'Restored occlusal caries',
        performedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveProcedureLog(log);

      final patientLogs = await repository.getProcedureLogsForPatient(testPatientId);
      expect(patientLogs.length, equals(1));
      expect(patientLogs.first.procedureName, equals('Composite Restoration'));
      expect(patientLogs.first.toothNumbers, equals(['16']));

      final visitLogs = await repository.getProcedureLogsForVisit('visit-99');
      expect(visitLogs.length, equals(1));

      // Soft delete procedure log
      await repository.deleteProcedureLog('proc-log-01');
      final afterDelete = await repository.getProcedureLogsForPatient(testPatientId);
      expect(afterDelete, isEmpty);
    });

    test('treatment plan line items can be created, updated, and reordered', () async {
      final item1 = TreatmentPlanLineItemModel(
        id: 'plan-01',
        doctorId: testDoctorId,
        patientId: testPatientId,
        treatmentPlanId: 'tp-1',
        procedureName: 'Scaling & Polishing',
        toothNumbers: const [],
        estimatedPrice: 1500.0,
        sequence: 1,
        status: 'proposed',
        createdAt: now,
        updatedAt: now,
      );

      final item2 = TreatmentPlanLineItemModel(
        id: 'plan-02',
        doctorId: testDoctorId,
        patientId: testPatientId,
        treatmentPlanId: 'tp-1',
        procedureName: 'Root Canal Treatment',
        toothNumbers: const ['26'],
        estimatedPrice: 4000.0,
        sequence: 2,
        status: 'proposed',
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveTreatmentPlanLineItem(item1);
      await repository.saveTreatmentPlanLineItem(item2);

      final items = await repository.getTreatmentPlanLineItems(testPatientId);
      expect(items.length, equals(2));
      expect(items.first.procedureName, equals('Scaling & Polishing'));
      expect(items.last.procedureName, equals('Root Canal Treatment'));

      // Update status to accepted
      await repository.updateTreatmentPlanLineItemStatus('plan-02', 'accepted');
      final updatedItems = await repository.getTreatmentPlanLineItems(testPatientId);
      expect(updatedItems.firstWhere((i) => i.id == 'plan-02').status, equals('accepted'));

      // Delete item1
      await repository.deleteTreatmentPlanLineItem('plan-01');
      final remaining = await repository.getTreatmentPlanLineItems(testPatientId);
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('plan-02'));
    });

    test('invoice creation mapping converts treatment plan items accurately', () async {
      final items = [
        TreatmentPlanLineItemModel(
          id: 'item-1',
          doctorId: testDoctorId,
          patientId: testPatientId,
          treatmentPlanId: 'tp-1',
          procedureName: 'Root Canal Treatment',
          toothNumbers: const ['36'],
          estimatedPrice: 4500.0,
          status: 'accepted',
          createdAt: now,
          updatedAt: now,
        ),
        TreatmentPlanLineItemModel(
          id: 'item-2',
          doctorId: testDoctorId,
          patientId: testPatientId,
          treatmentPlanId: 'tp-1',
          procedureName: 'Ceramic Crown',
          toothNumbers: const ['36'],
          estimatedPrice: 4000.0,
          status: 'accepted',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final totalAmount = items.fold<double>(0.0, (sum, i) => sum + i.estimatedPrice);
      expect(totalAmount, equals(8500.0));

      final serviceSummary = items.map((item) {
        if (item.toothNumbers.isNotEmpty) {
          return '${item.procedureName} (Tooth ${item.toothNumbers.join(", ")})';
        }
        return item.procedureName;
      }).join('; ');

      final fullServiceName = 'Dental: $serviceSummary';
      expect(fullServiceName, equals('Dental: Root Canal Treatment (Tooth 36); Ceramic Crown (Tooth 36)'));

      final invoice = InvoiceModel(
        id: 'INV-TEST-001',
        doctorId: testDoctorId,
        patientId: testPatientId,
        patientName: 'John Dental Doe',
        service: fullServiceName,
        amount: totalAmount,
        status: 'Pending',
        date: now,
        createdAt: now,
        updatedAt: now,
      );

      await InvoiceLocalService().upsertInvoice(invoice);

      final doctorInvoices = await InvoiceLocalService().getInvoicesForDoctor(testDoctorId);
      expect(doctorInvoices.any((inv) => inv.id == 'INV-TEST-001'), isTrue);
      final retrieved = doctorInvoices.firstWhere((inv) => inv.id == 'INV-TEST-001');
      expect(retrieved.amount, equals(8500.0));
      expect(retrieved.service, contains('Root Canal Treatment'));
      expect(retrieved.service, contains('Ceramic Crown'));
    });
  });

  group('Phase 2 Widget Tests', () {
    testWidgets('DentalProcedureCatalogScreen renders search bar, category filter, and lists items',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await DentalCatalogSeed.seedIfNeeded(repository, testDoctorId);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dentalRepositoryProvider.overrideWithValue(repository),
            dentalCatalogProvider.overrideWith((ref, docId) async {
              return repository.getProcedureCatalog(docId, includeArchived: true);
            }),
          ],
          child: const MaterialApp(
            home: DentalProcedureCatalogScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Dental Procedure Catalog'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Add Procedure'), findsOneWidget);

      // Verify some seeded procedures are visible
      expect(find.text('Root Canal Treatment'), findsOneWidget);
    });

    testWidgets('DentalProcedureLogSheet renders form fields and allows adding teeth',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dentalRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DentalProcedureLogSheet(
                patientId: testPatientId,
                preselectedToothNumber: '36',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Log Dental Procedure'), findsOneWidget);
      expect(find.text('Tooth 36'), findsOneWidget); // preselected tooth
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Save Procedure Log'), findsOneWidget);
    });

    testWidgets('DentalTreatmentPlanSheet renders quote view and total', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final item = TreatmentPlanLineItemModel(
        id: 'plan-item-test',
        doctorId: testDoctorId,
        patientId: testPatientId,
        treatmentPlanId: 'tp_1',
        procedureName: 'Composite Filling',
        toothNumbers: const ['14'],
        estimatedPrice: 1200.0,
        status: 'proposed',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repository.saveTreatmentPlanLineItem(item);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dentalRepositoryProvider.overrideWithValue(repository),
            patientTreatmentPlanProvider.overrideWith((ref, patId) async {
              return repository.getTreatmentPlanLineItems(patId);
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DentalTreatmentPlanSheet(
                patientId: testPatientId,
                patientName: 'Jane Smith',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Treatment Plan & Quote'), findsOneWidget);
      expect(find.text('Jane Smith'), findsOneWidget);
      expect(find.text('Composite Filling'), findsOneWidget);
      expect(find.text('₹1200'), findsWidgets);
      expect(find.text('Create Invoice'), findsOneWidget);
    });
  });
}
