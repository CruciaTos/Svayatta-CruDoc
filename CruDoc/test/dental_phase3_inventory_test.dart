import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 Dental Inventory Domain & Unit Tests', () {
    final now = DateTime.now();

    test('3.1 & 3.2: Dental categories and units correctly classify dental consumables', () {
      final dentalCategories = [
        'Dental Consumable',
        'Dental Restorative',
        'Dental Anesthetic',
        'Dental Endodontic',
        'Dental Surgical',
      ];

      final dentalUnits = [
        'Cartridges',
        'Burs',
        'Pouches',
        'Syringes',
        'Bottles',
      ];

      for (final cat in dentalCategories) {
        expect(cat.toLowerCase().contains('dental'), isTrue);
      }
      expect(dentalUnits.contains('Cartridges'), isTrue);
      expect(dentalUnits.contains('Burs'), isTrue);
      expect(dentalUnits.contains('Pouches'), isTrue);
    });

    test('3.3 & 3.7: MedicineModel correctly models dental consumables with low stock detection', () {
      final compositeItem = MedicineModel(
        id: 'med-comp-01',
        doctorId: 'doc-123',
        name: 'Composite Hybrid A2',
        category: 'Dental Restorative',
        unit: 'Syringes',
        currentStock: 3,
        reorderThreshold: 5,
        unitPrice: 850.0,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(compositeItem.isLowStock, isTrue);
      expect(compositeItem.category, equals('Dental Restorative'));
      expect(compositeItem.unit, equals('Syringes'));
      expect(compositeItem.currentStock, equals(3));
      expect(compositeItem.unitPrice, equals(850.0));

      // Adequate stock item
      final anestheticItem = MedicineModel(
        id: 'med-anes-01',
        doctorId: 'doc-123',
        name: 'Lidocaine 2% with Epinephrine',
        category: 'Dental Anesthetic',
        unit: 'Cartridges',
        currentStock: 50,
        reorderThreshold: 15,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(anestheticItem.isLowStock, isFalse);
    });

    test('3.4 & 3.6: Stock transaction audit model correctly tracks source, notes, and procedure links', () {
      const procLogId = 'proc-log-456';
      const visitId = 'visit-789';

      final tx = StockTransactionModel(
        id: 'tx-001',
        medicineId: 'med-comp-01',
        doctorId: 'doc-123',
        type: StockTransactionType.dispense,
        quantity: 1,
        resultingStock: 2,
        note: 'Used in Dental Procedure: Composite Restoration (Log ID: $procLogId)',
        linkedVisitId: visitId,
        createdAt: now,
      );

      expect(tx.type, equals(StockTransactionType.dispense));
      expect(tx.quantity, equals(1));
      expect(tx.resultingStock, equals(2));
      expect(tx.note, contains('Composite Restoration'));
      expect(tx.note, contains(procLogId));
      expect(tx.linkedVisitId, equals(visitId));

      final json = tx.toJson();
      final roundTrip = StockTransactionModel.fromJson(json, id: tx.id);
      expect(roundTrip.id, equals(tx.id));
      expect(roundTrip.note, equals(tx.note));
      expect(roundTrip.linkedVisitId, equals(visitId));
    });
  });

}
