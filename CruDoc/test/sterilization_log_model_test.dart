import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/dental/data/models/sterilization_log_model.dart';

void main() {
  group('SterilizationLogModel Tests', () {
    final now = DateTime.now();
    final sampleSterilizationLog = SterilizationLogModel(
      id: 'ster-1',
      doctorId: 'doc-1',
      cycleDate: now,
      operatorName: 'Ramesh (Staff)',
      loadDescription: '5 Pouches - Extraction Forceps, Mirror Sets',
      result: 'pass',
      notes: 'Autoclave 121°C 15 psi 20 mins',
      createdAt: now,
      updatedAt: now,
    );

    test('creates clinic-level sterilization log without patientId field', () {
      expect(sampleSterilizationLog.doctorId, equals('doc-1'));
      expect(sampleSterilizationLog.operatorName, equals('Ramesh (Staff)'));
      expect(sampleSterilizationLog.result, equals('pass'));
    });

    test('parses SterilizationResult enum values accurately', () {
      expect(SterilizationResult.fromString('pass'), equals(SterilizationResult.pass));
      expect(SterilizationResult.fromString('fail'), equals(SterilizationResult.fail));
      expect(SterilizationResult.fromString('incomplete'), equals(SterilizationResult.incomplete));
      expect(SterilizationResult.fromString(null), equals(SterilizationResult.pass));
    });

    test('serializes to Firestore map and restores plaintext operational fields', () {
      final json = sampleSterilizationLog.toJson();
      expect(json['id'], equals('ster-1'));
      expect(json['operatorName'], equals('Ramesh (Staff)'));
      expect(json['cycleDate'], isA<Timestamp>());

      final restored = SterilizationLogModel.fromJson(json);
      expect(restored.id, equals(sampleSterilizationLog.id));
      expect(restored.doctorId, equals(sampleSterilizationLog.doctorId));
      expect(restored.operatorName, equals(sampleSterilizationLog.operatorName));
      expect(restored.loadDescription, equals(sampleSterilizationLog.loadDescription));
      expect(restored.result, equals('pass'));
      expect(restored.notes, equals('Autoclave 121°C 15 psi 20 mins'));
    });

    test('round-trips through SQLite toMap / fromMap', () {
      final map = sampleSterilizationLog.toMap();
      expect(map['cycleDate'], equals(now.millisecondsSinceEpoch));

      final restored = SterilizationLogModel.fromMap(map);
      expect(restored.id, equals(sampleSterilizationLog.id));
      expect(restored.operatorName, equals(sampleSterilizationLog.operatorName));
      expect(restored.result, equals(sampleSterilizationLog.result));
    });
  });
}
