import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/presentation/add_edit_medicine_form.dart';
import 'package:doctor_management_app/features/inventory/presentation/medicine_detail_screen.dart';

final _desktopInventoryViewProvider =
    Provider<AsyncValue<_DesktopInventoryViewData>>((ref) {
      return ref.watch(
        medicinesStreamProvider.select(
          (medicinesAsync) => medicinesAsync.whenData(_mapMedicinesToViewData),
        ),
      );
    });

const _emptyDesktopInventoryViewData = _DesktopInventoryViewData(
  totalItems: '0',
  lowStockAlerts: '0',
  outOfStock: '0',
  inventoryValue: '\$0',
  monthlyUsage: '—',
  medications: <MedicationData>[],
  alerts: <AlertData>[],
);

class DesktopInventoryScreen extends ConsumerWidget {
  const DesktopInventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryViewAsync = ref.watch(_desktopInventoryViewProvider);
    final inventoryViewData =
        inventoryViewAsync.value ?? _emptyDesktopInventoryViewData;
    final repository = ref.watch(inventoryRepositoryProvider);

    void openAddMedicine() {
      showAddEditMedicineForm(context, repository: repository);
    }

    void openEditMedicine(MedicineModel medicine) {
      showAddEditMedicineForm(
        context,
        medicine: medicine,
        repository: repository,
      );
    }

    void openMedicineDetail(MedicineModel medicine) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MedicineDetailScreen(medicine: medicine),
        ),
      );
    }

    return Stack(
      children: [
        // Full‑width white card matching the revenue screen
        SizedBox.expand(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: _InventoryDashboardView(
              totalItems: inventoryViewData.totalItems,
              lowStockAlerts: inventoryViewData.lowStockAlerts,
              outOfStock: inventoryViewData.outOfStock,
              inventoryValue: inventoryViewData.inventoryValue,
              monthlyUsage: inventoryViewData.monthlyUsage,
              medications: inventoryViewData.medications,
              alerts: inventoryViewData.alerts,
              onAddMedicine: openAddMedicine,
              onEditMedicine: openEditMedicine,
              onOpenMedicineDetail: openMedicineDetail,
            ),
          ),
        ),
        if (inventoryViewAsync.hasError)
          Positioned(
            top: 16,
            right: 16,
            child: _InventoryStatusBanner(
              icon: Icons.error_outline_rounded,
              message: 'Failed to load inventory',
              color: Colors.red.shade700,
              backgroundColor: Colors.red.shade50,
            ),
          )
        else if (inventoryViewAsync.isLoading)
          const Positioned(
            top: 16,
            right: 16,
            child: _InventoryStatusBanner(
              icon: Icons.sync_rounded,
              message: 'Syncing inventory...',
              color: Color(0xFF2563EB),
              backgroundColor: Color(0xFFEFF6FF),
            ),
          ),
      ],
    );
  }
}

