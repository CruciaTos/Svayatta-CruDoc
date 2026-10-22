import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';

/// Some of an item's stock that came in together: one batch from one
/// supplier's bill, with its expiry and what each unit cost.
class StockBatch {
  const StockBatch({
    required this.quantity,
    this.batch,
    this.expiry,
    this.unitCost,
    this.supplier,
  });

  final int quantity;
  final String? batch;
  final DateTime? expiry;
  final double? unitCost;
  final String? supplier;

  /// What these units cost; null when the cost isn't known.
  double? get value => unitCost == null ? null : unitCost! * quantity;
}

/// The batches of [item] still in stock, the one to use first first.
///
/// Every purchase (restock from a bill) brought a batch. Stock used up
/// isn't tied to a batch, so the earliest-expiring batches are taken to
/// go first (as they should): the [item]'s current stock is the latest-
/// expiring units bought. Stock with no purchase behind it (entered by
/// hand) is one batch from the item's own batch, expiry, cost and
/// supplier.
List<StockBatch> remainingBatches(
  MedicineModel item,
  Iterable<StockTransactionModel> purchases,
) {
  final mine =
      purchases.where((p) => p.medicineId == item.id && p.isPurchase).toList()
        ..sort((a, b) {
          final byExpiry = _byExpiry(a.expiryDate, b.expiryDate);
          return byExpiry != 0 ? byExpiry : a.createdAt.compareTo(b.createdAt);
        });
  var left = item.currentStock;
  final kept = <StockBatch>[];
  // Last to be used are kept: walk from the latest expiry back.
  for (final p in mine.reversed) {
    if (left <= 0) break;
    final quantity = p.quantity < left ? p.quantity : left;
    kept.add(
      StockBatch(
        quantity: quantity,
        batch: p.batchNumber,
        expiry: p.expiryDate,
        unitCost: p.unitCost,
        supplier: p.supplierName,
      ),
    );
    left -= quantity;
  }
  // Stock older than any purchase on record (entered by hand): the
  // item's own batch, expiry, cost and supplier.
  if (left > 0) {
    kept.add(
      StockBatch(
        quantity: left,
        batch: item.batchNumber,
        expiry: item.expiryDate,
        unitCost: item.unitPrice,
        supplier: item.supplierName,
      ),
    );
  }
  return kept..sort((a, b) => _byExpiry(a.expiry, b.expiry));
}

/// Earliest expiry first; no expiry last.
int _byExpiry(DateTime? x, DateTime? y) {
  if (x == y) return 0;
  if (x == null) return 1;
  if (y == null) return -1;
  return x.compareTo(y);
}

/// What [batches] are worth together, and so what one unit costs on
/// average; null when no batch has a cost.
double? averageCost(List<StockBatch> batches) {
  final priced = batches.where((b) => b.unitCost != null);
  final units = priced.fold(0, (s, b) => s + b.quantity);
  if (units == 0) return null;
  return priced.fold(0.0, (s, b) => s + b.value!) / units;
}

/// One supplier's share of the stock: what it's worth and which items.
class SupplierStock {
  SupplierStock(this.name);

  final String name;
  double value = 0;
  bool hasValue = false;
  final itemIds = <String>{};
}

/// The stock held from each supplier, from every item's remaining
/// batches: an item bought from two suppliers counts under both, each
/// for its own batches. Stock with no supplier is under ''.
Map<String, SupplierStock> stockBySupplier(
  Iterable<MedicineModel> items,
  Iterable<StockTransactionModel> purchases,
) {
  final byItem = <String, List<StockTransactionModel>>{};
  for (final p in purchases) {
    byItem.putIfAbsent(p.medicineId, () => []).add(p);
  }
  final out = <String, SupplierStock>{};
  for (final item in items) {
    final batches = remainingBatches(item, byItem[item.id] ?? const []);
    if (batches.isEmpty) {
      // Out of stock: still listed under its supplier, to reorder from.
      final name = item.supplierName?.trim() ?? '';
      out.putIfAbsent(name, () => SupplierStock(name)).itemIds.add(item.id);
      continue;
    }
    for (final batch in batches) {
      final name = batch.supplier?.trim() ?? '';
      final s = out.putIfAbsent(name, () => SupplierStock(name));
      s.itemIds.add(item.id);
      if (batch.value != null) {
        s.value += batch.value!;
        s.hasValue = true;
      }
    }
  }
  return out;
}
