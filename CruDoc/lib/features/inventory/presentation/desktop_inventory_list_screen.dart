import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';
import 'package:doctor_management_app/features/inventory/presentation/add_edit_medicine_form.dart';
import 'package:doctor_management_app/features/inventory/presentation/medicine_detail_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/stock_adjustment_dialog.dart';

/// Rupee currency formatter
final _currencyFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String _formatCurrency(double value) => _currencyFormatter.format(value);

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
  inventoryValue: '₹0',
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

    final transactionsAsync = ref.watch(recentStockTransactionsProvider);
    final transactions =
        transactionsAsync.value ?? const <StockTransactionModel>[];
    final medicineById = <String, MedicineModel>{
      for (final med in inventoryViewData.medications)
        if (med.originalMedicine != null)
          med.originalMedicine!.id: med.originalMedicine!,
    };
    final monthlyUsageStat = _computeMonthlyUsageStat(
      transactions,
      medicineById,
    );

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
              monthlyUsage: monthlyUsageStat.value,
              monthlyUsageGrowthLabel: monthlyUsageStat.growthLabel,
              monthlyUsageGrowthPositive: monthlyUsageStat.growthPositive,
              medications: inventoryViewData.medications,
              alerts: inventoryViewData.alerts,
              transactions: transactions,
              medicineById: medicineById,
              repository: repository,
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

  final inventoryValue = hasAnyPrice ? _formatCurrency(inventoryTotal) : '₹0';

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
// MONTHLY USAGE STAT
// -----------------------------------------------------------------------------

class _MonthlyUsageStat {
  final String value;
  final String? growthLabel;
  final bool growthPositive;

  const _MonthlyUsageStat({
    required this.value,
    this.growthLabel,
    this.growthPositive = true,
  });
}

_MonthlyUsageStat _computeMonthlyUsageStat(
  List<StockTransactionModel> transactions,
  Map<String, MedicineModel> medicineById,
) {
  final now = DateTime.now();
  final periodStart = now.subtract(const Duration(days: 30));
  final priorPeriodStart = now.subtract(const Duration(days: 60));

  double current = 0;
  double prior = 0;

  for (final tx in transactions) {
    if (tx.type != StockTransactionType.dispense) continue;
    final price = medicineById[tx.medicineId]?.unitPrice;
    if (price == null) continue;
    final value = price * tx.quantity;
    if (!tx.createdAt.isBefore(periodStart)) {
      current += value;
    } else if (!tx.createdAt.isBefore(priorPeriodStart)) {
      prior += value;
    }
  }

  String? growthLabel;
  bool growthPositive = true;
  if (prior > 0) {
    final change = ((current - prior) / prior) * 100;
    growthPositive = change >= 0;
    growthLabel = '${growthPositive ? '+' : ''}${change.toStringAsFixed(0)}%';
  } else if (current > 0) {
    growthLabel = 'New';
    growthPositive = true;
  }

  return _MonthlyUsageStat(
    value: _formatCurrency(current),
    growthLabel: growthLabel,
    growthPositive: growthPositive,
  );
}

// -----------------------------------------------------------------------------
// DATA MODELS
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
// MAIN DASHBOARD VIEW
// ==============================================================================

class _InventoryDashboardView extends StatefulWidget {
  final String totalItems;
  final String lowStockAlerts;
  final String outOfStock;
  final String inventoryValue;
  final String monthlyUsage;
  final String? monthlyUsageGrowthLabel;
  final bool monthlyUsageGrowthPositive;
  final List<MedicationData> medications;
  final List<AlertData> alerts;
  final List<StockTransactionModel> transactions;
  final Map<String, MedicineModel> medicineById;
  final InventoryRepository repository;
  final VoidCallback onAddMedicine;
  final ValueChanged<MedicineModel> onEditMedicine;
  final ValueChanged<MedicineModel> onOpenMedicineDetail;

