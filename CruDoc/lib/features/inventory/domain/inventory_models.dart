import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';

/// The Inventory sections (only the ones that exist in the app).
enum InventoryTab {
  items('Items'),
  orders('Orders'),
  vendors('Vendors'),
  usage('Usage');

  const InventoryTab(this.label);
  final String label;
}

/// List rows or compact grid tiles. Remembered per device.
enum InventoryViewMode {
  list,
  grid;

  static InventoryViewMode fromName(String? name) => InventoryViewMode.values
      .firstWhere((m) => m.name == name, orElse: () => InventoryViewMode.list);
}

enum InventorySort {
  runsOut('Runs out soonest'),
  name('Name'),
  stock('Stock level'),
  expiry('Expiry');

  const InventorySort(this.label);
  final String label;
}

enum InventoryFilterKind { all, low, expiring, category }

/// One chip: All, Low stock, Expiring soon, or a category.
@immutable
class InventoryFilter {
  const InventoryFilter._(this.kind, [this.category]);

  const InventoryFilter.category(String name)
      : this._(InventoryFilterKind.category, name);

  static const all = InventoryFilter._(InventoryFilterKind.all);
  static const low = InventoryFilter._(InventoryFilterKind.low);
  static const expiring = InventoryFilter._(InventoryFilterKind.expiring);

  final InventoryFilterKind kind;

  /// Set only for [InventoryFilterKind.category].
  final String? category;

  String get label => switch (kind) {
        InventoryFilterKind.all => 'All',
        InventoryFilterKind.low => 'Low stock',
        InventoryFilterKind.expiring => 'Expiring soon',
        InventoryFilterKind.category => category ?? '',
      };

  /// Low stock and Expiring soon carry an amber dot.
  bool get attention =>
      kind == InventoryFilterKind.low || kind == InventoryFilterKind.expiring;

  @override
  bool operator ==(Object other) =>
      other is InventoryFilter &&
      other.kind == kind &&
      other.category == category;

  @override
  int get hashCode => Object.hash(kind, category);
}

/// A chip and how many items it holds.
@immutable
class InventoryChip {
  const InventoryChip(this.filter, this.count);

  final InventoryFilter filter;
  final int count;
}

/// How well stocked an item is, from the reorder ("alert") level and the
/// good level:
/// good at or above the good level, okay between the two, low at or
/// below the reorder level, critical at or below a fifth of it.
enum StockState { critical, low, okay, good }

/// Share of the reorder level at or below which stock is critical.
const double kCriticalStockShare = 0.2;

/// One active item with everything the list, grid and panel show,
/// derived from the medicine and its stock movements.
@immutable
class InventoryItem {
  const InventoryItem({
    required this.medicine,
    required this.low,
    required this.expiringSoon,
    required this.expiresFirst,
    required this.daysToExpiry,
    required this.dailyUse,
    required this.daysLeft,
    required this.usualOrder,
    required this.usage,
    required this.usageDays,
  });

  final MedicineModel medicine;

  /// Stock at or below the reorder level.
  final bool low;

  /// Expires within 60 days (or has expired).
  final bool expiringSoon;

  /// Expires before the stock runs out (or, with no usage, is expiring
  /// soon).
  final bool expiresFirst;

  /// Calendar days until [MedicineModel.expiryDate]; null with no date.
  final int? daysToExpiry;

  /// Average `dispense` quantity a day over the last 14 calendar days;
  /// null when nothing was dispensed in that window.
  final double? dailyUse;

  /// Stock ÷ daily use; null without usage.
  final double? daysLeft;

  /// Median `restock` quantity; null when the item was never restocked.
  final int? usualOrder;

  /// Dispensed quantity per day, oldest first; the last entry is today.
  final List<int> usage;

  /// The day of each [usage] entry.
  final List<DateTime> usageDays;

  String get id => medicine.id;
  String get name => medicine.name;
  String get unit => medicine.unit;
  int get stock => medicine.currentStock;
  int get reorderLevel => medicine.reorderThreshold;

  /// "Good in stock" level (set on the item, else twice the reorder level).
  int get goodLevel => medicine.goodLevel;

  StockState get stockState {
    if (stock <= reorderLevel * kCriticalStockShare) return StockState.critical;
    if (low) return StockState.low;
    if (stock < goodLevel) return StockState.okay;
    return StockState.good;
  }

  int get usageTotal => usage.fold(0, (a, b) => a + b);

  bool get outOfStock => stock <= 0;

  /// Runs out within the next 7 days.
  bool get runsOutThisWeek => daysLeft != null && daysLeft! <= 7;

  /// What a full vial means: the usual order, or the good level when that
  /// is higher or the item has never been restocked (so a new item still
  /// shows its colour). Null only when neither is known.
  int? get _scale {
    final scale = math.max(usualOrder ?? 0, goodLevel);
    return scale <= 0 ? null : scale;
  }

  /// Stock against [_scale] (vial fill, level bar), 0–1.
  double? get level {
    final s = _scale;
    if (s == null) return null;
    return (stock / s).clamp(0.0, 1.0);
  }

  /// The reorder level against [_scale] (vial notch), 0–1.
  double? get notch {
    final s = _scale;
    if (s == null) return null;
    return (reorderLevel / s).clamp(0.0, 1.0);
  }

  /// Cost of one usual order; null without a price or a usual order.
  double? get orderCost {
    final u = usualOrder;
    final price = medicine.unitPrice;
    if (u == null || price == null) return null;
    return u * price;
  }

  String? get supplier {
    final s = medicine.supplierName?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  String? get batch {
    final b = medicine.batchNumber?.trim();
    return b == null || b.isEmpty ? null : b;
  }

  String? get category {
    final c = medicine.category.trim();
    return c.isEmpty ? null : c;
  }
}

/// "3 items will run out this week".
@immutable
class RunOutStrip {
  const RunOutStrip({required this.items, required this.supplierCount});

  final List<InventoryItem> items;

  /// Distinct suppliers among [items] (one order per supplier).
  final int supplierCount;
}

/// Everything the Items section shows.
@immutable
class InventoryView {
  const InventoryView({
    required this.all,
    required this.rows,
    required this.visible,
    required this.selected,
    required this.selectedExplicit,
    required this.chips,
    required this.filter,
    required this.sort,
    required this.hasUsage,
    required this.hasUsualOrders,
    required this.runOut,
    required this.stockValue,
    required this.hasPrices,
    required this.now,
  });

  /// Every active item.
  final List<InventoryItem> all;

  /// Filtered, searched and sorted.
  final List<InventoryItem> rows;

  /// The first page of [rows] (load more on scroll).
  final List<InventoryItem> visible;

  /// The panel's item: the chosen one, or the first in the current sort.
  final InventoryItem? selected;

  /// The doctor picked [selected] (opens the sheet below 1200 px).
  final bool selectedExplicit;

  final List<InventoryChip> chips;

  /// The filter actually applied (a stale chip falls back to All).
  final InventoryFilter filter;

  /// The sort actually applied (no usage anywhere → Stock level).
  final InventorySort sort;

  /// Any item has dispensing in the last 14 days. Without it the Lasts
  /// column and "days left" are hidden.
  final bool hasUsage;

  /// Any item has a usual order (the grid's vial legend).
  final bool hasUsualOrders;

  final RunOutStrip? runOut;

  /// Σ stock × price over items with a price.
  final double stockValue;
  final bool hasPrices;

  final DateTime now;
}