class _InventoryStatusBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Color backgroundColor;

  const _InventoryStatusBanner({
    required this.icon,
    required this.message,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DATA MODELS
// -----------------------------------------------------------------------------

class _DesktopInventoryViewData {
  final String totalItems;
  final String lowStockAlerts;
  final String outOfStock;
  final String inventoryValue;
  final String monthlyUsage;
  final List<MedicationData> medications;
  final List<AlertData> alerts;

  const _DesktopInventoryViewData({
    required this.totalItems,
    required this.lowStockAlerts,
    required this.outOfStock,
    required this.inventoryValue,
    required this.monthlyUsage,
    required this.medications,
    required this.alerts,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _DesktopInventoryViewData &&
            other.totalItems == totalItems &&
            other.lowStockAlerts == lowStockAlerts &&
            other.outOfStock == outOfStock &&
            other.inventoryValue == inventoryValue &&
            other.monthlyUsage == monthlyUsage &&
            _listEquals(other.medications, medications) &&
            _listEquals(other.alerts, alerts);
  }

  @override
  int get hashCode => Object.hash(
    totalItems,
    lowStockAlerts,
    outOfStock,
    inventoryValue,
    monthlyUsage,
    Object.hashAll(medications),
    Object.hashAll(alerts),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;

  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }

  return true;
}

_DesktopInventoryViewData _mapMedicinesToViewData(
  List<MedicineModel> medicines,
) {
  final medications = <MedicationData>[];
  final alerts = <AlertData>[];
  int lowStockCount = 0;
  int outOfStockCount = 0;
  double inventoryTotal = 0;
  bool hasAnyPrice = false;
  final now = DateTime.now();

  for (final medicine in medicines) {
    final subtitle = medicine.category.isNotEmpty && medicine.unit.isNotEmpty
        ? '${medicine.category} · ${medicine.unit}'
        : '';
    final isLowStock = medicine.isLowStock;
    final isOutOfStock = medicine.currentStock == 0;
    final isExpiringSoon = medicine.isExpiringSoon;
    final reorderThreshold = medicine.reorderThreshold;
    final progress = reorderThreshold > 0
        ? (medicine.currentStock / reorderThreshold).clamp(0.0, 1.0)
        : 0.0;
    final progressColor = _stockLevelColor(medicine, progress);
    final expiryDays = medicine.expiryDate?.difference(now).inDays;

    medications.add(
      MedicationData(
        name: medicine.name,
        subtitle: subtitle,
        status: isExpiringSoon ? 'Expiring' : 'Active',
        dose: '${medicine.currentStock} ${medicine.unit}',
        daysLeft: medicine.expiryDate != null
            ? '${expiryDays ?? 0} days left'
            : '—',
        progress: progress,
        progressColor: progressColor,
        synced: 'Inventory',
        nextDose: '—',
        isPaused: false,
        buttonFilled: false,
        originalMedicine: medicine,
      ),
    );

    if (isLowStock) {
      lowStockCount += 1;
      alerts.add(
        AlertData(
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.amber.shade700,
          bgColor: Colors.amber.shade50,
          title: medicine.name,
          subtitle: 'Low stock: ${medicine.currentStock} ${medicine.unit}',
          actionLabel: 'Restock',
        ),
      );
    }

    if (isExpiringSoon) {
      alerts.add(
        AlertData(
          icon: Icons.timer_outlined,
          iconColor: Colors.orange.shade700,
          bgColor: Colors.orange.shade50,
          title: medicine.name,
          subtitle: 'Expiring soon',
          actionLabel: 'View',
        ),
      );
    }

    if (isOutOfStock) {
      outOfStockCount += 1;
    }

    if (medicine.unitPrice != null) {
      hasAnyPrice = true;
      inventoryTotal += medicine.unitPrice! * medicine.currentStock;
    }
  }

  final inventoryValue = hasAnyPrice
      ? '\$${inventoryTotal.toStringAsFixed(2)}'
      : '\$0';

  return _DesktopInventoryViewData(
    totalItems: medicines.length.toString(),
    lowStockAlerts: lowStockCount.toString(),
    outOfStock: outOfStockCount.toString(),
    inventoryValue: inventoryValue,
    monthlyUsage: '—',
    medications: List.unmodifiable(medications),
    alerts: List.unmodifiable(alerts.take(20)),
  );
}

Color _stockLevelColor(MedicineModel medicine, double progress) {
  if (medicine.isLowStock) {
    return Colors.red.shade600;
  }

  if (progress < 0.6) {
    return Colors.amber.shade700;
  }

  return const Color(0xFF00C853);
}

// -----------------------------------------------------------------------------
// DATA MODELS (updated with originalMedicine)
// -----------------------------------------------------------------------------

class MedicationData {
  final String name;
  final String subtitle;
  final String status;
  final String dose;
  final String daysLeft;
  final double progress;
  final Color progressColor;
  final String synced;
  final String nextDose;
  final bool isPaused;
  final bool buttonFilled;
  final MedicineModel? originalMedicine;

  const MedicationData({
    required this.name,
    required this.subtitle,
    required this.status,
    required this.dose,
    required this.daysLeft,
    required this.progress,
    required this.progressColor,
    required this.synced,
    required this.nextDose,
    this.isPaused = false,
    this.buttonFilled = false,
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
            other.progressColor == progressColor &&
            other.synced == synced &&
            other.nextDose == nextDose &&
            other.isPaused == isPaused &&
            other.buttonFilled == buttonFilled &&
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
    progressColor,
    synced,
    nextDose,
    isPaused,
    buttonFilled,
    originalMedicine?.id,
  );
}

class AlertData {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final String actionLabel;

  const AlertData({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AlertData &&
            other.icon == icon &&
            other.iconColor == iconColor &&
            other.bgColor == bgColor &&
            other.title == title &&
            other.subtitle == subtitle &&
            other.actionLabel == actionLabel;
  }

  @override
  int get hashCode =>
      Object.hash(icon, iconColor, bgColor, title, subtitle, actionLabel);
}

// ==============================================================================
// MAIN DASHBOARD VIEW (now with tab management)
// ==============================================================================

class _InventoryDashboardView extends StatefulWidget {
  final String totalItems;
  final String lowStockAlerts;
  final String outOfStock;
  final String inventoryValue;
  final String monthlyUsage;
  final List<MedicationData> medications;
  final List<AlertData> alerts;
  final VoidCallback onAddMedicine;
  final ValueChanged<MedicineModel> onEditMedicine;
  final ValueChanged<MedicineModel> onOpenMedicineDetail;

  const _InventoryDashboardView({
    required this.totalItems,
    required this.lowStockAlerts,
    required this.outOfStock,
    required this.inventoryValue,
    required this.monthlyUsage,
    required this.medications,
    required this.alerts,
    required this.onAddMedicine,
    required this.onEditMedicine,
    required this.onOpenMedicineDetail,
  });

  @override
  State<_InventoryDashboardView> createState() =>
      _InventoryDashboardViewState();
}

class _InventoryDashboardViewState extends State<_InventoryDashboardView> {
  int _selectedTabIndex = 0;

  static const _tabLabels = ['Items', 'Vendors', 'Orders', 'Usage analytics'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InventoryHeaderSection(
          totalItems: widget.totalItems,
          lowStockAlerts: widget.lowStockAlerts,
          outOfStock: widget.outOfStock,
          inventoryValue: widget.inventoryValue,
          monthlyUsage: widget.monthlyUsage,
          onAddMedicine: widget.onAddMedicine,
          selectedTabIndex: _selectedTabIndex,
          tabLabels: _tabLabels,
          onTabSelected: (index) => setState(() => _selectedTabIndex = index),
        ),
        const SizedBox(height: 32),
        Expanded(
          child: _buildTabContent(),
        ),
      ],
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildItemsTab();
      case 1:
        return const _VendorsPlaceholder();
      case 2:
        return const _OrdersPlaceholder();
      case 3:
        return const _UsageAnalyticsPlaceholder();
      default:
        return _buildItemsTab();
    }
  }

  Widget _buildItemsTab() {
    return LayoutBuilder(
      builder: (context, bodyConstraints) {
        final bool isWideScreen = bodyConstraints.maxWidth > 1100;

        if (isWideScreen) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _FilteredMedicationSection(
                  medications: widget.medications,
                  onAddMedicine: widget.onAddMedicine,
                  onEditMedicine: widget.onEditMedicine,
                  onOpenMedicineDetail: widget.onOpenMedicineDetail,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: _ScrollableAlertsPanel(alerts: widget.alerts)),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _FilteredMedicationSection(
                  medications: widget.medications,
                  onAddMedicine: widget.onAddMedicine,
                  onEditMedicine: widget.onEditMedicine,
                  onOpenMedicineDetail: widget.onOpenMedicineDetail,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                flex: 2,
                child: _ScrollableAlertsPanel(alerts: widget.alerts),
              ),
            ],
          );
        }
      },
    );
  }
}

