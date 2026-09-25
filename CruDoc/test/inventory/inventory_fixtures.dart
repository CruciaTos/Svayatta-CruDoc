// Test-only sample data mirroring the Inventory mock-ups
// (design/clinic-redesign/screens/inventory-*.png). Never imported by app
// code.
//
// Form, item type, batches and lead time are GAPs in the app, so the
// second line of each row shows the unit, and there is one batch per
// item. Dispensing is spread over the last 14 days so "Lasts" reads as
// in the mock-ups.

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';

import '../patients/patients_fixtures.dart' show fixtureIdentity, fixturePlan;

/// Wednesday 23 September 2026, 11:48 AM, as in the mock-ups.
final DateTime inventoryNow = DateTime(2026, 9, 23, 11, 48);

DateTime _ago(int days, [int hour = 10]) => DateTime(
      inventoryNow.year,
      inventoryNow.month,
      inventoryNow.day - days,
      hour,
    );

MedicineModel _med(
  String id,
  String name, {
  required String unit,
  required String category,
  required int stock,
  required int reorder,
  double? price,
  String? supplier,
  String? batch,
  DateTime? expiry,
}) =>
    MedicineModel(
      id: id,
      name: name,
      unit: unit,
      category: category,
      currentStock: stock,
      reorderThreshold: reorder,
      unitPrice: price,
      supplierName: supplier,
      batchNumber: batch,
      expiryDate: expiry,
      createdAt: _ago(200),
      updatedAt: _ago(1),
    );

/// [total] spread evenly over the 14 days (oldest first).
List<int> _spread(int total) => List.generate(
      14,
      (i) => total ~/ 14 + (i >= 14 - total % 14 ? 1 : 0),
    );

/// Dispense movements, one a day, from [perDay] (oldest first, last is
/// today), plus restocks of [restocks] a few months back.
List<StockTransactionModel> _history(
  String id, {
  List<int> perDay = const [],
  List<int> restocks = const [],
}) {
  final out = <StockTransactionModel>[];
  for (var i = 0; i < perDay.length; i++) {
    final q = perDay[i];
    if (q <= 0) continue;
    final ago = perDay.length - 1 - i;
    out.add(
      StockTransactionModel(
        id: '$id-d$i',
        medicineId: id,
        type: StockTransactionType.dispense,
        quantity: q,
        resultingStock: 0,
        createdAt: _ago(ago, ago == 0 ? 9 : 11),
      ),
    );
  }
  for (var i = 0; i < restocks.length; i++) {
    out.add(
      StockTransactionModel(
        id: '$id-r$i',
        medicineId: id,
        type: StockTransactionType.restock,
        quantity: restocks[i],
        resultingStock: 0,
        createdAt: _ago(30 + 25 * i),
      ),
    );
  }
  return out;
}

const _medicines = 'Medicines';
const _consumables = 'Consumables';
const _instruments = 'Instruments';

final List<MedicineModel> fixtureMedicines = [
  _med('paracetamol', 'Paracetamol 650 mg',
      unit: 'Strips', category: _medicines, stock: 12, reorder: 16,
      price: 30, supplier: 'Mehta Pharma', batch: 'B-2231',
      expiry: DateTime(2027, 3, 31)),
  _med('gloves', 'Gloves, medium',
      unit: 'Boxes', category: _consumables, stock: 2, reorder: 3,
      price: 420, supplier: 'Shree Surgicals'),
  _med('amoxicillin', 'Amoxicillin 500 mg',
      unit: 'Strips', category: _medicines, stock: 8, reorder: 10,
      price: 85, supplier: 'Mehta Pharma', batch: 'A-1180',
      expiry: DateTime(2027, 1, 31)),
  _med('sanitiser', 'Hand sanitiser',
      unit: 'Bottles', category: _consumables, stock: 5, reorder: 2,
      price: 120, supplier: 'Shree Surgicals'),
  _med('glucometer', 'Glucometer strips',
      unit: 'Packs', category: _consumables, stock: 4, reorder: 2,
      price: 650, supplier: 'Shree Surgicals', batch: 'G-0412',
      expiry: DateTime(2027, 6, 30)),
  _med('masks', 'Surgical masks',
      unit: 'Boxes', category: _consumables, stock: 7, reorder: 2,
      price: 150, supplier: 'Shree Surgicals'),
  _med('cetirizine', 'Cetirizine 10 mg',
      unit: 'Strips', category: _medicines, stock: 40, reorder: 10,
      price: 22, supplier: 'Mehta Pharma', batch: 'C-0907',
      expiry: DateTime(2026, 10, 28)),
  _med('ibuprofen', 'Ibuprofen 400 mg',
      unit: 'Strips', category: _medicines, stock: 30, reorder: 10,
      price: 28, supplier: 'Mehta Pharma', batch: 'I-3310',
      expiry: DateTime(2027, 4, 30)),
  _med('azithromycin', 'Azithromycin 500 mg',
      unit: 'Strips', category: _medicines, stock: 18, reorder: 6,
      price: 110, supplier: 'Mehta Pharma', batch: 'Z-5521',
      expiry: DateTime(2027, 2, 28)),
  _med('ors', 'ORS sachets',
      unit: 'Sachets', category: _medicines, stock: 60, reorder: 20,
      price: 21, supplier: 'Mehta Pharma', batch: 'O-7781',
      expiry: DateTime(2027, 6, 30)),
  _med('pantoprazole', 'Pantoprazole 40 mg',
      unit: 'Strips', category: _medicines, stock: 25, reorder: 10,
      price: 64, supplier: 'Mehta Pharma', batch: 'P-2040',
      expiry: DateTime(2027, 2, 28)),
  _med('metformin', 'Metformin 500 mg',
      unit: 'Strips', category: _medicines, stock: 32, reorder: 10,
      price: 18, supplier: 'Mehta Pharma', batch: 'M-6605',
      expiry: DateTime(2027, 8, 31)),
  _med('bandage', 'Bandage roll',
      unit: 'Rolls', category: _consumables, stock: 14, reorder: 4,
      price: 35, supplier: 'Shree Surgicals'),
  _med('micropore', 'Micropore tape',
      unit: 'Rolls', category: _consumables, stock: 10, reorder: 3,
      price: 45, supplier: 'Shree Surgicals'),
  _med('cotton', 'Cotton roll',
      unit: 'Rolls', category: _consumables, stock: 9, reorder: 3,
      price: 90, supplier: 'Shree Surgicals'),
  _med('syringes', 'Syringes, 5 ml',
      unit: 'Packs', category: _consumables, stock: 6, reorder: 2,
      price: 380, supplier: 'Shree Surgicals', batch: 'S-1188',
      expiry: DateTime(2028, 8, 31)),
  _med('thermometer', 'Digital thermometer',
      unit: 'Pcs', category: _instruments, stock: 3, reorder: 1,
      price: 250),
];