  const _InventoryDashboardView({
    required this.totalItems,
    required this.lowStockAlerts,
    required this.outOfStock,
    required this.inventoryValue,
    required this.monthlyUsage,
    this.monthlyUsageGrowthLabel,
    this.monthlyUsageGrowthPositive = true,
    required this.medications,
    required this.alerts,
    required this.transactions,
    required this.medicineById,
    required this.repository,
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
          monthlyUsageGrowthLabel: widget.monthlyUsageGrowthLabel,
          monthlyUsageGrowthPositive: widget.monthlyUsageGrowthPositive,
          onAddMedicine: widget.onAddMedicine,
          selectedTabIndex: _selectedTabIndex,
          tabLabels: _tabLabels,
          onTabSelected: (index) => setState(() => _selectedTabIndex = index),
        ),
        const SizedBox(height: 32),
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildItemsTab();
      case 1:
        return _VendorsTab(
          medications: widget.medications,
          onEditMedicine: widget.onEditMedicine,
          onOpenMedicineDetail: widget.onOpenMedicineDetail,
        );
      case 2:
        return _OrdersTab(
          medications: widget.medications,
          transactions: widget.transactions,
          repository: widget.repository,
          onOpenMedicineDetail: widget.onOpenMedicineDetail,
        );
      case 3:
        return _UsageAnalyticsTab(
          transactions: widget.transactions,
          medicineById: widget.medicineById,
        );
      default:
        return _buildItemsTab();
    }
  }

  Widget _buildItemsTab() {
    void openRestockDialog(MedicineModel medicine) {
      showStockAdjustmentDialog(
        context,
        medicine: medicine,
        repository: widget.repository,
      );
    }

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
                  onRestockMedicine: openRestockDialog,
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
                  onRestockMedicine: openRestockDialog,
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
// 1. HEADER
// ==============================================================================

class _InventoryHeaderSection extends StatelessWidget {
  final String totalItems;
  final String lowStockAlerts;
  final String outOfStock;
  final String inventoryValue;
  final String monthlyUsage;
  final String? monthlyUsageGrowthLabel;
  final bool monthlyUsageGrowthPositive;
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
    this.monthlyUsageGrowthLabel,
    this.monthlyUsageGrowthPositive = true,
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
        if (selectedTabIndex == 0)
          Row(
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
                  subtext: 'dispensed value · 30d',
                  growthLabel: monthlyUsageGrowthLabel,
                  growthPositive: monthlyUsageGrowthPositive,
                ),
              ),
            ],
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
  final String? growthLabel;
  final bool growthPositive;

  const _NewStatCard({
    required this.title,
    required this.value,
    required this.subtext,
    this.growthLabel,
    this.growthPositive = true,
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
            if (growthLabel != null) ...[
              const SizedBox(width: 8),
              Icon(
                growthPositive
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 12,
                color: growthPositive
                    ? const Color(0xFF00C853)
                    : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 4),
              Text(
                growthLabel!,
                style: TextStyle(
                  color: growthPositive
                      ? const Color(0xFF00C853)
                      : const Color(0xFFDC2626),
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
// 2. ITEMS TAB
// ==============================================================================

enum _InventorySortOption { nameAsc, stockLowHigh, stockHighLow, expirySoonest }

const List<String> _inventoryFilterOptions = [
  'All',
  'In stock',
  'Low stock',
  'Out of stock',
  'Expiring soon',
];

class _FilteredMedicationSection extends StatefulWidget {
  final List<MedicationData> medications;
  final VoidCallback onAddMedicine;
  final ValueChanged<MedicineModel> onEditMedicine;
  final ValueChanged<MedicineModel> onOpenMedicineDetail;
  final ValueChanged<MedicineModel> onRestockMedicine;

  const _FilteredMedicationSection({
    required this.medications,
    required this.onAddMedicine,
    required this.onEditMedicine,
    required this.onOpenMedicineDetail,
    required this.onRestockMedicine,
  });

  @override
  State<_FilteredMedicationSection> createState() =>
      _FilteredMedicationSectionState();
}

class _FilteredMedicationSectionState
    extends State<_FilteredMedicationSection> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  String _searchQuery = '';
  _InventorySortOption _sortOption = _InventorySortOption.nameAsc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesFilter(MedicationData m) {
    final original = m.originalMedicine;
    switch (_selectedFilter) {
      case 'In stock':
        return original != null &&
            !original.isLowStock &&
            original.currentStock > 0;
      case 'Low stock':
        return original?.isLowStock ?? false;
      case 'Out of stock':
        return original?.currentStock == 0;
      case 'Expiring soon':
        return m.status == 'Expiring';
      case 'All':
      default:
        return true;
    }
  }

  bool _matchesSearch(MedicationData m) {
    if (_searchQuery.isEmpty) return true;
    final query = _searchQuery.toLowerCase();
    return m.name.toLowerCase().contains(query) ||
        m.subtitle.toLowerCase().contains(query) ||
        (m.originalMedicine?.supplierName?.toLowerCase().contains(query) ??
            false);
  }

  List<MedicationData> get _filteredMedications {
    final result = widget.medications
        .where(_matchesFilter)
        .where(_matchesSearch)
        .toList();
    result.sort((a, b) {
      switch (_sortOption) {
        case _InventorySortOption.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _InventorySortOption.stockLowHigh:
          return (a.originalMedicine?.currentStock ?? 0).compareTo(
            b.originalMedicine?.currentStock ?? 0,
          );
        case _InventorySortOption.stockHighLow:
          return (b.originalMedicine?.currentStock ?? 0).compareTo(
            a.originalMedicine?.currentStock ?? 0,
          );
        case _InventorySortOption.expirySoonest:
          final aDate = a.originalMedicine?.expiryDate;
          final bDate = b.originalMedicine?.expiryDate;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return aDate.compareTo(bDate);
      }
    });
    return result;
  }

  void _onFilterChanged(String filter) =>
      setState(() => _selectedFilter = filter);
  void _onSearchChanged(String value) =>
      setState(() => _searchQuery = value.trim());
  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedFilter = 'All';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.medications.isEmpty) {
      return _PlaceholderScreen(
        icon: Icons.inventory_2_outlined,
        title: 'No items yet',
        message: 'Add your first medicine to start tracking stock levels.',
        actionLabel: 'Add item',
        onAction: widget.onAddMedicine,
      );
    }

    final filtered = _filteredMedications;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterRow(
          selectedFilter: _selectedFilter,
          onFilterChanged: _onFilterChanged,
          searchController: _searchController,
          searchQuery: _searchQuery,
          onSearchChanged: _onSearchChanged,
          onClearSearch: _clearSearch,
          sortOption: _sortOption,
          onSortChanged: (option) => setState(() => _sortOption = option),
        ),
        const SizedBox(height: 12),
        Text(
          'Showing ${filtered.length} of ${widget.medications.length} item${widget.medications.length == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? _PlaceholderScreen(
                  icon: Icons.search_off_rounded,
                  title: 'No items match',
                  message:
                      'Try a different search term or clear the current filter.',
                  actionLabel: 'Clear filters',
                  onAction: _clearAllFilters,
                )
              : SingleChildScrollView(
                  child: _MedicationGrid(
                    medications: filtered,
                    onEditMedicine: widget.onEditMedicine,
                    onOpenMedicineDetail: widget.onOpenMedicineDetail,
                    onRestockMedicine: widget.onRestockMedicine,
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
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final _InventorySortOption sortOption;
  final ValueChanged<_InventorySortOption> onSortChanged;

  const _FilterRow({
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.sortOption,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in _inventoryFilterOptions)
                _FilterTab(
                  label: option,
                  isActive: selectedFilter == option,
                  onTap: () => onFilterChanged(option),
                ),
            ],
          ),
        ),
        Container(
          width: 240,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: const InputDecoration(
                    hintText: 'Search items or vendor...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.clear,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  onPressed: onClearSearch,
                ),
            ],
          ),
        ),
        _InventorySortButton(
          currentOption: sortOption,
          onSelected: onSortChanged,
        ),
      ],
    );
  }
}

