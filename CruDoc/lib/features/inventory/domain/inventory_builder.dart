import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';

/// Pure derivations for the Inventory screen. No I/O.
abstract final class InventoryBuilder {
  /// Daily use looks back this many calendar days (closed days are a
  /// GAP, so every day counts).
  static const int usageWindowDays = 14;

  /// "Expiring soon".
  static const int expiringWithinDays = 60;

  /// The run-out strip: items that run out within this many days.
  static const int runOutWithinDays = 7;

  /// Rows revealed per page (load more on scroll).
  static const int pageSize = 30;

  static DateTime _day(DateTime t) => DateTime.utc(t.year, t.month, t.day);

  /// One item from its medicine and its movements (any order).
  static InventoryItem item(
    MedicineModel m,
    List<StockTransactionModel> movements,
    DateTime now,
  ) {
    final today = _day(now);
    final usage = List<int>.filled(usageWindowDays, 0);
    final restocks = <int>[];
    for (final t in movements) {
      if (t.type == StockTransactionType.restock && t.quantity > 0) {
        restocks.add(t.quantity);
      } else if (t.type == StockTransactionType.dispense) {
        final ago = today.difference(_day(t.createdAt.toLocal())).inDays;
        if (ago >= 0 && ago < usageWindowDays) {
          usage[usageWindowDays - 1 - ago] += t.quantity.abs();
        }
      }
    }
    final total = usage.fold<int>(0, (a, b) => a + b);
    final dailyUse = total > 0 ? total / usageWindowDays : null;
    final stock = m.currentStock < 0 ? 0 : m.currentStock;
    final daysLeft = dailyUse == null ? null : stock / dailyUse;

    final expiry = m.expiryDate;
    final daysToExpiry =
        expiry == null ? null : _day(expiry.toLocal()).difference(today).inDays;
    final expiringSoon =
        daysToExpiry != null && daysToExpiry <= expiringWithinDays;
    final expiresFirst = daysToExpiry != null &&
        (daysLeft == null ? expiringSoon : daysToExpiry < daysLeft);

    return InventoryItem(
      medicine: m,
      low: m.currentStock <= m.reorderThreshold,
      expiringSoon: expiringSoon,
      expiresFirst: expiresFirst,
      daysToExpiry: daysToExpiry,
      dailyUse: dailyUse,
      daysLeft: daysLeft,
      usualOrder: median(restocks),
      usage: usage,
      usageDays: [
        for (var i = usageWindowDays - 1; i >= 0; i--)
          DateTime(now.year, now.month, now.day - i),
      ],
    );
  }

  /// Median of [values] (rounded); null when empty.
  static int? median(List<int> values) {
    if (values.isEmpty) return null;
    final s = [...values]..sort();
    final mid = s.length ~/ 2;
    if (s.length.isOdd) return s[mid];
    return ((s[mid - 1] + s[mid]) / 2).round();
  }

  static bool matches(InventoryItem i, InventoryFilter f) => switch (f.kind) {
        InventoryFilterKind.all => true,
        InventoryFilterKind.low => i.low,
        InventoryFilterKind.expiring => i.expiringSoon,
        InventoryFilterKind.category =>
          (i.category ?? '').toLowerCase() == (f.category ?? '').toLowerCase(),
      };

  /// Search over name, batch and supplier.
  static bool matchesQuery(InventoryItem i, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return i.name.toLowerCase().contains(q) ||
        (i.batch ?? '').toLowerCase().contains(q) ||
        (i.supplier ?? '').toLowerCase().contains(q);
  }

