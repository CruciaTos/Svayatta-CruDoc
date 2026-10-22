import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';
import 'package:doctor_management_app/features/inventory/domain/bill_import.dart';
import 'package:doctor_management_app/features/inventory/domain/stock_batches.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_bill_review_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// An inventory in memory: keeps what the dialog writes (items, stock
/// movements with their purchase details, updates), so a second bill sees
/// the first one's items and purchases.
class _Inventory implements InventoryRepository {
  _Inventory([List<MedicineModel> items = const []]) : items = [...items];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final List<MedicineModel> items;
  final moves = <StockTransactionModel>[];
  final updates = <String, Map<String, dynamic>>{};

  MedicineModel named(String name) => items.singleWhere((m) => m.name == name);

  /// What the stock from [supplier] is worth, batch by batch.
  double valueFrom(String supplier) =>
      stockBySupplier(items, moves)[supplier]?.value ?? 0;

  @override
  Stream<List<MedicineModel>> watchMedicines() => Stream.value([...items]);

  @override
  Future<String> createMedicine(MedicineModel medicine) async {
    final id = 'm${items.length}';
    items.add(
      MedicineModel.fromJson({
        ...medicine.toJson(),
        'id': id,
      }).copyWith(unitPrice: medicine.unitPrice),
    );
    return id;
  }

  @override
  Future<StockTransactionModel> recordTransaction({
    required String medicineId,
    required StockTransactionType type,
    required int quantity,
    String? note,
    String? linkedVisitId,
    String? batchNumber,
    DateTime? expiryDate,
    double? unitCost,
    String? supplierName,
    String? billKey,
  }) async {
    final i = items.indexWhere((m) => m.id == medicineId);
    items[i] = items[i].copyWith(
      currentStock: items[i].currentStock + quantity,
    );
    final move = StockTransactionModel(
      id: 't${moves.length}',
      medicineId: medicineId,
      type: type,
      quantity: quantity,
      resultingStock: items[i].currentStock,
      note: note,
      createdAt: DateTime(2026, 10, 22, 0, moves.length),
      batchNumber: batchNumber,
      expiryDate: expiryDate,
      unitCost: unitCost,
      supplierName: supplierName,
      billKey: billKey,
    );
    moves.add(move);
    return move;
  }

  @override
  Future<List<StockTransactionModel>> getTransactionsForMedicine(
    String medicineId,
  ) async => moves.where((m) => m.medicineId == medicineId).toList();

  @override
  Future<List<StockTransactionModel>> getPurchases({String? billKey}) async =>
      moves
          .where(
            (m) => m.isPurchase && (billKey == null || m.billKey == billKey),
          )
          .toList();

  @override
  Future<void> updateMedicine(String id, Map<String, dynamic> data) async {
    updates[id] = data;
    final i = items.indexWhere((m) => m.id == id);
    items[i] = items[i].copyWith(
      unitPrice: data['unitPrice'] as double?,
      supplierName: data['supplierName'] as String?,
      expiryDate: data['expiryDate'] as DateTime?,
      batchNumber: data['batchNumber'] as String?,
    );
  }
}