/// Movements per item. Paracetamol matches the panel's bars exactly
/// (37 strips, closed-looking days on the 13th and 20th).
final Map<String, List<StockTransactionModel>> fixtureHistory = {
  'paracetamol': _history(
    'paracetamol',
    perDay: const [3, 2, 4, 0, 3, 3, 2, 4, 3, 4, 0, 3, 4, 2],
    restocks: const [50, 50, 50],
  ),
  'gloves': _history('gloves', perDay: _spread(5), restocks: const [10, 10]),
  'amoxicillin':
      _history('amoxicillin', perDay: _spread(18), restocks: const [25, 25]),
  'sanitiser':
      _history('sanitiser', perDay: _spread(3), restocks: const [10, 10]),
  'glucometer':
      _history('glucometer', perDay: _spread(3), restocks: const [8, 8]),
  'masks': _history('masks', perDay: _spread(4), restocks: const [10, 10]),
  'cetirizine':
      _history('cetirizine', perDay: _spread(15), restocks: const [50, 50]),
  'ibuprofen':
      _history('ibuprofen', perDay: _spread(12), restocks: const [40, 40]),
  'azithromycin':
      _history('azithromycin', perDay: _spread(6), restocks: const [30, 30]),
  'ors': _history('ors', perDay: _spread(20), restocks: const [80, 80]),
  'pantoprazole':
      _history('pantoprazole', perDay: _spread(7), restocks: const [40, 40]),
  'metformin':
      _history('metformin', perDay: _spread(9), restocks: const [50, 50]),
  'bandage': _history('bandage', perDay: _spread(4), restocks: const [20, 20]),
  'micropore':
      _history('micropore', perDay: _spread(2), restocks: const [15, 15]),
  'cotton': _history('cotton', perDay: _spread(2), restocks: const [15, 15]),
  'syringes':
      _history('syringes', perDay: _spread(1), restocks: const [7, 7]),
  'thermometer': const [],
};

/// Every provider the Inventory Items section and the sidebar read,
/// replaced with fakes so no SQLite, Firebase or platform channel is
/// touched.
List<Override> inventoryOverrides({
  List<MedicineModel>? medicines,
  Map<String, List<StockTransactionModel>>? history,
  DateTime? now,
  int waiting = 2,
}) {
  final meds = medicines ?? fixtureMedicines;
  final movements = history ?? fixtureHistory;
  return [
    dashboardNowProvider.overrideWithValue(now ?? inventoryNow),
    medicinesStreamProvider.overrideWith((ref) => Stream.value(meds)),
    recentStockTransactionsProvider.overrideWith(
      (ref) => Stream.value(const <StockTransactionModel>[]),
    ),
    stockHistoryProvider.overrideWith((ref) async => movements),
    // Who is signed in (sidebar).
    authStateProvider.overrideWith((ref) => Stream.value(null)),
    doctorProfileProvider.overrideWith((ref) => Stream.value(null)),
    doctorIdentityProvider.overrideWithValue(fixtureIdentity),
    subscriptionInfoProvider.overrideWith((ref) => Stream.value(fixturePlan)),
    // Sidebar Queue badge ("• 2" in the mock-ups).
    waitingNowCountProvider.overrideWithValue(waiting),
  ];
}