class _InventorySortButton extends StatelessWidget {
  final _InventorySortOption currentOption;
  final ValueChanged<_InventorySortOption> onSelected;

  const _InventorySortButton({
    required this.currentOption,
    required this.onSelected,
  });

  String get _label {
    switch (currentOption) {
      case _InventorySortOption.nameAsc:
        return 'Name A-Z';
      case _InventorySortOption.stockLowHigh:
        return 'Stock: Low-High';
      case _InventorySortOption.stockHighLow:
        return 'Stock: High-Low';
      case _InventorySortOption.expirySoonest:
        return 'Expiry: Soonest';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_InventorySortOption>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _InventorySortOption.nameAsc,
          child: Text('Name A-Z'),
        ),
        const PopupMenuItem(
          value: _InventorySortOption.stockLowHigh,
          child: Text('Stock: Low to High'),
        ),
        const PopupMenuItem(
          value: _InventorySortOption.stockHighLow,
          child: Text('Stock: High to Low'),
        ),
        const PopupMenuItem(
          value: _InventorySortOption.expirySoonest,
          child: Text('Expiry: Soonest first'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              _label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.grey),
          ],
        ),
      ),
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
  final ValueChanged<MedicineModel> onRestockMedicine;

  const _MedicationGrid({
    required this.medications,
    required this.onEditMedicine,
    required this.onOpenMedicineDetail,
    required this.onRestockMedicine,
  });

  static const double _spacing = 16;

  int _columnsForWidth(double width) {
    if (width >= 1400) return 4;
    if (width >= 1000) return 3;
    if (width >= 620) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int columns = _columnsForWidth(constraints.maxWidth);
        final double cardWidth =
            (constraints.maxWidth - _spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: medications.map((med) {
            return SizedBox(
              width: cardWidth,
              child: _MedicationCard(
                medication: med,
                onEdit: () {
                  if (med.originalMedicine != null)
                    onEditMedicine(med.originalMedicine!);
                },
                onTap: () {
                  if (med.originalMedicine != null)
                    onOpenMedicineDetail(med.originalMedicine!);
                },
                onRestock: () {
                  if (med.originalMedicine != null)
                    onRestockMedicine(med.originalMedicine!);
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final MedicationData medication;
  final VoidCallback onEdit;
  final VoidCallback onTap;
  final VoidCallback onRestock;

  const _MedicationCard({
    required this.medication,
    required this.onEdit,
    required this.onTap,
    required this.onRestock,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPaused = medication.isPaused;
    final Color statusColor = isPaused
        ? const Color(0xFFFFA000)
        : const Color(0xFF00C853);
    final MedicineModel? original = medication.originalMedicine;
    final String? supplier = original?.supplierName?.trim();
    final String vendorValue = (supplier == null || supplier.isEmpty)
        ? 'No vendor'
        : supplier;
    final bool hasPrice = original?.unitPrice != null;
    final String secondaryLabel = hasPrice ? 'Unit price' : 'Batch';
    final String secondaryValue = hasPrice
        ? _formatCurrency(original!.unitPrice!)
        : (original?.batchNumber?.trim().isNotEmpty ?? false)
        ? original!.batchNumber!
        : '—';

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
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Colors.grey,
                  ),
                  onPressed: onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
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
                        'Vendor',
                        style: TextStyle(color: Colors.grey[400], fontSize: 10),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vendorValue,
                        overflow: TextOverflow.ellipsis,
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
                        secondaryLabel,
                        style: TextStyle(color: Colors.grey[400], fontSize: 10),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        secondaryValue,
                        overflow: TextOverflow.ellipsis,
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
                Tooltip(
                  message: 'Restock',
                  child: GestureDetector(
                    onTap: onRestock,
                    child: Container(
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
                        Icons.add_rounded,
                        size: 18,
                        color: medication.buttonFilled
                            ? Colors.white
                            : Colors.grey[700],
                      ),
                    ),
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

List<_VendorSummary> _buildVendorSummaries(List<MedicationData> medications) {
  final grouped = <String, List<MedicationData>>{};
  for (final med in medications) {
    final supplier = med.originalMedicine?.supplierName?.trim();
    final key = (supplier == null || supplier.isEmpty)
        ? 'Unassigned'
        : supplier;
    grouped.putIfAbsent(key, () => []).add(med);
  }

  final summaries = <_VendorSummary>[];
  grouped.forEach((name, meds) {
    int lowStock = 0;
    int expiring = 0;
    double value = 0;
    bool hasKnownValue = false;
    for (final med in meds) {
      final original = med.originalMedicine;
      if (original == null) continue;
      if (original.isLowStock) lowStock += 1;
      if (original.isExpiringSoon) expiring += 1;
      if (original.unitPrice != null) {
        hasKnownValue = true;
        value += original.unitPrice! * original.currentStock;
      }
    }
    summaries.add(
      _VendorSummary(
        name: name,
        itemCount: meds.length,
        lowStockCount: lowStock,
        expiringCount: expiring,
        stockValue: value,
        hasKnownValue: hasKnownValue,
        medications: meds,
      ),
    );
  });

  summaries.sort((a, b) {
    if (a.name == 'Unassigned') return 1;
    if (b.name == 'Unassigned') return -1;
    return b.stockValue.compareTo(a.stockValue);
  });

  return summaries;
}

class _VendorsTab extends StatefulWidget {
  final List<MedicationData> medications;
  final ValueChanged<MedicineModel> onEditMedicine;
  final ValueChanged<MedicineModel> onOpenMedicineDetail;

  const _VendorsTab({
    required this.medications,
    required this.onEditMedicine,
    required this.onOpenMedicineDetail,
  });

  @override
  State<_VendorsTab> createState() => _VendorsTabState();
}

class _VendorsTabState extends State<_VendorsTab> {
  String _searchQuery = '';
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    // 1. Vendor Dashboard Header
    final vendors = _buildVendorSummaries(widget.medications);
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
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vendor Health',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 12),
              if (vendors.isEmpty)
                const Text(
                  'No vendor data yet',
                  style: TextStyle(color: Colors.grey),
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
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    v.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  _StripedProgressBar(
                                    value: totalValue > 0
                                        ? (v.stockValue / totalValue).clamp(
                                            0.0,
                                            1.0,
                                          )
                                        : 0.0,
                                    color: v.lowStockCount > 0
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _formatCurrency(v.stockValue),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 300,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: const InputDecoration(
                  hintText: 'Search vendors...',
                  icon: Icon(Icons.search, size: 18, color: Colors.grey),
                  border: InputBorder.none,
                ),
              ),
            ),
            Row(
              children: [
                _FilterChip(
                  label: 'All',
                  active: _filter == 'All',
                  onTap: () => setState(() => _filter = 'All'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Low Stock',
                  active: _filter == 'Low Stock',
                  onTap: () => setState(() => _filter = 'Low Stock'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Expiring',
                  active: _filter == 'Expiring',
                  onTap: () => setState(() => _filter = 'Expiring'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // List of Vendor Cards
        Expanded(
          child: ListView.separated(
            itemCount: filteredVendors.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
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
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1F2937) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? Colors.transparent : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : Colors.grey[600],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
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
                      ? Colors.grey.shade100
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isUnassigned
                      ? Icons.help_outline_rounded
                      : Icons.storefront_rounded,
                  size: 20,
                  color: isUnassigned
                      ? Colors.grey.shade500
                      : const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUnassigned ? 'No vendor assigned' : vendor.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${vendor.itemCount} item${vendor.itemCount == 1 ? '' : 's'}${vendor.hasKnownValue ? ' · ${_formatCurrency(vendor.stockValue)} in stock' : ''}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (vendor.lowStockCount > 0) ...[
                _VendorCountBadge(
                  label: '${vendor.lowStockCount} low',
                  color: Colors.red.shade700,
                  backgroundColor: Colors.red.shade50,
                ),
                const SizedBox(width: 6),
              ],
              if (vendor.expiringCount > 0)
                _VendorCountBadge(
                  label: '${vendor.expiringCount} exp',
                  color: Colors.orange.shade700,
                  backgroundColor: Colors.orange.shade50,
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
                  if (isUnassigned)
                    onEditMedicine(original);
                  else
                    onOpenMedicineDetail(original);
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
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (!isUnassigned)
                TextButton.icon(
                  onPressed: () {}, // Mock action for adding item to vendor
                  icon: const Icon(Icons.add_shopping_cart, size: 14),
                  label: const Text('Add Item', style: TextStyle(fontSize: 12)),
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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
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
        ? Colors.red.shade600
        : isExpiring
        ? Colors.orange.shade700
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(20),
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
              style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
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
            separatorBuilder: (_, __) => const SizedBox(height: 10),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOut ? Colors.red.shade100 : Colors.grey.shade200,
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF1F2937),
                          ),
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
                          color: isOut
                              ? Colors.red.shade50
                              : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isOut ? 'Out of stock' : 'Low stock',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isOut
                                ? Colors.red.shade700
                                : Colors.amber.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _StripedProgressBar(
                    value: reorderProgress,
                    color: isOut ? Colors.red : Colors.amber,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${medicine.currentStock} ${medicine.unit} left · Suggest +${suggestion.suggestedQty} ${medicine.unit}'
                    '${suggestion.estimatedCost != null ? ' (${_formatCurrency(suggestion.estimatedCost!)})' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (daysSinceRestock != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 12,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          daysSinceRestock == 0
                              ? 'Restocked today'
                              : 'Restocked ${daysSinceRestock}d ago',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
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
              backgroundColor: const Color(0xFF1F2937),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Restock',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
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
          if (dayIndex >= 0 && dayIndex < 7)
            dailyBuckets[dayIndex] += tx.quantity;
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
              const Text(
                'Usage Analytics',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Top Dispensed Items',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent stock activity',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dispensed Volume',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
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
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 120 * heightFactor + 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
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
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.grey[500],
                          ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Category Breakdown',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),
          if (categories.isEmpty)
            const Text(
              'No category data yet',
              style: TextStyle(color: Colors.grey),
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
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StripedProgressBar(
                        value: (entry.value / maxValue).clamp(0.0, 1.0),
                        color: Colors.purple.shade300,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _formatCurrency(entry.value),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sublabel,
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${usage.quantity} units · ${_formatCurrency(usage.quantity * unitValue)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _StripedProgressBar(value: progress, color: const Color(0xFF2563EB)),
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
    final color = _isIncrease ? const Color(0xFF00C853) : Colors.grey.shade700;

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
              style: const TextStyle(fontSize: 12, color: Color(0xFF1F2937)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${_isIncrease ? '+' : '-'}${transaction.quantity} · $dateLabel',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
  final String? actionLabel;
  final VoidCallback? onAction;

  const _PlaceholderScreen({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
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
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F2937),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
