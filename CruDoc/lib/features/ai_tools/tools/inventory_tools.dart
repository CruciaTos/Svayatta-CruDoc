import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/ai_tools/core/ai_tool.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';

const _maxItems = 15;

String? _str(Map<String, Object?> a, String k) {
  final v = a[k];
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

num? _num(Map<String, Object?> a, String k) {
  final v = a[k];
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, Object?> _row(MedicineModel m) => {
  'itemId': m.id,
  'name': m.name,
  'category': m.category,
  'unit': m.unit,
  'stock': m.currentStock,
  'minQuantity': m.reorderThreshold,
  'lowStock': m.isLowStock,
  'expiry': m.expiryDate == null ? null : _day(m.expiryDate!),
  'price': m.unitPrice,
  if (m.unitPrice != null) 'currency': 'INR',
};

List<AiTool> inventoryTools() => [
  AiTool(
    name: 'find_stock_item',
    description:
        'Find inventory items by name or category (max 15). Use the itemId '
        'for record_stock_movement.',
    group: AiToolGroup.inventory,
    risk: AiToolRisk.read,
    permission: ClinicPermission.inventory,
    params: const {'query': AiParam.string('Part of the item name or category')},
    run: (ctx, args) async {
      final q = _str(args, 'query')?.toLowerCase();
      if (q == null) return AiToolResult.error('query is required.');
      final all = await ctx.read(medicinesStreamProvider.future);
      final hits = [
        for (final m in all)
          if (m.isActive &&
              (m.name.toLowerCase().contains(q) ||
                  m.category.toLowerCase().contains(q)))
            m,
      ];
      return AiToolResult.ok({
        'count': hits.length,
        'items': hits.take(_maxItems).map(_row).toList(),
      }, summary: '${hits.length} item(s) found');
    },
  ),
  AiTool(
    name: 'list_low_stock',
    description: 'Items at or below their reorder level, lowest first (max 15).',
    group: AiToolGroup.inventory,
    risk: AiToolRisk.read,
    permission: ClinicPermission.inventory,
    run: (ctx, args) async {
      await ctx.read(medicinesStreamProvider.future);
      final all =
          ctx.read(lowStockMedicinesProvider).value ?? const <MedicineModel>[];
      final list = [...all]..sort((a, b) => a.currentStock.compareTo(b.currentStock));
      return AiToolResult.ok({
        'count': list.length,
        'items': list.take(_maxItems).map(_row).toList(),
      }, summary: '${list.length} low on stock');
    },
  ),
  AiTool(
    name: 'list_expiring_stock',
    description:
        'Items expiring within a number of days (default 30), including '
        'already expired, soonest first (max 15).',
    group: AiToolGroup.inventory,
    risk: AiToolRisk.read,
    permission: ClinicPermission.inventory,
    params: const {
      'withinDays': AiParam.integer(
        'Days ahead (default 30)',
        required: false,
        min: 1,
        max: 365,
      ),
    },
    run: (ctx, args) async {
      final days = (_num(args, 'withinDays') ?? 30).round().clamp(1, 365);
      final all = await ctx.read(medicinesStreamProvider.future);
      final limit = DateTime.now().add(Duration(days: days));
      final list = [
        for (final m in all)
          if (m.isActive && m.expiryDate != null && !m.expiryDate!.isAfter(limit))
            m,
      ]..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
      return AiToolResult.ok({
        'withinDays': days,
        'count': list.length,
        'items': list.take(_maxItems).map(_row).toList(),
      }, summary: '${list.length} expiring within $days days');
    },
  ),
  AiTool(
    name: 'add_stock_item',
    description:
        'Add a new inventory item with its opening quantity. Check '
        'find_stock_item first to avoid duplicates; to change stock of an '
        'existing item use record_stock_movement.',
    group: AiToolGroup.inventory,
    risk: AiToolRisk.write,
    permission: ClinicPermission.inventory,
    params: const {
      'name': AiParam.string('Item name'),
      'unit': AiParam.string('Unit, e.g. box, strip, pcs, ml'),
      'quantity': AiParam.integer('Opening quantity', min: 0),
      'minQuantity': AiParam.integer(
        'Reorder level (default 10)',
        required: false,
        min: 0,
      ),
      'expiry': AiParam.date('Expiry date', required: false),
      'price': AiParam.number(
        'Price per unit in rupees',
        required: false,
        min: 0,
      ),
    },
    run: (ctx, args) async {
      final name = _str(args, 'name');
      final unit = _str(args, 'unit');
      final qty = _num(args, 'quantity')?.round();
      if (name == null || unit == null || qty == null || qty < 0) {
        return AiToolResult.error(
          'name, unit and a quantity of 0 or more are required.',
        );
      }
      final minQ = _num(args, 'minQuantity')?.round() ?? 10;
      if (minQ < 0) return AiToolResult.error('minQuantity cannot be negative.');
      DateTime? expiry;
      final expiryText = _str(args, 'expiry');
      if (expiryText != null) {
        expiry = DateTime.tryParse(expiryText);
        if (expiry == null) {
          return AiToolResult.error('expiry must be YYYY-MM-DD.');
        }
      }
      final price = _num(args, 'price')?.toDouble();
      if (price != null && price < 0) {
        return AiToolResult.error('price cannot be negative.');
      }
      final repo = ctx.read(inventoryRepositoryProvider);
      try {
        final now = DateTime.now();
        final id = await repo.createMedicine(
          MedicineModel(
            id: '',
            name: name,
            unit: unit,
            currentStock: qty,
            reorderThreshold: minQ,
            unitPrice: price,
            expiryDate: expiry,
            createdAt: now,
            updatedAt: now,
          ),
        );
        return AiToolResult.ok(
          {'itemId': id, 'name': name, 'unit': unit, 'stock': qty},
          summary: 'Added $name ($qty $unit)',
          undo: () => repo.deleteMedicine(id),
        );
      } catch (e) {
        return AiToolResult.error("Couldn't add the item: $e");
      }
    },
  ),
  AiTool(
    name: 'record_stock_movement',
    description:
        'Change an item\'s stock. in = received/restock (adds). out = used or '
        'dispensed (subtracts). adjust = correction or loss (subtracts the '
        'quantity). Quantity is always a positive number.',
    group: AiToolGroup.inventory,
    risk: AiToolRisk.write,
    permission: ClinicPermission.inventory,
    params: const {
      'itemId': AiParam.string('Item ID from find_stock_item'),
      'type': AiParam.enumOf(['in', 'out', 'adjust'], 'Kind of movement'),
      'quantity': AiParam.integer('Units, positive', min: 1),
      'note': AiParam.string('Reason or note', required: false),
    },
    run: (ctx, args) async {
      final id = _str(args, 'itemId');
      final type = _str(args, 'type');
      final qty = _num(args, 'quantity')?.round();
      if (id == null) return AiToolResult.error('itemId is required.');
      if (qty == null || qty <= 0) {
        return AiToolResult.error('quantity must be above zero.');
      }
      final (txType, opposite) = switch (type) {
        'in' => (StockTransactionType.restock, StockTransactionType.dispense),
        'out' => (StockTransactionType.dispense, StockTransactionType.restock),
        'adjust' => (
          StockTransactionType.adjustment,
          StockTransactionType.restock,
        ),
        _ => (null, null),
      };
      if (txType == null || opposite == null) {
        return AiToolResult.error('type must be in, out or adjust.');
      }
      final repo = ctx.read(inventoryRepositoryProvider);
      try {
        final med = await repo.getMedicine(id);
        if (med == null || !med.isActive) {
          return AiToolResult.error('No inventory item with id $id.');
        }
        final tx = await repo.recordTransaction(
          medicineId: id,
          type: txType,
          quantity: qty,
          note: _str(args, 'note'),
        );
        return AiToolResult.ok(
          {
            'itemId': id,
            'name': med.name,
            'type': type,
            'quantity': qty,
            'stockBefore': med.currentStock,
            'stockNow': tx.resultingStock,
          },
          summary: '${med.name}: ${med.currentStock} to ${tx.resultingStock} ${med.unit}',
          undo: () async {
            await repo.recordTransaction(
              medicineId: id,
              type: opposite,
              quantity: qty,
              note: 'Undo of AI stock change',
            );
          },
        );
      } catch (e) {
        return AiToolResult.error("Couldn't change the stock: $e");
      }
    },
  ),
  AiTool(
    name: 'list_stock_purchases',
    description:
        'Stock batches received from supplier bills, newest first (max 15).',
    group: AiToolGroup.inventory,
    risk: AiToolRisk.read,
    permission: ClinicPermission.inventory,
    params: const {
      'limit': AiParam.integer(
        'How many (default 10, max 15)',
        required: false,
        min: 1,
        max: 15,
      ),
    },
    run: (ctx, args) async {
      final n = (_num(args, 'limit') ?? 10).round().clamp(1, _maxItems);
      final meds = await ctx.read(medicinesStreamProvider.future);
      final names = {for (final m in meds) m.id: m.name};
      final all = await ctx.read(stockPurchasesProvider.future);
      final list = [...all]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return AiToolResult.ok({
        'count': list.length,
        'purchases': [
          for (final p in list.take(n))
            {
              'date': _day(p.createdAt),
              'itemId': p.medicineId,
              'item': names[p.medicineId],
              'quantity': p.quantity,
              'unitCost': p.unitCost,
              if (p.unitCost != null) 'currency': 'INR',
              'supplier': p.supplierName,
              'batch': p.batchNumber,
              'expiry': p.expiryDate == null ? null : _day(p.expiryDate!),
            },
        ],
      });
    },
  ),
];
