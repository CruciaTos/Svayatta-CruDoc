import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/presentation/add_edit_medicine_form.dart';
import 'package:doctor_management_app/features/inventory/presentation/medicine_detail_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/stock_adjustment_dialog.dart';

enum _InventoryFilter { all, lowStock, expiring }

/// The Inventory tab screen — search, filter, and list every active
/// medicine, with a FAB to add a new one.
class InventoryListScreen extends ConsumerStatefulWidget {
  const InventoryListScreen({super.key, this.autoOpenAddForm = false});

  /// When true, the Add Medicine form opens automatically once this screen
  /// mounts — used by the dashboard's "Add Inventory Item" quick action so
  /// it can push straight into the add flow, matching how the dashboard
  /// pushes [AddPatientPage] for "Patient".
  final bool autoOpenAddForm;

  @override
  ConsumerState<InventoryListScreen> createState() =>
      _InventoryListScreenState();
}

class _InventoryListScreenState extends ConsumerState<InventoryListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _InventoryFilter _filter = _InventoryFilter.all;
  String? _category;

  @override
  void initState() {
    super.initState();
    if (widget.autoOpenAddForm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showAddEditMedicineForm(context);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MedicineModel> _applyFilters(List<MedicineModel> medicines) {
    var result = medicines;

    switch (_filter) {
      case _InventoryFilter.lowStock:
        result = result.where((m) => m.isLowStock).toList();
        break;
      case _InventoryFilter.expiring:
        result = result.where((m) => m.isExpiringSoon).toList();
        break;
      case _InventoryFilter.all:
        break;
    }

    if (_category != null) {
      result = result.where((m) => m.category == _category).toList();
    }

    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result
          .where((m) => m.name.toLowerCase().contains(query))
          .toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final medicinesAsync = ref.watch(medicinesStreamProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.chartBarLight,
        foregroundColor: Colors.white,
        onPressed: () => showAddEditMedicineForm(context),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Inventory', style: AppColors.pageHeading),
              const SizedBox(height: 8),
              _SearchBar(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              medicinesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (medicines) => _FilterRow(
                  selected: _filter,
                  category: _category,
                  categories: medicines
                      .map((m) => m.category)
                      .where((c) => c.trim().isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort(),
                  onSelected: (filter) => setState(() => _filter = filter),
                  onCategorySelected: (category) =>
                      setState(() => _category = category),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: medicinesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text(
                      'Error loading inventory: $error',
                      style: AppColors.bodyMedium,
                    ),
                  ),
                  data: (medicines) {
                    final filtered = _applyFilters(medicines);
                    if (filtered.isEmpty) {
                      final message = medicines.isEmpty
                          ? 'No medicines yet — tap + to add one'
                          : 'No matches';
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            message,
                            style: AppColors.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      physics: const ClampingScrollPhysics(),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _MedicineTile(medicine: filtered[index]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- SEARCH BAR ----------
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search, color: AppColors.silver, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              style: AppColors.bodyMedium,
              onChanged: onChanged,
              decoration: const InputDecoration(
                hintText: 'Search medicines...',
                hintStyle: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.silver,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ---------- FILTER CHIPS ----------
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.selected,
    required this.category,
    required this.categories,
    required this.onSelected,
    required this.onCategorySelected,
  });

  final _InventoryFilter selected;
  final String? category;
  final List<String> categories;
  final ValueChanged<_InventoryFilter> onSelected;
  final ValueChanged<String?> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            selected: selected == _InventoryFilter.all,
            onTap: () => onSelected(_InventoryFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Low Stock',
            selected: selected == _InventoryFilter.lowStock,
            onTap: () => onSelected(_InventoryFilter.lowStock),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Expiring Soon',
            selected: selected == _InventoryFilter.expiring,
            onTap: () => onSelected(_InventoryFilter.expiring),
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(width: 1, height: 20, color: AppColors.divider),
            const SizedBox(width: 8),
            for (final c in categories) ...[
              _FilterChip(
                label: c,
                selected: category == c,
                onTap: () => onCategorySelected(category == c ? null : c),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.chartBarLight : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.chartBarLight : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ---------- MEDICINE TILE ----------
class _MedicineTile extends StatelessWidget {
  const _MedicineTile({required this.medicine});

  final MedicineModel medicine;

  Color _stockColor() {
    if (medicine.currentStock <= medicine.reorderThreshold) {
      return Colors.redAccent;
    }
    if (medicine.currentStock <= medicine.reorderThreshold * 1.5) {
      return const Color(0xFFCC8B00); // amber
    }
    return AppColors.positiveGreen;
  }

  String? _expiryLabel() {
    final expiry = medicine.expiryDate;
    if (expiry == null) return null;
    final days = expiry.difference(DateTime.now()).inDays;
    if (days < 0) return 'Expired';
    if (days == 0) return 'Expires today';
    if (days <= 30) return 'Expires in $days d';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final expiryLabel = _expiryLabel();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MedicineDetailScreen(medicine: medicine),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _stockColor(),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medicine.name,
                        style: AppColors.bodyLarge.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${medicine.currentStock} / ${medicine.reorderThreshold} ${medicine.unit}'
                        '${medicine.category.isNotEmpty ? ' • ${medicine.category}' : ''}',
                        style: AppColors.bodySmall,
                      ),
                      if (expiryLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          expiryLabel,
                          style: AppColors.bodySmall.copyWith(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: AppColors.silver,
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'adjust':
                        showStockAdjustmentDialog(context, medicine: medicine);
                        break;
                      case 'edit':
                        showAddEditMedicineForm(context, medicine: medicine);
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'adjust',
                      child: Text('Restock / Dispense'),
                    ),
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