// ==============================================================================
// 1. HEADER, TABS & STATS
// ==============================================================================

class _InventoryHeaderSection extends StatelessWidget {
  final String totalItems;
  final String lowStockAlerts;
  final String outOfStock;
  final String inventoryValue;
  final String monthlyUsage;
  final VoidCallback onAddMedicine;
  final int selectedTabIndex;
  final List<String> tabLabels;
  final ValueChanged<int> onTabSelected;

  const _InventoryHeaderSection({
    required this.totalItems,
    required this.lowStockAlerts,
    required this.outOfStock,
    required this.inventoryValue,
    required this.monthlyUsage,
    required this.onAddMedicine,
    required this.selectedTabIndex,
    required this.tabLabels,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Inventory',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: onAddMedicine,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2937),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'Add item',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.settings_outlined,
                    size: 20,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: List.generate(tabLabels.length, (index) {
            return _TabItem(
              label: tabLabels[index],
              isActive: selectedTabIndex == index,
              onTap: () => onTabSelected(index),
            );
          }),
        ),
        const SizedBox(height: 24),
        // Only show stats for Items tab (or you can keep them always)
        if (selectedTabIndex == 0)
          LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  Expanded(
                    child: _NewStatCard(
                      title: 'Total items',
                      value: totalItems,
                      subtext: 'across all locations',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NewStatCard(
                      title: 'Low stock alerts',
                      value: lowStockAlerts,
                      subtext: 'needs restocking soon',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NewStatCard(
                      title: 'Out of stock',
                      value: outOfStock,
                      subtext: 'immediate attention',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NewStatCard(
                      title: 'Inventory value',
                      value: inventoryValue,
                      subtext: 'estimated total value',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NewStatCard(
                      title: 'Monthly usage',
                      value: monthlyUsage,
                      subtext: 'per last month',
                      hasPositiveGrowth: true,
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 24.0),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF1F2937)
                    : const Color(0xFF6B7280),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 2,
              width: 24,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF1F2937) : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtext;
  final bool hasPositiveGrowth;

  const _NewStatCard({
    required this.title,
    required this.value,
    required this.subtext,
    this.hasPositiveGrowth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: const Color(0xFF6B7280),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              subtext,
              style: TextStyle(color: const Color(0xFF6B7280), fontSize: 12),
            ),
            if (hasPositiveGrowth) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_upward_rounded,
                size: 12,
                color: Color(0xFF00C853),
              ),
              const SizedBox(width: 4),
              const Text(
                '+12%',
                style: TextStyle(
                  color: Color(0xFF00C853),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ==============================================================================
// 2. FILTER + MEDICATION GRID (Items tab)
// ==============================================================================

class _FilteredMedicationSection extends StatefulWidget {
  final List<MedicationData> medications;
  final VoidCallback onAddMedicine;
  final ValueChanged<MedicineModel> onEditMedicine;
  final ValueChanged<MedicineModel> onOpenMedicineDetail;

  const _FilteredMedicationSection({
    required this.medications,
    required this.onAddMedicine,
    required this.onEditMedicine,
    required this.onOpenMedicineDetail,
  });

  @override
  State<_FilteredMedicationSection> createState() =>
      _FilteredMedicationSectionState();
}

class _FilteredMedicationSectionState
    extends State<_FilteredMedicationSection> {
  String _selectedFilter = 'All';

  List<MedicationData> get _filteredMedications {
    if (_selectedFilter == 'All') return widget.medications;
    return widget.medications
        .where((m) => m.status == _selectedFilter)
        .toList();
  }

  void _onFilterChanged(String filter) {
    setState(() {
      _selectedFilter = filter;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterRow(
          selectedFilter: _selectedFilter,
          onFilterChanged: _onFilterChanged,
          onAddMedicine: widget.onAddMedicine,
        ),
        const SizedBox(height: 24),
        Expanded(
          child: SingleChildScrollView(
            child: _MedicationGrid(
              medications: _filteredMedications,
              onEditMedicine: widget.onEditMedicine,
              onOpenMedicineDetail: widget.onOpenMedicineDetail,
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String selectedFilter;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onAddMedicine;

  const _FilterRow({
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.onAddMedicine,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _FilterTab(
                label: 'All',
                isActive: selectedFilter == 'All',
                onTap: () => onFilterChanged('All'),
              ),
              _FilterTab(
                label: 'Active',
                isActive: selectedFilter == 'Active',
                onTap: () => onFilterChanged('Active'),
              ),
              _FilterTab(
                label: 'Paused',
                isActive: selectedFilter == 'Paused',
                onTap: () => onFilterChanged('Paused'),
              ),
              _FilterTab(
                label: 'Finished',
                isActive: selectedFilter == 'Finished',
                onTap: () => onFilterChanged('Finished'),
              ),
            ],
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: onAddMedicine,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A1A),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(
            'Add Prescription',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.grey[600],
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _MedicationGrid extends StatelessWidget {
  final List<MedicationData> medications;
  final ValueChanged<MedicineModel> onEditMedicine;
  final ValueChanged<MedicineModel> onOpenMedicineDetail;

  const _MedicationGrid({
    required this.medications,
    required this.onEditMedicine,
    required this.onOpenMedicineDetail,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth = (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: medications.map((med) {
            return SizedBox(
              width: cardWidth,
              child: _MedicationCard(
                medication: med,
                onEdit: () {
                  if (med.originalMedicine != null) {
                    onEditMedicine(med.originalMedicine!);
                  }
                },
                onTap: () {
                  if (med.originalMedicine != null) {
                    onOpenMedicineDetail(med.originalMedicine!);
                  }
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ==============================================================================
// 3. MEDICATION CARD (now tappable and with edit icon)
// ==============================================================================

class _MedicationCard extends StatelessWidget {
  final MedicationData medication;
  final VoidCallback onEdit;
  final VoidCallback onTap;

  const _MedicationCard({
    required this.medication,
    required this.onEdit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPaused = medication.isPaused;
    final Color statusColor = isPaused
        ? const Color(0xFFFFA000)
        : const Color(0xFF00C853);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.medication,
                    color: Color(0xFFD17A28),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medication.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        medication.subtitle,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      medication.status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
                  onPressed: onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  medication.dose,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const Spacer(),
                Text(
                  medication.daysLeft,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _StripedProgressBar(
              value: medication.progress,
              color: medication.progressColor,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Synced from',
                        style: TextStyle(color: Colors.grey[400], fontSize: 10),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        medication.synced,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next dose',
                        style: TextStyle(color: Colors.grey[400], fontSize: 10),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        medication.nextDose,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: medication.buttonFilled
                        ? const Color(0xFF1A1A1A)
                        : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: medication.buttonFilled
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                            ),
                          ],
                  ),
                  child: Icon(
                    Icons.arrow_outward_rounded,
                    size: 16,
                    color: medication.buttonFilled
                        ? Colors.white
                        : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
              color: Colors.grey[200],
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
// 4. SCROLLABLE ALERTS PANEL
// ==============================================================================

class _ScrollableAlertsPanel extends StatelessWidget {
  final List<AlertData> alerts;

  const _ScrollableAlertsPanel({required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Alerts',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.more_horiz,
                  size: 20,
                  color: Color(0xFF4B5563),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: alerts.length,
              itemBuilder: (context, index) {
                final alert = alerts[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index < alerts.length - 1 ? 8 : 0,
                  ),
                  child: _AlertItem(alert: alert),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  final AlertData alert;

  const _AlertItem({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: alert.bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(alert.icon, size: 16, color: alert.iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF1F2937),
                  ),
                ),
                if (alert.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    alert.subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              alert.actionLabel,
              style: const TextStyle(
                color: Color(0xFF673AB7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// 5. PLACEHOLDER SCREENS FOR OTHER TABS
// ==============================================================================

class _VendorsPlaceholder extends StatelessWidget {
  const _VendorsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScreen(
      icon: Icons.storefront_outlined,
      title: 'Vendors',
      message: 'Vendor management will appear here.',
    );
  }
}

class _OrdersPlaceholder extends StatelessWidget {
  const _OrdersPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScreen(
      icon: Icons.receipt_long_outlined,
      title: 'Orders',
      message: 'Purchase orders and requests will appear here.',
    );
  }
}

class _UsageAnalyticsPlaceholder extends StatelessWidget {
  const _UsageAnalyticsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScreen(
      icon: Icons.insights_outlined,
      title: 'Usage Analytics',
      message: 'Consumption trends and reports will appear here.',
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
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}