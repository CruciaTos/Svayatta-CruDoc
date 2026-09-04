import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';

void main() {
  final now = DateTime.now();

  group('ToothChartEntryModel Tests', () {
    final sampleToothEntry = ToothChartEntryModel(
      id: 'tooth-1',
      doctorId: 'doc-1',
      patientId: 'pat-1',
      toothNumber: '36',
      notationSystem: 'fdi',
      surface: 'occlusal',
      condition: 'caries',
      treatment: 'filling',
      procedureLogId: 'log-100',
      notes: 'Deep occlusal pit caries treated',
      recordedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    test('creates tooth chart entry with correct FDI default notation', () {
      expect(sampleToothEntry.notationSystem, equals('fdi'));
      expect(sampleToothEntry.toothNumber, equals('36'));
      expect(sampleToothEntry.notes, equals('Deep occlusal pit caries treated'));
    });

    test('parses ToothNotationSystem and ToothSurface enums correctly', () {
      expect(ToothNotationSystem.fromString('fdi'), equals(ToothNotationSystem.fdi));
      expect(ToothNotationSystem.fromString('universal'), equals(ToothNotationSystem.universal));
      expect(ToothNotationSystem.fromString('palmer'), equals(ToothNotationSystem.palmer));

      expect(ToothSurface.fromString('mesial'), equals(ToothSurface.mesial));
      expect(ToothSurface.fromString('occlusal'), equals(ToothSurface.occlusal));
      expect(ToothCondition.fromString('caries'), equals(ToothCondition.caries));
      expect(ToothTreatment.fromString('rct'), equals(ToothTreatment.rct));
    });

    test('serializes to Firestore map and decrypts notes on deserialization', () {
      final json = sampleToothEntry.toJson();
      expect(json['id'], equals('tooth-1'));
      expect(json['toothNumber'], equals('36'));
      expect(json['recordedAt'], isA<Timestamp>());

      final restored = ToothChartEntryModel.fromJson(json);
      expect(restored.id, equals(sampleToothEntry.id));
      expect(restored.toothNumber, equals(sampleToothEntry.toothNumber));
      expect(restored.surface, equals(sampleToothEntry.surface));
      expect(restored.condition, equals(sampleToothEntry.condition));
      expect(restored.treatment, equals(sampleToothEntry.treatment));
      expect(restored.notes, equals('Deep occlusal pit caries treated'));
    });

    test('round-trips through SQLite toMap / fromMap', () {
      final map = sampleToothEntry.toMap();
      expect(map['recordedAt'], equals(now.millisecondsSinceEpoch));

      final restored = ToothChartEntryModel.fromMap(map);
      expect(restored.id, equals(sampleToothEntry.id));
      expect(restored.toothNumber, equals('36'));
      expect(restored.notes, equals('Deep occlusal pit caries treated'));
    });
  });

  group('DentalProcedureLogModel Tests', () {
    final sampleProcedureLog = DentalProcedureLogModel(
      id: 'log-1',
      doctorId: 'doc-1',
      patientId: 'pat-1',
      visitId: 'visit-99',
      procedureCatalogId: 'cat-rct',
      procedureName: 'Root Canal Treatment',
      toothNumbers: const ['16', '17'],
      notationSystem: 'fdi',
      status: 'completed',
      notes: 'Single visit endodontic therapy completed',
      materials: 'Gutta-percha, AH Plus sealer',
      performedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    test('creates procedure log linked to multiple teeth', () {
      expect(sampleProcedureLog.toothNumbers, equals(['16', '17']));
      expect(sampleProcedureLog.procedureName, equals('Root Canal Treatment'));
      expect(sampleProcedureLog.status, equals('completed'));
    });

    test('parses DentalProcedureStatus enum correctly', () {
      expect(DentalProcedureStatus.fromString('planned'), equals(DentalProcedureStatus.planned));
      expect(DentalProcedureStatus.fromString('inProgress'), equals(DentalProcedureStatus.inProgress));
      expect(DentalProcedureStatus.fromString('completed'), equals(DentalProcedureStatus.completed));
      expect(DentalProcedureStatus.fromString('unknown'), equals(DentalProcedureStatus.completed));
    });

    test('serializes to Firestore map and restores encrypted notes/materials', () {
      final json = sampleProcedureLog.toJson();
      expect(json['procedureName'], equals('Root Canal Treatment'));
      expect(json['toothNumbers'], equals(['16', '17']));

      final restored = DentalProcedureLogModel.fromJson(json);
      expect(restored.id, equals(sampleProcedureLog.id));
      expect(restored.toothNumbers, equals(['16', '17']));
      expect(restored.notes, equals('Single visit endodontic therapy completed'));
      expect(restored.materials, equals('Gutta-percha, AH Plus sealer'));
    });

    test('round-trips through SQLite toMap / fromMap with JSON toothNumbers list', () {
      final map = sampleProcedureLog.toMap();
      expect(map['toothNumbers'], isA<String>()); // JSON stringified list

      final restored = DentalProcedureLogModel.fromMap(map);
      expect(restored.id, equals(sampleProcedureLog.id));
      expect(restored.toothNumbers, equals(['16', '17']));
      expect(restored.notes, equals('Single visit endodontic therapy completed'));
      expect(restored.materials, equals('Gutta-percha, AH Plus sealer'));
    });

    test('handles zero tooth numbers gracefully (e.g. consultation)', () {
      final consultationLog = DentalProcedureLogModel(
        id: 'log-2',
        doctorId: 'doc-1',
        patientId: 'pat-1',
        procedureName: 'General Dental Consultation',
        toothNumbers: const [],
        performedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      final map = consultationLog.toMap();
      final restored = DentalProcedureLogModel.fromMap(map);
      expect(restored.toothNumbers, isEmpty);
    });
  });
}