  /// All, Low stock, Expiring soon, then one chip per category (most
  /// items first).
  static List<InventoryChip> chips(List<InventoryItem> items) {
    final categories = <String, int>{};
    final spelling = <String, String>{};
    for (final i in items) {
      final c = i.category;
      if (c == null) continue;
      final key = c.toLowerCase();
      spelling.putIfAbsent(key, () => c);
      categories[key] = (categories[key] ?? 0) + 1;
    }
    final keys = categories.keys.toList()
      ..sort((a, b) {
        final byCount = categories[b]!.compareTo(categories[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return [
      InventoryChip(InventoryFilter.all, items.length),
      InventoryChip(InventoryFilter.low, items.where((i) => i.low).length),
      InventoryChip(
        InventoryFilter.expiring,
        items.where((i) => i.expiringSoon).length,
      ),
      for (final k in keys)
        InventoryChip(InventoryFilter.category(spelling[k]!), categories[k]!),
    ];
  }

  static int _byName(InventoryItem a, InventoryItem b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  static List<InventoryItem> sorted(
    List<InventoryItem> items,
    InventorySort sort,
  ) {
    final list = [...items];
    switch (sort) {
      case InventorySort.name:
        list.sort(_byName);
      case InventorySort.runsOut:
        list.sort((a, b) {
          final da = a.daysLeft ?? double.infinity;
          final db = b.daysLeft ?? double.infinity;
          final c = da.compareTo(db);
          if (c != 0) return c;
          if (a.low != b.low) return a.low ? -1 : 1;
          return _byName(a, b);
        });
      case InventorySort.stock:
        list.sort((a, b) {
          if (a.low != b.low) return a.low ? -1 : 1;
          final c = a.stock.compareTo(b.stock);
          return c != 0 ? c : _byName(a, b);
        });
      case InventorySort.expiry:
        list.sort((a, b) {
          final ea = a.daysToExpiry;
          final eb = b.daysToExpiry;
          if (ea == null && eb == null) return _byName(a, b);
          if (ea == null) return 1;
          if (eb == null) return -1;
          final c = ea.compareTo(eb);
          return c != 0 ? c : _byName(a, b);
        });
    }
    return list;
  }

  /// Items that run out within a week, soonest first; null when none.
  static RunOutStrip? runOut(List<InventoryItem> items) {
    final soon = sorted(
      items.where((i) => i.runsOutThisWeek).toList(),
      InventorySort.runsOut,
    );
    if (soon.isEmpty) return null;
    final suppliers = {
      for (final i in soon)
        if (i.supplier != null) i.supplier!.toLowerCase(),
    };
    return RunOutStrip(items: soon, supplierCount: suppliers.length);
  }

  static InventoryView view({
    required List<MedicineModel> medicines,
    required Map<String, List<StockTransactionModel>> history,
    required DateTime now,
    required InventoryFilter filter,
    required InventorySort sort,
    required String query,
    required String? selectedId,
    required int limit,
  }) {
    final all = [
      for (final m in medicines)
        if (m.isActive) item(m, history[m.id] ?? const [], now),
    ];
    final hasUsage = all.any((i) => i.dailyUse != null);
    final chips = InventoryBuilder.chips(all);

    var applied = filter;
    if (applied != InventoryFilter.all) {
      final count = chips
          .where((c) => c.filter == applied)
          .fold<int>(0, (a, c) => a + c.count);
      if (count == 0) applied = InventoryFilter.all;
    }
    final appliedSort =
        !hasUsage && sort == InventorySort.runsOut ? InventorySort.stock : sort;

    final rows = sorted(
      all
          .where((i) => matches(i, applied) && matchesQuery(i, query))
          .toList(),
      appliedSort,
    );
    final visible = rows.take(limit < pageSize ? pageSize : limit).toList();

    InventoryItem? chosen;
    if (selectedId != null) {
      for (final r in rows) {
        if (r.id == selectedId) {
          chosen = r;
          break;
        }
      }
    }

    var value = 0.0;
    var hasPrices = false;
    for (final i in all) {
      final price = i.medicine.unitPrice;
      if (price == null) continue;
      hasPrices = true;
      if (i.stock > 0) value += i.stock * price;
    }

    return InventoryView(
      all: all,
      rows: rows,
      visible: visible,
      selected: chosen ?? (rows.isEmpty ? null : rows.first),
      selectedExplicit: chosen != null,
      chips: chips,
      filter: applied,
      sort: appliedSort,
      hasUsage: hasUsage,
      hasUsualOrders: all.any((i) => i.usualOrder != null),
      runOut: runOut(all),
      stockValue: value,
      hasPrices: hasPrices,
      now: now,
    );
  }
}
