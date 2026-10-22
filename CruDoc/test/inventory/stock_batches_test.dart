import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/domain/stock_batches.dart';

MedicineModel _item({
  int stock = 0,
  String? supplier,
  double? price,
  String? batch,
  DateTime? expiry,
}) => MedicineModel(
  id: 'axcer',
  name: 'Axcer 90',
  unit: 'Tablets',
  currentStock: stock,
  supplierName: supplier,
  unitPrice: price,
  batchNumber: batch,
  expiryDate: expiry,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

StockTransactionModel _bought(
  int qty,
  String batch,
  DateTime expiry, {
  double cost = 35,
  String supplier = 'Health Corner',
  int day = 1,
}) => StockTransactionModel(
  id: batch,
  medicineId: 'axcer',
  type: StockTransactionType.restock,
  quantity: qty,
  resultingStock: 0,
  createdAt: DateTime(2026, 10, day),
  batchNumber: batch,
  expiryDate: expiry,
  unitCost: cost,
  supplierName: supplier,
  billKey: 'b$day',
);

void main() {
  final box = _bought(120, 'GTH0601EA', DateTime(2029, 2, 28), day: 1);
  final strips = _bought(
    56,
    'GTC321A',
    DateTime(2028, 12, 31),
    cost: 35.09,
    supplier: 'MediCare',
    day: 2,
  );

  test('every batch bought is in stock until some is used', () {
    final batches = remainingBatches(_item(stock: 176), [box, strips]);
    expect(batches.map((b) => (b.batch, b.quantity)), [
      ('GTC321A', 56), // expires first: use first
      ('GTH0601EA', 120),
    ]);
    expect(batches.first.supplier, 'MediCare');
  });

  test('used stock comes off the batch that expires first', () {
    final batches = remainingBatches(_item(stock: 150), [box, strips]);
    expect(batches.map((b) => (b.batch, b.quantity)), [
      ('GTC321A', 30),
      ('GTH0601EA', 120),
    ]);
    expect(
      remainingBatches(_item(stock: 100), [box, strips]).map((b) => b.batch),
      ['GTH0601EA'],
    );
    expect(remainingBatches(_item(), [box, strips]), isEmpty);
  });

  test('stock entered by hand is the item\'s own batch', () {
    final old = _item(
      stock: 130,
      supplier: 'Old Distributor',
      price: 30,
      batch: 'OLD1',
      expiry: DateTime(2027, 1, 31),
    );
    final batches = remainingBatches(old, [box]);
    expect(batches.map((b) => (b.batch, b.quantity, b.supplier)), [
      ('OLD1', 10, 'Old Distributor'),
      ('GTH0601EA', 120, 'Health Corner'),
    ]);
    expect(remainingBatches(old, const []).single.quantity, 130);
  });

  test('average cost over the batches in stock', () {
    final batches = remainingBatches(_item(stock: 176), [box, strips]);
    expect(averageCost(batches)! * 176, closeTo(120 * 35 + 56 * 35.09, 1e-9));
    expect(averageCost(const []), isNull);
  });

  test('each supplier is worth its own batches', () {
    final stock = stockBySupplier([_item(stock: 176)], [box, strips]);
    expect(stock['Health Corner']!.value, closeTo(120 * 35, 1e-9));
    expect(stock['MediCare']!.value, closeTo(56 * 35.09, 1e-9));
    expect(stock['MediCare']!.itemIds, {'axcer'});
  });

  test('an item out of stock is still listed under its supplier', () {
    final stock = stockBySupplier([_item(supplier: 'Health Corner')], [box]);
    expect(stock['Health Corner']!.itemIds, {'axcer'});
    expect(stock['Health Corner']!.hasValue, isFalse);
  });
}
