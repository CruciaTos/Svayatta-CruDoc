import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';

const Color _accentTeal = Color(0xFF0D9488);

/// Dental Clinic Consumable Inventory Screen.
///
/// Extends the core CruDoc inventory system to manage dental-specific consumables
/// such as composites, anesthetic cartridges, burs, disposables, and sterilization supplies.
class DentalInventoryScreen extends ConsumerStatefulWidget {
  const DentalInventoryScreen({super.key});

  @override
  ConsumerState<DentalInventoryScreen> createState() => _DentalInventoryScreenState();
}

class _DentalInventoryScreenState extends ConsumerState<DentalInventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _dentalOnly = true;

  static const List<String> _dentalCategories = [
    'Dental Consumable',
    'Dental Restorative',
    'Dental Anesthetic',
    'Dental Endodontic',
    'Dental Surgical',
    'Consumable',
  ];

  static const List<String> _dentalUnits = [
    'Cartridges',
    'Burs',
    'Pouches',
    'Syringes',
    'Bottles',
    'Pcs',
    'Vials',
    'Strips',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAddConsumableDialog() async {
    final nameController = TextEditingController();
    final stockController = TextEditingController(text: '10');
    final thresholdController = TextEditingController(text: '5');
    final priceController = TextEditingController();
    String category = 'Dental Consumable';
    String unit = 'Cartridges';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Dental Consumable'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Consumable Name *',
                        hintText: 'e.g. Lidocaine 2% Cartridge, Composite A2',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: _dentalCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => category = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: unit,
                      decoration: const InputDecoration(labelText: 'Packaging Unit'),
                      items: _dentalUnits
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => unit = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: stockController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Initial Stock *'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: thresholdController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Low Alert Limit'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Unit Cost (₹) (Optional)',
                        hintText: 'e.g. 150',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accentTeal),
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Name is required')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      final now = DateTime.now();
      final stock = int.tryParse(stockController.text.trim()) ?? 0;
      final threshold = int.tryParse(thresholdController.text.trim()) ?? 5;
      final price = double.tryParse(priceController.text.trim());

      final med = MedicineModel(
        id: const Uuid().v4(),
        name: nameController.text.trim(),
        category: category,
        unit: unit,
        currentStock: stock,
        reorderThreshold: threshold,
        unitPrice: price,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      await ref.read(inventoryRepositoryProvider).createMedicine(med);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${med.name} added to dental inventory'),
            backgroundColor: _accentTeal,
          ),
        );
      }
    }
  }

  Future<void> _adjustStock(MedicineModel med, int delta) async {
    final newStock = med.currentStock + delta;
    if (newStock < 0) return;

    final repo = ref.read(inventoryRepositoryProvider);
    await repo.recordTransaction(
      medicineId: med.id,
      type: delta >= 0 ? StockTransactionType.restock : StockTransactionType.dispense,
      quantity: delta.abs(),
      note: delta >= 0 ? 'Manual restock' : 'Chairside procedure usage',
    );
  }

  Future<void> _showCustomAdjustmentDialog(MedicineModel med) async {
    final qtyController = TextEditingController(text: '1');
    final noteController = TextEditingController();
    bool isRestock = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Text('Adjust ${med.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Restock (+)'),
                        selected: isRestock,
                        selectedColor: const Color(0xFFDCFCE7),
                        onSelected: (val) {
                          if (val) setDlgState(() => isRestock = true);
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Deduct / Use (-)'),
                        selected: !isRestock,
                        selectedColor: const Color(0xFFFEE2E2),
                        onSelected: (val) {
                          if (val) setDlgState(() => isRestock = false);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quantity (${med.unit}) *',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Reason / Audit Note',
                      hintText: 'e.g. Received shipment, expired batch, physical count correction',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accentTeal),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Record Movement'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      final qty = int.tryParse(qtyController.text.trim()) ?? 0;
      if (qty <= 0) return;

      final repo = ref.read(inventoryRepositoryProvider);
      await repo.recordTransaction(
        medicineId: med.id,
        type: isRestock ? StockTransactionType.restock : StockTransactionType.dispense,
        quantity: qty,
        note: noteController.text.trim().isNotEmpty
            ? noteController.text.trim()
            : (isRestock ? 'Manual stock addition' : 'Manual stock deduction'),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stock updated for ${med.name}'),
            backgroundColor: _accentTeal,
          ),
        );
      }
    }
  }

  Future<void> _showItemDetailsDialog(MedicineModel med) async {
    final repo = ref.read(inventoryRepositoryProvider);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              med.name,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${med.category} • ${med.unit}',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Content
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Status card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text('Current Stock', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                const SizedBox(height: 4),
                                Text(
                                  '${med.currentStock} ${med.unit}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: med.isLowStock ? Colors.red : const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
                            Column(
                              children: [
                                const Text('Min. Reorder', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                const SizedBox(height: 4),
                                Text(
                                  '${med.reorderThreshold} ${med.unit}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            if (med.unitPrice != null) ...[
                              Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
                              Column(
                                children: [
                                  const Text('Unit Cost', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₹${med.unitPrice!.toStringAsFixed(0)}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Action button
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _accentTeal,
                          side: const BorderSide(color: _accentTeal),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Adjust Stock with Audit Note'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showCustomAdjustmentDialog(med);
                        },
                      ),

                      const SizedBox(height: 20),

                      // Transaction history
                      const Text(
                        'Audit Trail & Stock History',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 8),

                      FutureBuilder<List<StockTransactionModel>>(
                        future: repo.getTransactionsForMedicine(med.id),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final txs = snapshot.data ?? [];
                          if (txs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No stock movements recorded yet.',
                                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                              ),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: txs.length,
                            separatorBuilder: (context, i) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final tx = txs[i];
                              final isIncrease = tx.type == StockTransactionType.restock;
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  isIncrease ? Icons.arrow_downward : Icons.arrow_upward,
                                  color: isIncrease ? Colors.green : Colors.red,
                                  size: 18,
                                ),
                                title: Text(
                                  tx.note ?? tx.type.name.toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                subtitle: Text(
                                  DateFormat('dd MMM yyyy, hh:mm a').format(tx.createdAt),
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                                trailing: Text(
                                  '${isIncrease ? '+' : '-'}${tx.quantity} (${tx.resultingStock} left)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: isIncrease ? Colors.green : Colors.red,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<MedicineModel> _filterList(List<MedicineModel> list) {
    return list.where((item) {
      if (!item.isActive) return false;
      if (_dentalOnly) {
        final cat = item.category.toLowerCase();
        final isDental = cat.contains('dental') ||
            cat == 'consumable' ||
            cat == 'restorative' ||
            cat == 'anesthetic';
        if (!isDental) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final nameMatches = item.name.toLowerCase().contains(_searchQuery);
        final catMatches = item.category.toLowerCase().contains(_searchQuery);
        return nameMatches || catMatches;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryAsync = ref.watch(medicinesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dental Consumables & Stock'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _dentalOnly ? 'Show All Clinic Stock' : 'Show Dental Only',
            icon: Icon(
              _dentalOnly ? Icons.filter_alt : Icons.filter_alt_off,
              color: _accentTeal,
            ),
            onPressed: () => setState(() => _dentalOnly = !_dentalOnly),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accentTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Consumable'),
        onPressed: _openAddConsumableDialog,
      ),
      body: Column(
        children: [
          // Search & Filters
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search consumable or batch...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.trim().toLowerCase());
              },
            ),
          ),

          const Divider(height: 1),

          // Inventory List
          Expanded(
            child: inventoryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading inventory: $err')),
              data: (allItems) {
                final items = _filterList(allItems);
                final lowStockCount = items.where((i) => i.isLowStock).length;

                return Column(
                  children: [
                    // Summary header bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: const Color(0xFFF8FAFC),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${items.length} items (${_dentalOnly ? 'Dental' : 'All'})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                          if (lowStockCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$lowStockCount Low Stock',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    if (items.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF94A3B8)),
                              const SizedBox(height: 12),
                              const Text(
                                'No dental consumables found',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Add composite, anesthetic, burs, or sterilization pouches.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: _accentTeal),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Consumable'),
                                onPressed: _openAddConsumableDialog,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 80, top: 4),
                          itemCount: items.length,
                          separatorBuilder: (context, sepIndex) => const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (context, idx) {
                            final item = items[idx];
                            return ListTile(
                              onTap: () => _showItemDetailsDialog(item),
                              title: Text(
                                item.name,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    '${item.category} • ${item.unit}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                  if (item.isLowStock) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                                  ],
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${item.currentStock} ${item.unit}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: item.isLowStock ? Colors.red : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        'Min: ${item.reorderThreshold}',
                                        style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                                    color: Colors.redAccent,
                                    tooltip: 'Dispense 1',
                                    onPressed: () => _adjustStock(item, -1),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 20),
                                    color: _accentTeal,
                                    tooltip: 'Restock 1',
                                    onPressed: () => _adjustStock(item, 1),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
