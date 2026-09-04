import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/sterilization_log_model.dart';
import 'package:doctor_management_app/features/dental/data/repositories/dental_repository.dart';
import 'package:doctor_management_app/features/dental/data/seed/dental_catalog_seed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DentalRepository repository;
  const testDoctorId = 'doc-seed-123';
  const testPatientId = 'pat-seed-456';

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await LocalDatabaseService.instance.ensureLocalDataMatchesSignedInDoctor(testDoctorId);
    repository = DentalRepository();
  });

  tearDown(() async {
    await db.close();
  });

  group('DentalRepository & Seed Integration Tests', () {
    final now = DateTime.now();

    test('DentalCatalogSeed inserts default procedures for new doctor', () async {
      final initialList = await repository.getProcedureCatalog(testDoctorId);
      expect(initialList, isEmpty);

      final count = await DentalCatalogSeed.seedIfNeeded(repository, testDoctorId);
      expect(count, equals(DentalCatalogSeed.defaultTemplates.length));

      final seeded = await repository.getProcedureCatalog(testDoctorId);
      expect(seeded.length, equals(DentalCatalogSeed.defaultTemplates.length));

      final rct = seeded.firstWhere((e) => e.code == 'RCT');
      expect(rct.name, equals('Root Canal Treatment'));
      expect(rct.defaultPrice, equals(4000.0));
      expect(rct.requiresToothSelection, isTrue);
    });

    test('DentalCatalogSeed is idempotent on consecutive runs and preserves user edits', () async {
      await DentalCatalogSeed.seedIfNeeded(repository, testDoctorId);

      // Customize a price
      final catalog = await repository.getProcedureCatalog(testDoctorId);
      final rct = catalog.firstWhere((e) => e.code == 'RCT');
      final updatedRct = rct.copyWith(defaultPrice: 5500.0, name: 'Custom Molar RCT');
      await repository.saveCatalogItem(updatedRct);

      // Re-run seed
      final reSeedCount = await DentalCatalogSeed.seedIfNeeded(repository, testDoctorId);
      expect(reSeedCount, equals(0)); // 0 new items added

      final afterReSeed = await repository.getProcedureCatalog(testDoctorId);
      final rctAfter = afterReSeed.firstWhere((e) => e.code == 'RCT');
      expect(rctAfter.defaultPrice, equals(5500.0));
      expect(rctAfter.name, equals('Custom Molar RCT'));
    });

    test('Tooth chart repository operations query by patient and tooth number', () async {
      final entry1 = ToothChartEntryModel(
        id: 'tooth-repo-1',
        doctorId: testDoctorId,
        patientId: testPatientId,
        toothNumber: '11',
        condition: 'caries',
        recordedAt: now.subtract(const Duration(days: 2)),
        createdAt: now,
        updatedAt: now,
      );

      final entry2 = ToothChartEntryModel(
        id: 'tooth-repo-2',
        doctorId: testDoctorId,
        patientId: testPatientId,
        toothNumber: '11',
        treatment: 'filling',
        recordedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveToothChartEntry(entry1);
      await repository.saveToothChartEntry(entry2);

      final patientEntries = await repository.getToothChartForPatient(testPatientId);
      expect(patientEntries, hasLength(2));

      final tooth11History = await repository.getHistoryForTooth(testPatientId, '11');
      expect(tooth11History, hasLength(2));
      expect(tooth11History.first.treatment, equals('filling'));
    });

    test('Procedure log repository operations query by patientId and visitId', () async {
      final log1 = DentalProcedureLogModel(
        id: 'log-repo-1',
        doctorId: testDoctorId,
        patientId: testPatientId,
        visitId: 'visit-10',
        procedureName: 'Scaling & Polishing',
        performedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveProcedureLog(log1);

      final patientLogs = await repository.getProcedureLogsForPatient(testPatientId);
      expect(patientLogs, hasLength(1));

      final visitLogs = await repository.getProcedureLogsForVisit('visit-10');
      expect(visitLogs, hasLength(1));
      expect(visitLogs.first.procedureName, equals('Scaling & Polishing'));
    });

    test('Sterilization log repository operations query by doctorId', () async {
      final ster1 = SterilizationLogModel(
        id: 'ster-repo-1',
        doctorId: testDoctorId,
        cycleDate: now,
        operatorName: 'Dr. Soham',
        result: 'pass',
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveSterilizationLog(ster1);

      final sterLogs = await repository.getSterilizationLogs(testDoctorId);
      expect(sterLogs, hasLength(1));
      expect(sterLogs.first.operatorName, equals('Dr. Soham'));
    });
  });
}
