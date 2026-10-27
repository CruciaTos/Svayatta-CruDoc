import 'package:flutter/material.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/domain/stock_batches.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_add_edit_medicine_dialog.dart';
import 'package:doctor_management_app/features/inventory/presentation/medicine_detail_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/stock_adjustment_dialog.dart';

/// "₹2,450", or "₹7,021.84" with paise: never rounded to the rupee.
String _formatCurrency(double value) => InventoryFormat.rupees(value);

/// One medicine as the Orders, Vendors and Usage tabs list it.
class MedicationData {
  final String name;
  final String subtitle;
  final String status;
  final String dose;
  final String daysLeft;
  final double progress;
  final MedicineModel? originalMedicine;

  const MedicationData({
    required this.name,
    required this.subtitle,
    required this.status,
    required this.dose,
    required this.daysLeft,
    required this.progress,
    this.originalMedicine,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MedicationData &&
            other.name == name &&
            other.subtitle == subtitle &&
            other.status == status &&
            other.dose == dose &&
            other.daysLeft == daysLeft &&
            other.progress == progress &&
            other.originalMedicine?.id == originalMedicine?.id;
  }

  @override
  int get hashCode => Object.hash(
    name,
    subtitle,
    status,
    dose,
    daysLeft,
    progress,
    originalMedicine?.id,
  );
}

List<MedicationData> _medicationsFrom(List<MedicineModel> medicines) {
  final now = DateTime.now();
  return List.unmodifiable([
    for (final medicine in medicines)
      () {
        final threshold = medicine.reorderThreshold;
        final expiryDays = medicine.expiryDate?.difference(now).inDays;
        return MedicationData(
          name: medicine.name,
          subtitle: medicine.category.isNotEmpty && medicine.unit.isNotEmpty
              ? '${medicine.category} · ${medicine.unit}'
              : '',
          status: medicine.isExpiringSoon ? 'Expiring' : 'Active',
          dose: '${medicine.currentStock} ${medicine.unit}',
          daysLeft: medicine.expiryDate != null
              ? '${expiryDays ?? 0} days left'
              : '—',
          progress: threshold > 0
              ? (medicine.currentStock / threshold).clamp(0.0, 1.0)
              : 0.0,
          originalMedicine: medicine,
        );
      }(),
  ]);
}

class _NewStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtext;

