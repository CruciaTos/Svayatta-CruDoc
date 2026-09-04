import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_catalog_model.dart';

void main() {
  group('DentalProcedureCatalogModel Serialization & Model Tests', () {
    final now = DateTime.now();
    final sampleModel = DentalProcedureCatalogModel(
      id: 'cat-123',
      doctorId: 'doc-456',
      code: 'RCT',
      name: 'Root Canal Treatment',
      category: 'endodontics',
      defaultPrice: 3500.0,
      defaultDurationMinutes: 60,
      requiresToothSelection: true,
      isActive: true,
      isDeleted: false,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'synced',
      pendingDelete: false,
      lastSyncedAt: now,
    );

    test('creates model with correct defaults', () {
      final model = DentalProcedureCatalogModel(
        id: 'cat-1',
        doctorId: 'doc-1',
        code: 'SCALE',
        name: 'Scaling & Polishing',
        createdAt: now,
        updatedAt: now,
      );

      expect(model.category, equals('general'));
      expect(model.defaultPrice, isNull);
      expect(model.defaultDurationMinutes, isNull);
      expect(model.requiresToothSelection, isTrue);
      expect(model.isActive, isTrue);
      expect(model.isDeleted, isFalse);
      expect(model.syncStatus, equals('synced'));
      expect(model.pendingDelete, isFalse);
      expect(model.lastSyncedAt, isNull);
    });

    test('round-trips through json / Firestore map without data loss', () {
      final json = sampleModel.toJson();
      expect(json['id'], equals('cat-123'));
      expect(json['code'], equals('RCT'));
      expect(json['createdAt'], isA<Timestamp>());

      final restored = DentalProcedureCatalogModel.fromJson(json);
      expect(restored.id, equals(sampleModel.id));
      expect(restored.doctorId, equals(sampleModel.doctorId));
      expect(restored.code, equals(sampleModel.code));
      expect(restored.name, equals(sampleModel.name));
      expect(restored.category, equals(sampleModel.category));
      expect(restored.defaultPrice, equals(sampleModel.defaultPrice));
      expect(restored.defaultDurationMinutes, equals(sampleModel.defaultDurationMinutes));
      expect(restored.requiresToothSelection, isTrue);
    });

    test('round-trips through SQLite map (toMap / fromMap)', () {
      final sqliteMap = sampleModel.toMap();
      expect(sqliteMap['createdAt'], equals(now.millisecondsSinceEpoch));
      expect(sqliteMap['requiresToothSelection'], equals(1));

      final restored = DentalProcedureCatalogModel.fromMap(sqliteMap);
      expect(restored.id, equals(sampleModel.id));
      expect(restored.code, equals(sampleModel.code));
      expect(restored.defaultPrice, equals(sampleModel.defaultPrice));
      expect(restored.requiresToothSelection, isTrue);
      expect(restored.isActive, isTrue);
    });

    test('copyWith updates specific fields and clear flags', () {
      final updated = sampleModel.copyWith(
        name: 'Molar RCT',
        defaultPrice: 4500.0,
        clearDefaultDuration: true,
      );

      expect(updated.name, equals('Molar RCT'));
      expect(updated.defaultPrice, equals(4500.0));
      expect(updated.defaultDurationMinutes, isNull);
      expect(updated.code, equals('RCT'));
    });

    test('equality and hashCode evaluate properly', () {
      final copy = sampleModel.copyWith();
      expect(copy, equals(sampleModel));
      expect(copy.hashCode, equals(sampleModel.hashCode));
    });
  });
}
