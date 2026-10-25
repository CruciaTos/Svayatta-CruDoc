import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/dental/data/models/sterilization_log_model.dart';
import 'package:doctor_management_app/features/dental/data/repositories/dental_repository.dart';

import 'support/isolated_app_dirs.dart';

void main() {
  useIsolatedAppDirs();
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DentalRepository repository;
  const testDoctorId = 'doc-test-ph345';

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await LocalDatabaseService.instance.ensureLocalDataMatchesSignedInDoctor(testDoctorId);
    // The repository uses the real local database file, which outlives a
    // run: start every test from empty, or earlier rows change the counts.
    await LocalDatabaseService.instance.wipeAllLocalData();
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

}
