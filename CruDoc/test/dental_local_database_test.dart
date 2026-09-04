import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_catalog_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/sterilization_log_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await LocalDatabaseService.instance.ensureLocalDataMatchesSignedInDoctor('doc-test-123');
  });

  tearDown(() async {
    await db.close();
  });

  group('Dental SQLite Database Integration Tests', () {
    final now = DateTime.now();

    test('executes CRUD operations on dental_procedure_catalog table', () async {
      final dbInstance = await LocalDatabaseService.instance.localDatabase;
      final catalogItem = DentalProcedureCatalogModel(
        id: 'cat-db-1',
        doctorId: 'doc-test-123',
        code: 'RCT',
        name: 'Root Canal Treatment',
        category: 'endodontics',
        defaultPrice: 4000.0,
        createdAt: now,
        updatedAt: now,
      );

      // Insert
      await dbInstance.insert('dental_procedure_catalog', catalogItem.toMap());

      // Query
      final rows = await dbInstance.query(
        'dental_procedure_catalog',
        where: 'id = ?',
        whereArgs: ['cat-db-1'],
      );
      expect(rows, hasLength(1));
      final fetched = DentalProcedureCatalogModel.fromMap(rows.first);
      expect(fetched.code, equals('RCT'));
      expect(fetched.defaultPrice, equals(4000.0));
    });

    test('executes CRUD operations on tooth_chart_entries table', () async {
      final dbInstance = await LocalDatabaseService.instance.localDatabase;
      final toothEntry = ToothChartEntryModel(
        id: 'tooth-db-1',
        doctorId: 'doc-test-123',
        patientId: 'pat-456',
        toothNumber: '36',
        condition: 'caries',
        notes: 'Enamel decay',
        recordedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await dbInstance.insert('tooth_chart_entries', toothEntry.toMap());

      final rows = await dbInstance.query(
        'tooth_chart_entries',
        where: 'patientId = ? AND toothNumber = ?',
        whereArgs: ['pat-456', '36'],
      );
      expect(rows, hasLength(1));
      final fetched = ToothChartEntryModel.fromMap(rows.first);
      expect(fetched.toothNumber, equals('36'));
      expect(fetched.notes, equals('Enamel decay'));
    });

    test('executes CRUD operations on procedure_log_entries table', () async {
      final dbInstance = await LocalDatabaseService.instance.localDatabase;
      final procedureLog = DentalProcedureLogModel(
        id: 'log-db-1',
        doctorId: 'doc-test-123',
        patientId: 'pat-456',
        procedureName: 'Composite Restoration',
        toothNumbers: const ['36'],
        notes: 'Shade A2 used',
        performedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await dbInstance.insert('procedure_log_entries', procedureLog.toMap());

      final rows = await dbInstance.query(
        'procedure_log_entries',
        where: 'patientId = ?',
        whereArgs: ['pat-456'],
      );
      expect(rows, hasLength(1));
      final fetched = DentalProcedureLogModel.fromMap(rows.first);
      expect(fetched.procedureName, equals('Composite Restoration'));
      expect(fetched.toothNumbers, equals(['36']));
    });

    test('executes CRUD operations on sterilization_log_entries table', () async {
      final dbInstance = await LocalDatabaseService.instance.localDatabase;
      final sterilizationLog = SterilizationLogModel(
        id: 'ster-db-1',
        doctorId: 'doc-test-123',
        cycleDate: now,
        operatorName: 'Sunita (Assistant)',
        loadDescription: 'Pouches cycle 1',
        result: 'pass',
        createdAt: now,
        updatedAt: now,
      );

      await dbInstance.insert('sterilization_log_entries', sterilizationLog.toMap());

      final rows = await dbInstance.query(
        'sterilization_log_entries',
        where: 'doctorId = ?',
        whereArgs: ['doc-test-123'],
      );
      expect(rows, hasLength(1));
      final fetched = SterilizationLogModel.fromMap(rows.first);
      expect(fetched.operatorName, equals('Sunita (Assistant)'));
      expect(fetched.result, equals('pass'));
    });
  });
}