MedicineModel _item(
  String name, {
  String unit = 'Tablets',
  int stock = 0,
  DateTime? expiry,
}) => MedicineModel(
  id: name,
  name: name,
  unit: unit,
  currentStock: stock,
  expiryDate: expiry,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

const _bill = ScannedBill(
  source: 'sarvam',
  supplier: 'SHREE GANESH PHARMA DISTRIBUTORS',
  invoiceNumber: 'SGPD/2026/04512',
  invoiceDate: '14/10/2026',
  items: [
    BillLine(
      name: 'DOLO 650 TAB',
      pack: "15'S",
      batch: 'DL24A91',
      expiry: '03/28',
      quantity: 10,
      freeQuantity: 1,
      rate: 24.1,
    ),
    BillLine(
      name: 'PANTOCID 40MG TAB',
      pack: "10'S",
      batch: 'PT77812',
      expiry: '09/27',
      quantity: 6,
      rate: 112.4,
    ),
    BillLine(name: 'VOLINI GEL 30GM', pack: "1'S", quantity: 5, rate: 104.5),
  ],
);

/// Sarvam's reading of two Health Corner bills: the same medicines in
/// different packs (Axcer as a box of 120 and as strips of 14), names
/// misread on one ("GENER", "KENIA", "TELHA"), and repeated lines. Their
/// values include GST: they add up to the amount payable.
const _health = 'HEALTH CORNER MEDICAL AND GENERAL STORE';
BillLine _l(String name, String pack, double qty, double rate) => BillLine(
  name: name,
  pack: pack,
  quantity: qty,
  rate: rate,
  amount: qty * rate,
);
final _bill7021 = ScannedBill(
  source: 'sarvam',
  supplier: _health,
  invoiceNumber: '165534',
  grandTotal: 7021.84,
  taxPercent: 5, // misread: the bill mixes 5% and 18%, already in prices
  amountsIncludeTax: false, // and Sarvam called it wrong
  items: [
    _l('GEMER 1MG', '10T', 1, 167.81),
    _l('GEMER 1MG', '10T', 2, 167.81),
    _l('UNISTAR 20/75', '10C', 4, 150.9),
    _l('PANTAKIND', '15T', 3, 87.38),
    _l('TELHA 40MG (30T)', '30T', 2, 216.72),
    _l('KENIA ST 25', '15T', 1, 206.44),
    _l('KENIA ST 25', '15T', 2, 206.44),
    _l('CONCOR COR 2.5MG', '10T', 4, 97.4),
    _l('AXCER 90', '120T', 1, 4210.31),
  ],
);
final _bill4092 = ScannedBill(
  source: 'sarvam',
  supplier: _health,
  invoiceNumber: '160489',
  grandTotal: 4092.7, // the last digit is torn off the bill
  items: [
    _l('GENER 1MG', '10T', 1, 153.28),
    _l('UNISTAR 20/75', '10C', 3, 150.9),
    _l('PANTAKIND', '15T', 2, 87.38),
    _l('TELMA 40MG (30T)', '30T', 1, 216.72),
    _l('LIVON SERUM', '20HL', 1, 70),
    _l('GARN COL MAT ORG BLK 2.0', '2.0', 2, 45),
    _l('XENIA ST 25', '15T', 2, 206.44),
    _l('CONCOR COR 2.5MG', '10T', 3, 97.4),
    _l('CONCOR COR 2.5MG', '10T', 1, 97.4),
    _l('AXCER 90', '14T', 1, 491.25),
    _l('AXCER 90', '14T', 1, 491.25),
    _l('AXCER 90', '14T', 2, 982.5 / 2),
    _l('GEHER 1MG', '10T', 1, 167.81),
  ],
);

/// MediCare Wholesale's bill: 10% off every line, 12% IGST on top.
const _medicare = ScannedBill(
  source: 'sarvam',
  supplier: 'MediCare Wholesale Pharmacy',
  invoiceNumber: '27',
  subtotal: 2205,
  taxAmount: 264.6,
  taxPercent: 12,
  grandTotal: 2469.6,
  items: [
    BillLine(
      name: 'Paracetamol 500 mg',
      quantity: 10,
      quantityUnit: 'TBS',
      rate: 40,
      discountPercent: 10,
      amount: 360,
    ),
    BillLine(
      name: 'Cough Syrup (200ml)',
      pack: '200ml',
      quantity: 20,
      quantityUnit: 'BTL',
      rate: 80,
      discountPercent: 10,
      amount: 1440,
    ),
    BillLine(
      name: 'Antibiotic Cream (30g)',
      pack: '30g',
      quantity: 10,
      quantityUnit: 'PKG',
      rate: 45,
      discountPercent: 10,
      amount: 405,
    ),
  ],
);

/// Opens the dialog; the returned function gives what it closed with.
Future<BillReviewOutcome? Function()> _open(
  WidgetTester tester,
  InventoryRepository repo, {
  Future<ScannedBill> Function(String)? scan,
}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  BillReviewOutcome? outcome;
  await tester.pumpWidget(
    MaterialApp(
      theme: CruTheme.day(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              outcome = await showDialog<BillReviewOutcome>(
                context: context,
                builder: (_) => DesktopBillReviewDialog(
                  // Not an image: no receipt upload in tests.
                  image: XFile('bill.txt'),
                  repository: repo,
                  scan: scan ?? (_) async => _bill,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => outcome;
}

Future<void> _add(WidgetTester tester, String button) async {
  await tester.tap(find.text(button));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists every line; adds new items and restocks known ones', (
    tester,
  ) async {
    final repo = _Inventory([
      _item('Pantocid 40 mg', stock: 12, expiry: DateTime(2027, 1, 31)),
    ]);
    final outcome = await _open(tester, repo);

    expect(find.text('Add from bill'), findsOneWidget);
    expect(
      find.text(
        'Shree Ganesh Pharma Distributors · Invoice SGPD/2026/04512 · 14/10/2026',
      ),
      findsOneWidget,
    );
    expect(find.text('Dolo 650'), findsOneWidget);
    expect(find.text('165'), findsOneWidget, reason: '11 strips of 15');
    expect(find.text('1.46'), findsOneWidget, reason: '₹241 for 165');
    expect(find.text('In stock 12 → 72'), findsOneWidget);
    expect(find.text('New item'), findsNWidgets(2));

    // Leave the gel out.
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await _add(tester, 'Add 2 items');

    final dolo = repo.named('Dolo 650');
    expect(dolo.currentStock, 165);
    expect(dolo.unitPrice! * dolo.currentStock, closeTo(241, 1e-9));
    expect(dolo.expiryDate, DateTime(2028, 3, 31));
    expect(dolo.batchNumber, 'DL24A91');
    expect(dolo.supplierName, 'Shree Ganesh Pharma Distributors');

    // Every line is a purchase: batch, expiry, cost, supplier, bill.
    final pantocid = repo.moves.singleWhere((m) => m.medicineId != dolo.id);
    expect(pantocid.quantity, 60);
    expect(pantocid.batchNumber, 'PT77812');
    expect(pantocid.expiryDate, DateTime(2027, 9, 30));
    expect(pantocid.unitCost, closeTo(11.24, 1e-9));
    expect(pantocid.billKey, 'shreeganeshpharmadistributors#sgpd202604512');
    // Its older stock expires first: that's the batch to use first.
    expect(repo.named('Pantocid 40 mg').expiryDate, DateTime(2027, 1, 31));

    expect(outcome()?.added, 1);
    expect(outcome()?.restocked, 1);
  });

  testWidgets(
    "two bills from one supplier: the stock is worth both bills' totals",
    (tester) async {
      final repo = _Inventory();
      await _open(tester, repo, scan: (_) async => _bill7021);
      await _add(tester, 'Add 9 items');
      expect(
        repo.valueFrom('Health Corner Medical And General Store'),
        closeTo(7021.84, 0.005),
      );

      // The second bill: misread names are offered as the same item;
      // repeated lines join it; nothing is made twice.
      await _open(tester, repo, scan: (_) async => _bill4092);
      expect(find.text('Same as Gemer 1mg? 30 → 40'), findsOneWidget);
      expect(find.text('Same as Gemer 1mg? 40 → 50'), findsOneWidget);
      expect(find.text('Same as Kenia St 25? 45 → 75'), findsOneWidget);
      expect(find.text('Keep separate'), findsNWidgets(4));
      // Axcer: a box of 120 in stock, then strips of 14 line by line.
      expect(find.text('In stock 120 → 134'), findsOneWidget);
      expect(find.text('In stock 134 → 148'), findsOneWidget);
      expect(find.text('In stock 148 → 176'), findsOneWidget);
      await _add(tester, 'Add 13 items');

      final names = repo.items.map((m) => m.name).toList();
      expect(names.toSet().length, names.length, reason: 'no duplicates');
      expect(names, hasLength(9));
      final axcer = repo.named('Axcer 90');
      expect(axcer.unit, 'Tablets');
      expect(axcer.currentStock, 120 + 56);
      expect(
        repo.valueFrom('Health Corner Medical And General Store'),
        closeTo(7021.84 + 4092.75, 0.01),
        reason: 'both bills, to the paisa; GST already in their prices',
      );
    },
  );

  testWidgets('the same bill again: a warning, and nothing added', (
    tester,
  ) async {
    final repo = _Inventory();
    await _open(tester, repo, scan: (_) async => _bill7021);
    await _add(tester, 'Add 9 items');
    final moves = repo.moves.length;

    await _open(tester, repo, scan: (_) async => _bill7021);
    expect(find.text('This bill is already in your inventory'), findsOneWidget);
    expect(
      find.textContaining('Bill 165534 from Health Corner'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Add from bill'), findsNothing);
    expect(repo.moves, hasLength(moves));
  });

  testWidgets('the same bill again, on purpose: "Add it again"', (
    tester,
  ) async {
    final repo = _Inventory();
    await _open(tester, repo, scan: (_) async => _medicare);
    await _add(tester, 'Add 3 items');
    await _open(tester, repo, scan: (_) async => _medicare);
    await tester.tap(find.text('Add it again'));
    await tester.pumpAndSettle();
    await _add(tester, 'Add 3 items');
    expect(repo.named('Paracetamol 500 mg').currentStock, 20);
  });

  testWidgets('a syrup never joins tablets of the same name', (tester) async {
    final repo = _Inventory([_item('Crocin 500', stock: 30)]);
    await _open(
      tester,
      repo,
      scan: (_) async => const ScannedBill(
        source: 'sarvam',
        items: [
          BillLine(
            name: 'CROCIN 500 SYP',
            pack: '100ML',
            quantity: 2,
            rate: 60,
          ),
        ],
      ),
    );
    expect(find.text('New item'), findsOneWidget);
    await _add(tester, 'Add 1 item');
    expect(repo.items.map((m) => (m.name, m.unit, m.currentStock)), [
      ('Crocin 500', 'Tablets', 30),
      ('Crocin 500', 'Bottles', 2),
    ]);
  });

  testWidgets('a name a letter apart can be kept separate', (tester) async {
    final repo = _Inventory([_item('Gemer 1mg', stock: 30)]);
    await _open(
      tester,
      repo,
      scan: (_) async => const ScannedBill(
        source: 'sarvam',
        items: [
          BillLine(name: 'GENER 1MG', pack: '10T', quantity: 1, rate: 150),
        ],
      ),
    );
    expect(find.text('Same as Gemer 1mg? 30 → 40'), findsOneWidget);
    await tester.tap(find.text('Keep separate'));
    await tester.pumpAndSettle();
    expect(find.text('New item'), findsOneWidget);
    expect(find.text('Add to Gemer 1mg'), findsOneWidget);
    await _add(tester, 'Add 1 item');
    expect(repo.items.map((m) => m.name), ['Gemer 1mg', 'Gener 1mg']);
    expect(repo.named('Gemer 1mg').currentStock, 30);
  });

  testWidgets('an unclear pack can be corrected: stock and price follow', (
    tester,
  ) async {
    final repo = _Inventory();
    await _open(
      tester,
      repo,
      scan: (_) async => const ScannedBill(
        source: 'sarvam',
        items: [
          BillLine(name: 'ZINCOVIT TAB', pack: '10x10', quantity: 2, rate: 300),
        ],
      ),
    );
    // "10x10": a box of 10 strips, or the quantity counts strips?
    expect(find.text('Check this'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: '₹600 / 200');
    await tester.enterText(find.widgetWithText(TextField, '100'), '10');
    await tester.pumpAndSettle();
    expect(find.text('20'), findsOneWidget);
    expect(find.text('30'), findsOneWidget, reason: '₹600 / 20');
    await _add(tester, 'Add 1 item');
    expect(repo.named('Zincovit').currentStock, 20);
    expect(repo.named('Zincovit').unitPrice, 30);
  });

  testWidgets('GST can be left out of the cost, and that is remembered', (
    tester,
  ) async {
    final repo = _Inventory();
    await _open(tester, repo, scan: (_) async => _medicare);
    expect(find.text('40.32'), findsOneWidget, reason: '₹40 − 10% + 12%');
    expect(find.textContaining("₹2,469.60, the bill's total"), findsOneWidget);

    await tester.tap(find.text('Without GST'));
    await tester.pumpAndSettle();
    expect(find.text('36'), findsOneWidget, reason: '₹40 − 10%');
    expect(
      find.textContaining("₹2,205, the bill's taxable value"),
      findsOneWidget,
    );
    await _add(tester, 'Add 3 items');
    expect(repo.named('Paracetamol 500 mg').unitPrice, closeTo(36, 1e-9));
    expect(repo.valueFrom('MediCare Wholesale Pharmacy'), closeTo(2205, 1e-6));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('inventory.billCostIncludesGst'), isFalse);
  });

  testWidgets('saving after editing a field closes cleanly', (tester) async {
    // The fields are drawn again while the dialog animates away: their
    // controllers must still be alive then.
    final repo = _Inventory();
    final outcome = await _open(tester, repo);
    await tester.enterText(find.byType(TextField).first, 'Dolo 650 mg');
    await tester.pump();
    await tester.tap(find.text('Add 3 items'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add from bill'), findsNothing);
    expect(repo.items.first.name, 'Dolo 650 mg');
    expect(outcome()?.added, 3);
  });

  testWidgets('a price typed over is saved as typed', (tester) async {
    final repo = _Inventory();
    await _open(tester, repo);
    final priceField = find.byType(TextField).at(4); // Dolo's unit price
    expect(tester.widget<TextField>(priceField).controller!.text, '1.46');
    await tester.enterText(priceField, '1.5');
    await _add(tester, 'Add 3 items');
    expect(repo.named('Dolo 650').unitPrice, 1.5);
  });

  testWidgets('the lines are checked against the bill total', (tester) async {
    await _open(
      tester,
      _Inventory(),
      scan: (_) async => const ScannedBill(
        source: 'sarvam',
        grandTotal: 500,
        taxPercent: 12,
        items: [
          BillLine(name: 'DOLO 650 TAB', quantity: 2, rate: 100, amount: 200),
        ],
      ),
    );
    expect(
      find.textContaining(
        "These lines come to ₹224, but the bill's total is ₹500",
      ),
      findsOneWidget,
    );
  });

  testWidgets('a bill read offline says so', (tester) async {
    await _open(
      tester,
      _Inventory(),
      scan: (_) async => const ScannedBill(
        source: 'paddle',
        note: 'no internet connection to Sarvam',
        items: [BillLine(name: 'DOLO 650 TAB', quantity: 1)],
      ),
    );
    expect(
      find.textContaining('Read offline with PaddleOCR (no internet'),
      findsOneWidget,
    );
    expect(find.textContaining('Read by PaddleOCR'), findsOneWidget);
  });

  testWidgets('an unreadable bill offers the form instead', (tester) async {
    await _open(
      tester,
      _Inventory(),
      scan: (_) async => throw Exception('bad image'),
    );
    expect(find.text("Couldn't read this bill."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Add by hand'), findsOneWidget);
  });
}
