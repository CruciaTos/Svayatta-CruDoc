import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';

void main() {
  group('TreatmentPlanLineItemModel Tests', () {
    test('roundtrips through SQLite toMap and fromMap cleanly', () {
      final now = DateTime.now();
      final item = TreatmentPlanLineItemModel(
        id: 'plan-item-001',
        doctorId: 'doc-dentist-1',
        patientId: 'patient-42',
        treatmentPlanId: 'tp-100',
        procedureCatalogId: 'cat-rct',
        procedureName: 'Root Canal Treatment',
        toothNumbers: ['16', '17'],
        estimatedPrice: 6500.0,
        sequence: 1,
        status: 'proposed',
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
        syncStatus: 'synced',
        pendingDelete: false,
      );

      final map = item.toMap();
      expect(map['id'], 'plan-item-001');
      expect(map['doctorId'], 'doc-dentist-1');
      expect(map['patientId'], 'patient-42');
      expect(map['treatmentPlanId'], 'tp-100');
      expect(map['procedureCatalogId'], 'cat-rct');
      expect(map['procedureName'], 'Root Canal Treatment');
      expect(map['toothNumbers'], '["16","17"]');
      expect(map['estimatedPrice'], 6500.0);
      expect(map['sequence'], 1);
      expect(map['status'], 'proposed');
      expect(map['isDeleted'], 0);
      expect(map['syncStatus'], 'synced');

      final fromDb = TreatmentPlanLineItemModel.fromMap(map);
      expect(fromDb.id, item.id);
      expect(fromDb.doctorId, item.doctorId);
      expect(fromDb.patientId, item.patientId);
      expect(fromDb.treatmentPlanId, item.treatmentPlanId);
      expect(fromDb.procedureCatalogId, item.procedureCatalogId);
      expect(fromDb.procedureName, item.procedureName);
      expect(fromDb.toothNumbers, ['16', '17']);
      expect(fromDb.estimatedPrice, 6500.0);
      expect(fromDb.sequence, 1);
      expect(fromDb.status, 'proposed');
      expect(fromDb.isDeleted, false);
      expect(fromDb.syncStatus, 'synced');
    });

    test('roundtrips through Firestore toJson and fromJson cleanly', () {
      final now = DateTime.now();
      final item = TreatmentPlanLineItemModel(
        id: 'plan-item-002',
        doctorId: 'doc-dentist-1',
        patientId: 'patient-42',
        treatmentPlanId: 'tp-100',
        procedureCatalogId: 'cat-crown',
        procedureName: 'Ceramic Crown',
        toothNumbers: ['16'],
        estimatedPrice: 4000.0,
        sequence: 2,
        status: 'accepted',
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      final json = item.toJson();
      expect(json['id'], 'plan-item-002');
      expect(json['toothNumbers'], ['16']);
      expect(json['status'], 'accepted');
      expect(json['createdAt'], isA<Timestamp>());

      final parsed = TreatmentPlanLineItemModel.fromJson(json);
      expect(parsed.id, item.id);
      expect(parsed.toothNumbers, ['16']);
      expect(parsed.estimatedPrice, 4000.0);
      expect(parsed.status, 'accepted');
    });

    test('TreatmentPlanItemStatus helper maps labels and codes properly', () {
      expect(TreatmentPlanItemStatus.fromString('proposed'), TreatmentPlanItemStatus.proposed);
      expect(TreatmentPlanItemStatus.fromString('accepted'), TreatmentPlanItemStatus.accepted);
      expect(TreatmentPlanItemStatus.fromString('declined'), TreatmentPlanItemStatus.declined);
      expect(TreatmentPlanItemStatus.fromString('invoiced'), TreatmentPlanItemStatus.invoiced);
      expect(TreatmentPlanItemStatus.fromString(null), TreatmentPlanItemStatus.proposed);

      expect(TreatmentPlanItemStatus.proposed.label, 'Proposed');
      expect(TreatmentPlanItemStatus.accepted.label, 'Accepted');
      expect(TreatmentPlanItemStatus.declined.label, 'Declined');
      expect(TreatmentPlanItemStatus.invoiced.label, 'Invoiced');
    });
  });
}