  const _NewStatCard({
    required this.title,
    required this.value,
    required this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cru.surface,
        borderRadius: BorderRadius.circular(CruRadius.card),
        border: Border.all(color: context.cru.label3),
        boxShadow: const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: CruType.subhead.w500.tint(context.cru.label2)),
          const SizedBox(height: 8),
          Text(value, style: CruType.title.w700.tint(context.cru.label)),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Text(
                  subtext,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.caption.tint(context.cru.label2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// 2. ITEMS TAB
// ==============================================================================

class _StripedProgressBar extends StatelessWidget {
  final double value;
  final Color color;

  const _StripedProgressBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            Container(
              color: context.cru.label3,
              child: CustomPaint(painter: _StripePainter()),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;

    for (double x = -size.height; x < size.width + size.height; x += 6) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==============================================================================
// 5. VENDORS TAB (Over-Engineered)
// ==============================================================================

class _VendorSummary {
  final String name;
  final int itemCount;
  final int lowStockCount;
  final int expiringCount;
  final double stockValue;
  final bool hasKnownValue;
  final List<MedicationData> medications;

  const _VendorSummary({
    required this.name,
    required this.itemCount,
    required this.lowStockCount,
    required this.expiringCount,
    required this.stockValue,
    required this.hasKnownValue,
    required this.medications,
  });
}

/// Each supplier's stock, from the batches in stock: an item bought from
/// two suppliers is under both, each for what's left of its own batches
/// (see [stockBySupplier]). Items never bought from a bill count under
/// their supplier field.
List<_VendorSummary> _buildVendorSummaries(
  List<MedicationData> medications, [
  List<StockTransactionModel> purchases = const [],
]) {
  final byId = <String, MedicationData>{
    for (final med in medications)
      if (med.originalMedicine != null) med.originalMedicine!.id: med,
  };
  final stock = stockBySupplier([
    for (final med in byId.values) med.originalMedicine!,
  ], purchases);
  final unassigned = [
    for (final med in medications)
      if (med.originalMedicine == null) med,
  ];

  final summaries = <_VendorSummary>[];
  for (final s in stock.values) {
    final meds = [for (final id in s.itemIds) ?byId[id]];
    if (s.name.isEmpty) meds.addAll(unassigned);
    int lowStock = 0;
    int expiring = 0;
    for (final med in meds) {
      final original = med.originalMedicine;
      if (original == null) continue;
      if (original.isLowStock) lowStock += 1;
      if (original.isExpiringSoon) expiring += 1;
    }
    summaries.add(
      _VendorSummary(
        name: s.name.isEmpty ? 'Unassigned' : s.name,
        itemCount: meds.length,
        lowStockCount: lowStock,
        expiringCount: expiring,
        stockValue: s.value,
        hasKnownValue: s.hasValue,
        medications: meds,
      ),
    );
  }
  if (unassigned.isNotEmpty && !stock.containsKey('')) {
    summaries.add(
      _VendorSummary(
        name: 'Unassigned',
        itemCount: unassigned.length,
        lowStockCount: 0,
        expiringCount: 0,
        stockValue: 0,
        hasKnownValue: false,
        medications: unassigned,
      ),
    );
  }

  summaries.sort((a, b) {
    if (a.name == 'Unassigned') return 1;
    if (b.name == 'Unassigned') return -1;
    return b.stockValue.compareTo(a.stockValue);
  });

  return summaries;
}

class _VendorsTab extends StatefulWidget {
  final List<MedicationData> medications;

  /// The batches bought from bills, so each supplier counts its own.
  final List<StockTransactionModel> purchases;
  final ValueChanged<MedicineModel> onEditMedicine;
  final ValueChanged<MedicineModel> onOpenMedicineDetail;

  const _VendorsTab({
    required this.medications,
    this.purchases = const [],
    required this.onEditMedicine,
    required this.onOpenMedicineDetail,
  });

  @override
  State<_VendorsTab> createState() => _VendorsTabState();
}

class _VendorsTabState extends State<_VendorsTab> {
  final _search = TextEditingController();
  String _searchQuery = '';
  String _filter = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Vendor Dashboard Header
    final vendors = _buildVendorSummaries(widget.medications, widget.purchases);
    final totalValue = vendors.fold<double>(0, (sum, v) => sum + v.stockValue);
    final totalItems = vendors.fold<int>(0, (sum, v) => sum + v.itemCount);

    // 2. Filtered Vendors
    final filteredVendors = vendors
        .where((v) {
          if (_filter == 'All') return true;
          if (_filter == 'Low Stock') return v.lowStockCount > 0;
          if (_filter == 'Expiring') return v.expiringCount > 0;
          return true;
        })
        .where((v) => v.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    if (widget.medications.isEmpty) {
      return const _PlaceholderScreen(
        icon: Icons.storefront_outlined,
        title: 'No vendors yet',
        message: 'Add an item with a supplier to see it grouped here.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Stats
        Row(
          children: [
            Expanded(
              child: _NewStatCard(
                title: 'Total Vendors',
                value: vendors.length.toString(),
                subtext: 'Active Suppliers',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NewStatCard(
                title: 'Total Value',
                value: _formatCurrency(totalValue),
                subtext: 'inventory held',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NewStatCard(
                title: 'Total Items',
                value: totalItems.toString(),
                subtext: 'across vendors',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Vendor Health Panel
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cru.inset,
            borderRadius: BorderRadius.circular(CruRadius.card),
            border: Border.all(color: context.cru.label3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vendor Health',
                style: CruType.body.w700.tint(context.cru.label),
              ),
              const SizedBox(height: 12),
              if (vendors.isEmpty)
                Text(
                  'No vendor data yet',
                  style: TextStyle(color: context.cru.label3),
                )
              else
                ...vendors
                    .take(3)
                    .map(
                      (v) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.storefront,
                              size: 16,
                              color: context.cru.label2,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v.name, style: CruType.caption.w600),
                                  const SizedBox(height: 4),
                                  _StripedProgressBar(
                                    value: totalValue > 0
                                        ? (v.stockValue / totalValue).clamp(
                                            0.0,
                                            1.0,
                                          )
                                        : 0.0,
                                    color: v.lowStockCount > 0
                                        ? context.cru.amberText
                                        : context.cru.greenText,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _formatCurrency(v.stockValue),
                              style: CruType.caption.w700,
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Filters, then the search filling the row (as on every list).
        DentalFilterBar(
          filters: [
            for (final f in const ['All', 'Low Stock', 'Expiring'])
              _FilterChip(
                label: f,
                active: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
          ],
          search: DentalSearchField(
            controller: _search,
            hint: 'Search vendors',
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        const SizedBox(height: 16),

        // List of Vendor Cards
        Expanded(
          child: ListView.separated(
            itemCount: filteredVendors.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _VendorCard(
              vendor: filteredVendors[index],
              onEditMedicine: widget.onEditMedicine,
              onOpenMedicineDetail: widget.onOpenMedicineDetail,
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        // The Inventory filter-chip look: accent tint when selected.
        decoration: BoxDecoration(
          color: active ? context.cru.accentTint : context.cru.surface,
          borderRadius: BorderRadius.circular(CruRadius.full),
          border: Border.all(
            color: active ? Colors.transparent : context.cru.hairline,
          ),
        ),
        child: Text(
          label,
          style: CruType.caption.w600.tint(
            active ? context.cru.accentText : context.cru.label,
          ),
        ),
      ),
    );
  }
}

class _VendorCard extends StatelessWidget {
  final _VendorSummary vendor;
  final ValueChanged<MedicineModel> onEditMedicine;
  final ValueChanged<MedicineModel> onOpenMedicineDetail;

  const _VendorCard({
    required this.vendor,
    required this.onEditMedicine,
    required this.onOpenMedicineDetail,
  });

  @override
  Widget build(BuildContext context) {
    final isUnassigned = vendor.name == 'Unassigned';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cru.surface,
        borderRadius: BorderRadius.circular(CruRadius.card),
        border: Border.all(color: context.cru.label3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isUnassigned
                      ? context.cru.label3
                      : context.cru.accentWash,
                  borderRadius: BorderRadius.circular(CruRadius.control),
                ),
                child: Icon(
                  isUnassigned
                      ? Icons.help_outline_rounded
                      : Icons.storefront_rounded,
                  size: 20,
                  color: isUnassigned ? context.cru.label3 : context.cru.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUnassigned ? 'No vendor assigned' : vendor.name,
                      style: CruType.row.w700.tint(context.cru.label),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${vendor.itemCount} item${vendor.itemCount == 1 ? '' : 's'}${vendor.hasKnownValue ? ' · ${_formatCurrency(vendor.stockValue)} in stock' : ''}',
                      style: CruType.caption.tint(context.cru.label2),
                    ),
                  ],
                ),
              ),
              if (vendor.lowStockCount > 0) ...[
                _VendorCountBadge(
                  label: '${vendor.lowStockCount} low',
                  color: context.cru.label2,
                  backgroundColor: context.cru.inset,
                ),
                const SizedBox(width: 6),
              ],
              if (vendor.expiringCount > 0)
                _VendorCountBadge(
                  label: '${vendor.expiringCount} exp',
                  color: context.cru.amberText,
                  backgroundColor: context.cru.amberTint,
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Expanded Medications Row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: vendor.medications.map((med) {
              return _VendorMedicineChip(
                medication: med,
                onTap: () {
                  final original = med.originalMedicine;
                  if (original == null) return;
                  if (isUnassigned) {
                    onEditMedicine(original);
                  } else {
                    onOpenMedicineDetail(original);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isUnassigned
                    ? 'Tap an item to add its vendor.'
                    : 'Tap an item to view details.',
                style: CruType.micro
                    .tint(context.cru.label3)
                    .copyWith(fontStyle: FontStyle.italic),
              ),
              if (!isUnassigned)
                TextButton.icon(
                  onPressed: () {}, // Mock action for adding item to vendor
                  icon: const Icon(Icons.add_shopping_cart, size: 14),
                  label: const Text('Add Item', style: CruType.caption),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VendorCountBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color backgroundColor;

  const _VendorCountBadge({
    required this.label,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(CruRadius.card),
      ),
      child: Text(label, style: CruType.caption.w600.tint(color)),
    );
  }
}

class _VendorMedicineChip extends StatelessWidget {
  final MedicationData medication;
  final VoidCallback onTap;

  const _VendorMedicineChip({required this.medication, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final original = medication.originalMedicine;
    final bool isLowStock = original?.isLowStock ?? false;
    final bool isExpiring = original?.isExpiringSoon ?? false;
    final Color? dotColor = isLowStock
        ? context.cru.label2
        : isExpiring
        ? context.cru.amberText
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.cru.inset,
          borderRadius: BorderRadius.circular(CruRadius.card),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              medication.name,
              style: CruType.caption.tint(context.cru.label),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// 6. ORDERS TAB (Over-Engineered)
// ==============================================================================

class _ReorderSuggestion {
  final MedicineModel medicine;
  final int suggestedQty;
  final double? estimatedCost;

  const _ReorderSuggestion({
    required this.medicine,
    required this.suggestedQty,
    this.estimatedCost,
  });
}

List<_ReorderSuggestion> _buildReorderQueue(List<MedicationData> medications) {
  final suggestions = <_ReorderSuggestion>[];
  for (final med in medications) {
    final original = med.originalMedicine;
    if (original == null || !original.isLowStock) continue;
    final target = original.reorderThreshold > 0
        ? original.reorderThreshold * 2
        : 10;
    final rawQty = target - original.currentStock;
    final suggestedQty = rawQty < 1 ? 1 : rawQty;
    final estimatedCost = original.unitPrice != null
        ? original.unitPrice! * suggestedQty
        : null;
    suggestions.add(
      _ReorderSuggestion(
        medicine: original,
        suggestedQty: suggestedQty,
        estimatedCost: estimatedCost,
      ),
    );
  }
  suggestions.sort((a, b) {
    final aOut = a.medicine.currentStock == 0;
    final bOut = b.medicine.currentStock == 0;
    if (aOut != bOut) return aOut ? -1 : 1;
    return a.medicine.currentStock.compareTo(b.medicine.currentStock);
  });
  return suggestions;
}

class _OrdersTab extends StatefulWidget {
  final List<MedicationData> medications;
  final List<StockTransactionModel> transactions;
  final InventoryRepository repository;
  final ValueChanged<MedicineModel> onOpenMedicineDetail;

  const _OrdersTab({
    required this.medications,
    required this.transactions,
    required this.repository,
    required this.onOpenMedicineDetail,
  });

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final queue = _buildReorderQueue(widget.medications);
    final totalCost = queue.fold<double>(
      0,
      (sum, s) => sum + (s.estimatedCost ?? 0),
    );
    final hasAnyCost = queue.any((s) => s.estimatedCost != null);

    final filteredQueue = queue.where((q) {
      if (_filter == 'All') return true;
      if (_filter == 'Urgent') return q.medicine.currentStock == 0;
      if (_filter == 'Low') return q.medicine.currentStock > 0;
      return true;
    }).toList();

    if (queue.isEmpty) {
      return const _PlaceholderScreen(
        icon: Icons.receipt_long_outlined,
        title: 'No reorders needed',
        message: 'Every item is above its reorder threshold.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Order Header Stats
        Row(
          children: [
            Expanded(
              child: _NewStatCard(
                title: 'Needs Attention',
                value: queue.length.toString(),
                subtext: 'items below threshold',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NewStatCard(
                title: 'Est. Cost',
                value: hasAnyCost ? _formatCurrency(totalCost) : '—',
                subtext: 'to restock all',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NewStatCard(
                title: 'Urgent',
                value: queue
                    .where((q) => q.medicine.currentStock == 0)
                    .length
                    .toString(),
                subtext: 'Out of Stock',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Order Filtering
        Row(
          children: [
            _FilterChip(
              label: 'All',
              active: _filter == 'All',
              onTap: () => setState(() => _filter = 'All'),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Urgent',
              active: _filter == 'Urgent',
              onTap: () => setState(() => _filter = 'Urgent'),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Low Stock',
              active: _filter == 'Low',
              onTap: () => setState(() => _filter = 'Low'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Existing Orders
        Expanded(
          child: ListView.separated(
            itemCount: filteredQueue.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ReorderRow(
              suggestion: filteredQueue[index],
              transactions: widget.transactions,
              repository: widget.repository,
              onOpenMedicineDetail: widget.onOpenMedicineDetail,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReorderRow extends StatelessWidget {
  final _ReorderSuggestion suggestion;
  final List<StockTransactionModel> transactions;
  final InventoryRepository repository;
  final ValueChanged<MedicineModel> onOpenMedicineDetail;

  const _ReorderRow({
    required this.suggestion,
    required this.transactions,
    required this.repository,
    required this.onOpenMedicineDetail,
  });

  @override
  Widget build(BuildContext context) {
    final medicine = suggestion.medicine;
    final isOut = medicine.currentStock == 0;

    final lastRestock = transactions
        .where(
          (t) =>
              t.medicineId == medicine.id &&
              t.type == StockTransactionType.restock,
        )
        .fold<StockTransactionModel?>(
          null,
          (latest, t) => latest == null || t.createdAt.isAfter(latest.createdAt)
              ? t
              : latest,
        );
    final daysSinceRestock = lastRestock != null
        ? DateTime.now().difference(lastRestock.createdAt).inDays
        : null;

    final reorderProgress = medicine.reorderThreshold > 0
        ? (medicine.currentStock / medicine.reorderThreshold).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cru.surface,
        borderRadius: BorderRadius.circular(CruRadius.control),
        border: Border.all(
          color: isOut ? context.cru.inset : context.cru.label3,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onOpenMedicineDetail(medicine),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          medicine.name,
                          style: CruType.callout.w700.tint(context.cru.label),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isOut ? context.cru.inset : context.cru.amber,
                          borderRadius: BorderRadius.circular(CruRadius.card),
                        ),
                        child: Text(
                          isOut ? 'Out of stock' : 'Low stock',
                          style: CruType.micro.w600.tint(
                            isOut ? context.cru.label2 : context.cru.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _StripedProgressBar(
                    value: reorderProgress,
                    color: isOut ? context.cru.amberText : context.cru.amber,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${medicine.currentStock} ${medicine.unit} left · Suggest +${suggestion.suggestedQty} ${medicine.unit}'
                    '${suggestion.estimatedCost != null ? ' (${_formatCurrency(suggestion.estimatedCost!)})' : ''}',
                    style: CruType.caption.tint(context.cru.label2),
                  ),
                  if (daysSinceRestock != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 12,
                          color: context.cru.label3,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          daysSinceRestock == 0
                              ? 'Restocked today'
                              : 'Restocked ${daysSinceRestock}d ago',
                          style: CruType.micro.tint(context.cru.label3),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () => showStockAdjustmentDialog(
              context,
              medicine: medicine,
              repository: repository,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.cru.primaryButtonFill,
              foregroundColor: context.cru.primaryButtonText,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CruRadius.control),
              ),
            ),
            child: Text('Restock', style: CruType.caption.w600),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// 7. USAGE ANALYTICS TAB (Over-Engineered)
// ==============================================================================

class _MedicineUsage {
  final String name;
  final int quantity;

  const _MedicineUsage({required this.name, required this.quantity});
}

class _UsageAnalyticsData {
  final int dispensedQty30d;
  final int restockedQty30d;
  final int writeOffQty30d;
  final double dispensedValue30d;
  final List<double> dailyDispensed7d;
  final List<_MedicineUsage> topMedicines;
  final List<StockTransactionModel> recentTransactions;
  final Map<String, double> categoryBreakdown; // Added for category analytics

  const _UsageAnalyticsData({
    required this.dispensedQty30d,
    required this.restockedQty30d,
    required this.writeOffQty30d,
    required this.dispensedValue30d,
    required this.dailyDispensed7d,
    required this.topMedicines,
    required this.recentTransactions,
    required this.categoryBreakdown,
  });
}

_UsageAnalyticsData _buildUsageAnalytics(
  List<StockTransactionModel> transactions,
  Map<String, MedicineModel> medicineById,
) {
  final now = DateTime.now();
  final since30 = now.subtract(const Duration(days: 30));
  final since7 = now.subtract(const Duration(days: 7));

  int dispensed30 = 0;
  int restocked30 = 0;
  int writeOff30 = 0;
  double dispensedValue30 = 0;
  final dailyBuckets = List<double>.filled(7, 0);
  final usageByMedicine = <String, int>{};
  final categoryTotals = <String, double>{};

  for (final tx in transactions) {
    if (tx.createdAt.isBefore(since30)) continue;

    switch (tx.type) {
      case StockTransactionType.dispense:
        dispensed30 += tx.quantity;
        final med = medicineById[tx.medicineId];
        final price = med?.unitPrice;
        if (price != null) dispensedValue30 += price * tx.quantity;

        final name = med?.name ?? 'Unknown item';
        usageByMedicine.update(
          name,
          (existing) => existing + tx.quantity,
          ifAbsent: () => tx.quantity,
        );

        // Add category data
        if (med != null && med.category.isNotEmpty) {
          categoryTotals.update(
            med.category,
            (existing) => existing + (price ?? 0) * tx.quantity,
            ifAbsent: () => (price ?? 0) * tx.quantity,
          );
        }

        if (!tx.createdAt.isBefore(since7)) {
          final dayIndex = 6 - now.difference(tx.createdAt).inDays;
          if (dayIndex >= 0 && dayIndex < 7) {
            dailyBuckets[dayIndex] += tx.quantity;
          }
        }
        break;
      case StockTransactionType.restock:
        restocked30 += tx.quantity;
        break;
      case StockTransactionType.expiredWriteoff:
        writeOff30 += tx.quantity;
        break;
      case StockTransactionType.adjustment:
        break;
    }
  }

  final topMedicines =
      usageByMedicine.entries
          .map((e) => _MedicineUsage(name: e.key, quantity: e.value))
          .toList()
        ..sort((a, b) => b.quantity.compareTo(a.quantity));

  final recent = List<StockTransactionModel>.from(transactions)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return _UsageAnalyticsData(
    dispensedQty30d: dispensed30,
    restockedQty30d: restocked30,
    writeOffQty30d: writeOff30,
    dispensedValue30d: dispensedValue30,
    dailyDispensed7d: dailyBuckets,
    topMedicines: topMedicines.take(5).toList(),
    recentTransactions: recent.take(8).toList(),
    categoryBreakdown: categoryTotals,
  );
}

class _UsageAnalyticsTab extends StatefulWidget {
  final List<StockTransactionModel> transactions;
  final Map<String, MedicineModel> medicineById;

  const _UsageAnalyticsTab({
    required this.transactions,
    required this.medicineById,
  });

  @override
  State<_UsageAnalyticsTab> createState() => _UsageAnalyticsTabState();
}

class _UsageAnalyticsTabState extends State<_UsageAnalyticsTab> {
  bool _isLast7Days = false;

  @override
  Widget build(BuildContext context) {
    final data = _buildUsageAnalytics(widget.transactions, widget.medicineById);

    // Turnover rate metric
    final totalStockValue = widget.medicineById.values.fold<double>(
      0,
      (sum, m) => sum + (m.unitPrice ?? 0) * m.currentStock,
    );
    final turnoverRate = totalStockValue > 0
        ? (data.dispensedValue30d / totalStockValue) * 100
        : 0.0;

    if (widget.transactions.isEmpty) {
      return const _PlaceholderScreen(
        icon: Icons.insights_outlined,
        title: 'No activity yet',
        message: 'Restock or dispense an item to see usage trends here.',
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Usage Analytics',
                style: CruType.headline.w700.tint(context.cru.label),
              ),
              Row(
                children: [
                  _FilterChip(
                    label: '7 Days',
                    active: _isLast7Days,
                    onTap: () => setState(() => _isLast7Days = true),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '30 Days',
                    active: !_isLast7Days,
                    onTap: () => setState(() => _isLast7Days = false),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Header Stats
          Row(
            children: [
              Expanded(
                child: _UsageStatChip(
                  label: 'Units Dispensed',
                  value: '${data.dispensedQty30d}',
                  sublabel: '30d',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _UsageStatChip(
                  label: 'Units Restocked',
                  value: '${data.restockedQty30d}',
                  sublabel: '30d',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _UsageStatChip(
                  label: 'Value Used',
                  value: _formatCurrency(data.dispensedValue30d),
                  sublabel: '30d',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _UsageStatChip(
                  label: 'Turnover Rate',
                  value: '${turnoverRate.toStringAsFixed(1)}%',
                  sublabel: 'of inventory',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Main Analytics Row (split into two columns)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 1000) {
                return Row(
                  children: [
                    Expanded(
                      child: _WeeklyUsageChart(
                        data: data,
                        is7Days: _isLast7Days,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: _CategoryBreakdownPanel(data: data)),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _WeeklyUsageChart(data: data, is7Days: _isLast7Days),
                    const SizedBox(height: 24),
                    _CategoryBreakdownPanel(data: data),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 24),

          // Top Items
          if (data.topMedicines.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.cru.surface,
                borderRadius: BorderRadius.circular(CruRadius.card),
                border: Border.all(color: context.cru.label3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top Dispensed Items',
                    style: CruType.callout.w700.tint(context.cru.label),
                  ),
                  const SizedBox(height: 12),
                  ...data.topMedicines.map(
                    (m) => _TopMedicineRow(
                      usage: m,
                      maxQuantity: data.topMedicines.first.quantity,
                      unitValue: widget.medicineById.entries
                          .where((e) => e.value.name == m.name)
                          .map((e) => e.value.unitPrice ?? 0)
                          .fold(0.0, (a, b) => a + b),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),

          // Recent Transactions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cru.surface,
              borderRadius: BorderRadius.circular(CruRadius.card),
              border: Border.all(color: context.cru.cardBorder, width: 0.75),
              boxShadow: const [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent stock activity',
                  style: CruType.callout.w700.tint(context.cru.label),
                ),
                const SizedBox(height: 12),
                ...data.recentTransactions.map(
                  (tx) => _UsageTransactionRow(
                    transaction: tx,
                    medicineName:
                        widget.medicineById[tx.medicineId]?.name ??
                        'Unknown item',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _WeeklyUsageChart extends StatelessWidget {
  final _UsageAnalyticsData data;
  final bool is7Days;

  const _WeeklyUsageChart({required this.data, required this.is7Days});

  @override
  Widget build(BuildContext context) {
    final values = is7Days
        ? data.dailyDispensed7d
        : List<double>.filled(30, 0); // Mocking 30d data not in model

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cru.surface,
        borderRadius: BorderRadius.circular(CruRadius.card),
        border: Border.all(color: context.cru.label3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dispensed Volume',
            style: CruType.callout.w700.tint(context.cru.label),
          ),
          const SizedBox(height: 16),
          // Greatly expanded bars
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: values.asMap().entries.map((entry) {
                final index = entry.key;
                final value = entry.value;
                final maxValue = values.fold<double>(
                  0,
                  (m, v) => v > m ? v : m,
                );
                final heightFactor = maxValue > 0 ? value / maxValue : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          value > 0 ? value.toStringAsFixed(0) : '',
                          style: CruType.micro.tint(context.cru.label3),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 120 * heightFactor + 4,
                          decoration: BoxDecoration(
                            color: context.cru.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          is7Days
                              ? [
                                  '6d',
                                  '5d',
                                  '4d',
                                  '3d',
                                  '2d',
                                  '1d',
                                  'Today',
                                ][index % 7]
                              : '${index + 1}',
                          style: CruType.micro.tint(context.cru.label3),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdownPanel extends StatelessWidget {
  final _UsageAnalyticsData data;

  const _CategoryBreakdownPanel({required this.data});

  @override
  Widget build(BuildContext context) {
    final categories = data.categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxValue = categories.isEmpty ? 1.0 : categories.first.value;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cru.surface,
        borderRadius: BorderRadius.circular(CruRadius.card),
        border: Border.all(color: context.cru.label3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Category Breakdown',
            style: CruType.callout.w700.tint(context.cru.label),
          ),
          const SizedBox(height: 16),
          if (categories.isEmpty)
            Text(
              'No category data yet',
              style: TextStyle(color: context.cru.label3),
            )
          else
            ...categories.take(6).map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        entry.key,
                        style: CruType.caption.w600,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StripedProgressBar(
                        value: (entry.value / maxValue).clamp(0.0, 1.0),
                        color: context.cru.ai,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _formatCurrency(entry.value),
                      style: CruType.caption.w700,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _UsageStatChip extends StatelessWidget {
  final String label;
  final String value;
  final String sublabel;

  const _UsageStatChip({
    required this.label,
    required this.value,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cru.surface,
        borderRadius: BorderRadius.circular(CruRadius.control),
        border: Border.all(color: context.cru.label3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: CruType.caption.w500.tint(context.cru.label2)),
          const SizedBox(height: 6),
          Text(value, style: CruType.headline.w700.tint(context.cru.label)),
          const SizedBox(height: 2),
          Text(sublabel, style: CruType.micro.tint(context.cru.label3)),
        ],
      ),
    );
  }
}

class _TopMedicineRow extends StatelessWidget {
  final _MedicineUsage usage;
  final int maxQuantity;
  final double unitValue;

  const _TopMedicineRow({
    required this.usage,
    required this.maxQuantity,
    required this.unitValue,
  });

  @override
  Widget build(BuildContext context) {
    final progress = maxQuantity > 0 ? usage.quantity / maxQuantity : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  usage.name,
                  style: CruType.subhead.w600.tint(context.cru.label),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${usage.quantity} units · ${_formatCurrency(usage.quantity * unitValue)}',
                style: CruType.caption.tint(context.cru.label2),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _StripedProgressBar(value: progress, color: context.cru.accent),
        ],
      ),
    );
  }
}

class _UsageTransactionRow extends StatelessWidget {
  final StockTransactionModel transaction;
  final String medicineName;

  const _UsageTransactionRow({
    required this.transaction,
    required this.medicineName,
  });

  String _label() {
    switch (transaction.type) {
      case StockTransactionType.restock:
        return 'Restocked';
      case StockTransactionType.dispense:
        return 'Dispensed';
      case StockTransactionType.adjustment:
        return 'Adjusted';
      case StockTransactionType.expiredWriteoff:
        return 'Written off';
    }
  }

  bool get _isIncrease => transaction.type == StockTransactionType.restock;

  @override
  Widget build(BuildContext context) {
    final dt = transaction.createdAt;
    final dateLabel = '${dt.day}/${dt.month}/${dt.year}';
    final color = _isIncrease ? context.cru.greenText : context.cru.label2;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            _isIncrease
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_label()} $medicineName',
              style: CruType.caption.tint(context.cru.label),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${_isIncrease ? '+' : '-'}${transaction.quantity} · $dateLabel',
            style: CruType.micro.tint(context.cru.label3),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _PlaceholderScreen({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: context.cru.label3),
          const SizedBox(height: 16),
          Text(title, style: CruType.title2.tint(context.cru.label)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: CruType.text.tint(context.cru.label3),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Public hosts for the redesigned InventoryScreen's Orders, Vendors and
// Usage sections. Each builds the data its tab needs from providers, so
// InventoryScreen can mount them with no arguments. Behaviour unchanged.
// =============================================================================

final _inventoryMedicationsProvider =
    Provider<AsyncValue<List<MedicationData>>>(
      (ref) => ref.watch(
        medicinesStreamProvider.select(
          (async) => async.whenData(_medicationsFrom),
        ),
      ),
    );

List<MedicationData> _watchMedications(WidgetRef ref) =>
    ref.watch(_inventoryMedicationsProvider).value ?? const [];

void _pushMedicineDetail(BuildContext context, MedicineModel medicine) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => MedicineDetailScreen(medicine: medicine)),
  );
}

/// The reorder queue (Orders section).
class InventoryOrdersTab extends ConsumerWidget {
  const InventoryOrdersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _OrdersTab(
      medications: _watchMedications(ref),
      transactions:
          ref.watch(recentStockTransactionsProvider).value ??
          const <StockTransactionModel>[],
      repository: ref.watch(inventoryRepositoryProvider),
      onOpenMedicineDetail: (m) => _pushMedicineDetail(context, m),
    );
  }
}

/// Suppliers and what each one stocks (Vendors section).
class InventoryVendorsTab extends ConsumerWidget {
  const InventoryVendorsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(inventoryRepositoryProvider);
    return _VendorsTab(
      medications: _watchMedications(ref),
      purchases:
          ref.watch(stockPurchasesProvider).value ??
          const <StockTransactionModel>[],
      onEditMedicine: (m) => showDesktopAddEditMedicineDialog(
        context,
        medicine: m,
        repository: repository,
      ),
      onOpenMedicineDetail: (m) => _pushMedicineDetail(context, m),
    );
  }
}

/// Usage analytics (Usage section).
class InventoryUsageTab extends ConsumerWidget {
  const InventoryUsageTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medications = _watchMedications(ref);
    return _UsageAnalyticsTab(
      transactions:
          ref.watch(recentStockTransactionsProvider).value ??
          const <StockTransactionModel>[],
      medicineById: <String, MedicineModel>{
        for (final med in medications)
          if (med.originalMedicine != null)
            med.originalMedicine!.id: med.originalMedicine!,
      },
    );
  }
}
