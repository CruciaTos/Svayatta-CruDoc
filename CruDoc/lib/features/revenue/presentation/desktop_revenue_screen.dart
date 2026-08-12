import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/errors/revenue_exceptions.dart';

const _emptyFinancialDashboardData = _FinancialDashboardViewData(
  revenue: '₹0',
  expenses: '₹0',
  profit: '₹0',
  outstandingInvoices: '₹0',
  invoiceSubtitle: '0 invoices this period',
  outstandingSubtitle: '0 unpaid invoices',
  recentTransactions: <_TransactionData>[],
  structures: <_StructureData>[],
  weeklyData: _WeeklyFinancialData(
    labels: <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    dates: <DateTime>[],
    revenue: <double>[0, 0, 0, 0, 0, 0, 0],
    expenses: <double>[0, 0, 0, 0, 0, 0, 0],
    profit: <double>[0, 0, 0, 0, 0, 0, 0],
  ),
  allInvoices: <InvoiceModel>[],
);

final _currencyFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String _formatCurrency(double value) => _currencyFormatter.format(value);

enum FinancialRange { week, month, threeMonths, twelveMonths }

extension FinancialRangeExtension on FinancialRange {
  String get label {
    switch (this) {
      case FinancialRange.week:
        return 'This week';
      case FinancialRange.month:
        return 'This month';
      case FinancialRange.threeMonths:
        return 'Last 3 months';
      case FinancialRange.twelveMonths:
        return 'Last 12 months';
    }
  }
}

_FinancialDashboardViewData _mapInvoicesToFinancialData(
  List<InvoiceModel> invoices,
  FinancialRange range,
) {
  final now = DateTime.now();
  DateTime startDate;
  List<DateTime> dates;
  List<String> labels;
  int pointCount;

  switch (range) {
    case FinancialRange.week:
      startDate = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));
      pointCount = 7;
      dates = List.generate(pointCount, (i) => startDate.add(Duration(days: i)));
      labels = dates.map((d) => DateFormat('E').format(d)).toList();
      break;
    case FinancialRange.month:
      startDate = DateTime(now.year, now.month, 1);
      pointCount = DateTime(now.year, now.month + 1, 0).day;
      dates = List.generate(pointCount, (i) => startDate.add(Duration(days: i)));
      labels = dates.map((d) => d.day.toString()).toList();
      break;
    case FinancialRange.threeMonths:
      startDate = DateTime(now.year, now.month - 2, 1);
      pointCount = 3;
      dates = List.generate(pointCount, (i) => DateTime(startDate.year, startDate.month + i, 1));
      labels = dates.map((d) => DateFormat('MMM').format(d)).toList();
      break;
    case FinancialRange.twelveMonths:
      startDate = DateTime(now.year, now.month - 11, 1);
      pointCount = 12;
      dates = List.generate(pointCount, (i) => DateTime(startDate.year, startDate.month + i, 1));
      labels = dates.map((d) => DateFormat('MMM yy').format(d)).toList();
      break;
  }

  final weekRevenue = List<double>.filled(pointCount, 0);
  final weekExpenses = List<double>.filled(pointCount, 0);
  final weekProfit = List<double>.filled(pointCount, 0);

  double paidTotal = 0;
  double outstandingTotal = 0;
  int unpaidCount = 0;
  int invoicesThisPeriod = 0;
  final serviceTotals = <String, double>{};
  final filteredInvoices = <InvoiceModel>[];

  for (final invoice in invoices) {
    final invoiceDate = DateTime(invoice.date.year, invoice.date.month, invoice.date.day);
    if (invoiceDate.isBefore(startDate) || invoiceDate.isAfter(now)) continue;

    filteredInvoices.add(invoice);
    invoicesThisPeriod++;

    if (invoice.isPaid) {
      paidTotal += invoice.amount;
    } else {
      outstandingTotal += invoice.amount;
      unpaidCount++;
    }

    int index;
    switch (range) {
      case FinancialRange.week:
        index = invoiceDate.difference(startDate).inDays;
        break;
      case FinancialRange.month:
        index = invoiceDate.day - 1;
        break;
      case FinancialRange.threeMonths:
        index = invoiceDate.month - startDate.month;
        break;
      case FinancialRange.twelveMonths:
        index = (invoiceDate.year - startDate.year) * 12 + (invoiceDate.month - startDate.month);
        break;
    }
    if (index >= 0 && index < pointCount) {
      if (invoice.isPaid) {
        weekRevenue[index] += invoice.amount;
      }
    }

    if (invoice.isPaid) {
      final category = _categoryForService(invoice.service);
      serviceTotals.update(
        category,
        (value) => value + invoice.amount,
        ifAbsent: () => invoice.amount,
      );
    }
  }

  for (var i = 0; i < pointCount; i++) {
    weekProfit[i] = weekRevenue[i] - weekExpenses[i];
  }

  final structures = serviceTotals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final structureTotal = structures.fold<double>(
    0,
    (sum, entry) => sum + entry.value,
  );
  final colors = <Color>[
    const Color(0xFF7B61FF),
    const Color(0xFFBDA6FF),
    const Color(0xFFE2D5FF),
    const Color(0xFFFFAA00),
  ];

  return _FinancialDashboardViewData(
    revenue: _formatCurrency(paidTotal),
    expenses: _formatCurrency(0),
    profit: _formatCurrency(paidTotal),
    outstandingInvoices: _formatCurrency(outstandingTotal),
    invoiceSubtitle: '$invoicesThisPeriod invoices this period',
    outstandingSubtitle: '$unpaidCount unpaid invoices',
    recentTransactions: List.unmodifiable(
      filteredInvoices.take(6).map(_mapInvoiceToTransaction),
    ),
    structures: List.unmodifiable(
      structures.take(4).toList().asMap().entries.map((entry) {
        final value = entry.value.value;
        return _StructureData(
          label: entry.value.key,
          amount: _formatCurrency(value),
          percent: structureTotal <= 0
              ? 0
              : ((value / structureTotal) * 100).round(),
          color: colors[entry.key % colors.length],
        );
      }),
    ),
    weeklyData: _WeeklyFinancialData(
      labels: labels,
      dates: dates,
      revenue: weekRevenue,
      expenses: weekExpenses,
      profit: weekProfit,
    ),
    allInvoices: List.unmodifiable(filteredInvoices),
  );
}

String _categoryForService(String rawService) {
  final service = rawService.trim();
  if (service.isEmpty) return 'Clinical services';
  if (service.length <= 24) return service;
  return '${service.substring(0, 21)}...';
}

_TransactionData _mapInvoiceToTransaction(InvoiceModel invoice) {
  final statusColor = invoice.isPaid
      ? const Color(0xFF00C853)
      : (invoice.isOverdue ? const Color(0xFFFF1744) : const Color(0xFFFFAA00));
  return _TransactionData(
    name: invoice.patientName.isEmpty ? 'General Patient' : invoice.patientName,
    type: invoice.service.isEmpty
        ? invoice.status
        : '${invoice.service} • ${invoice.status}',
    amount: _formatCurrency(invoice.amount),
    date: DateFormat('MMM d, h:mm a').format(invoice.date),
    icon: invoice.isPaid ? Icons.person : Icons.receipt_long_outlined,
    color: statusColor,
    isIncome: invoice.isPaid,
  );
}

// -----------------------------------------------------------------------------
// VIEW DATA MODELS
// -----------------------------------------------------------------------------

class _FinancialDashboardViewData {
  final String revenue;
  final String expenses;
  final String profit;
  final String outstandingInvoices;
  final String invoiceSubtitle;
  final String outstandingSubtitle;
  final List<_TransactionData> recentTransactions;
  final List<_StructureData> structures;
  final _WeeklyFinancialData weeklyData;
  final List<InvoiceModel> allInvoices;

  const _FinancialDashboardViewData({
    required this.revenue,
    required this.expenses,
    required this.profit,
    required this.outstandingInvoices,
    required this.invoiceSubtitle,
    required this.outstandingSubtitle,
    required this.recentTransactions,
    required this.structures,
    required this.weeklyData,
    required this.allInvoices,
  });
}

class _WeeklyFinancialData {
  final List<String> labels;
  final List<DateTime> dates;
  final List<double> revenue;
  final List<double> expenses;
  final List<double> profit;

  const _WeeklyFinancialData({
    required this.labels,
    required this.dates,
    required this.revenue,
    required this.expenses,
    required this.profit,
  });
}

class _TransactionData {
  final String name;
  final String type;
  final String amount;
  final String date;
  final IconData icon;
  final Color color;
  final bool isIncome;

  const _TransactionData({
    required this.name,
    required this.type,
    required this.amount,
    required this.date,
    required this.icon,
    required this.color,
    required this.isIncome,
  });
}

class _StructureData {
  final String label;
  final String amount;
  final int percent;
  final Color color;

  const _StructureData({
    required this.label,
    required this.amount,
    required this.percent,
    required this.color,
  });
}

// -----------------------------------------------------------------------------
// SCREEN WIDGET
// -----------------------------------------------------------------------------

class DesktopRevenueScreen extends StatefulWidget {
  const DesktopRevenueScreen({super.key});

  @override
  State<DesktopRevenueScreen> createState() => _DesktopRevenueScreenState();
}

class _DesktopRevenueScreenState extends State<DesktopRevenueScreen> {
  final InvoiceRepository _invoiceRepository = InvoiceRepository();
  final RevenueRepository _revenueRepository = RevenueRepository();
  final VisitRepository _visitRepository = VisitRepository();

  FinancialRange _selectedRange = FinancialRange.week;
  TransactionKind? _kindFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAddTransactionSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _TransactionFormSheet(
        includeKindToggle: true,
        includePayerField: true,
        title: 'Add Transaction',
      ),
    );
  }

  void _openAddPendingSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _TransactionFormSheet(
        includeKindToggle: false,
        includePayerField: false,
        title: 'Add Pending Payment',
      ),
    );
  }

  void _openPendingPaymentDetails(PendingPayment pending) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _PendingPaymentDetailsSheet(pending: pending),
    );
  }

  Future<void> _markAsPaid(PendingPayment pending) async {
    try {
      await _visitRepository.markVisitationPaymentPaid(pending.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked "${pending.description}" as paid')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InvoiceModel>>(
      stream: _invoiceRepository.watchInvoices(),
      builder: (context, invoiceSnapshot) {
        final viewData = invoiceSnapshot.hasData
            ? _mapInvoicesToFinancialData(
                invoiceSnapshot.data ?? const <InvoiceModel>[],
                _selectedRange,
              )
            : _emptyFinancialDashboardData;

        return StreamBuilder<List<PendingPayment>>(
          stream: _revenueRepository.watchPendingPayments(),
          builder: (context, pendingSnapshot) {
            final pendingPayments =
                pendingSnapshot.data ?? const <PendingPayment>[];

            return StreamBuilder<List<RevenueEntry>>(
              stream: _revenueRepository.watchRevenueEntries(),
              builder: (context, entriesSnapshot) {
                final allEntries =
                    entriesSnapshot.data ?? const <RevenueEntry>[];
                final filteredEntries = _filterEntries(allEntries, _selectedRange);

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
                        child: _FinancialDashboardView(
                          viewData: viewData,
                          selectedRange: _selectedRange,
                          onRangeChanged: (range) =>
                              setState(() => _selectedRange = range),
                          pendingPayments: pendingPayments,
                          onAddPending: _openAddPendingSheet,
                          onPendingTap: _openPendingPaymentDetails,
                          onMarkPendingPaid: _markAsPaid,
                          onAddTransaction: _openAddTransactionSheet,
                          kindFilter: _kindFilter,
                          onKindFilterChanged: (kind) =>
                              setState(() => _kindFilter = kind),
                          searchController: _searchController,
                          searchQuery: _searchQuery,
                          onSearchChanged: (value) =>
                              setState(() => _searchQuery = value),
                          onClearSearch: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                          recentEntries: filteredEntries,
                        ),
                      ),
                    ),
                    if (invoiceSnapshot.hasError)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: _RevenueStatusBanner(
                          icon: Icons.error_outline_rounded,
                          message: 'Failed to load revenue data',
                          color: Colors.red.shade700,
                          backgroundColor: Colors.red.shade50,
                        ),
                      )
                    else if (invoiceSnapshot.connectionState ==
                        ConnectionState.waiting)
                      const Positioned(
                        top: 16,
                        right: 16,
                        child: _RevenueStatusBanner(
                          icon: Icons.sync_rounded,
                          message: 'Syncing revenue...',
                          color: Color(0xFF2563EB),
                          backgroundColor: Color(0xFFEFF6FF),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  List<RevenueEntry> _filterEntries(
      List<RevenueEntry> entries, FinancialRange range) {
    final now = DateTime.now();
    DateTime startDate;
    switch (range) {
      case FinancialRange.week:
        startDate = now.subtract(const Duration(days: 7));
        break;
      case FinancialRange.month:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case FinancialRange.threeMonths:
        startDate = DateTime(now.year, now.month - 2, 1);
        break;
      case FinancialRange.twelveMonths:
        startDate = DateTime(now.year - 1, now.month, now.day);
        break;
    }

    var filtered = entries.where((e) => e.date.isAfter(startDate)).toList();
    if (_kindFilter != null) {
      filtered = filtered.where((e) => e.kind == _kindFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((e) =>
              e.description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (e.payer != null &&
                  e.payer!.toLowerCase().contains(_searchQuery.toLowerCase())))
          .toList();
    }
    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }
}

class _RevenueStatusBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Color backgroundColor;

  const _RevenueStatusBanner({
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
// MAIN DASHBOARD VIEW
// -----------------------------------------------------------------------------

class _FinancialDashboardView extends StatefulWidget {
  final _FinancialDashboardViewData viewData;
  final FinancialRange selectedRange;
  final ValueChanged<FinancialRange> onRangeChanged;
  final List<PendingPayment> pendingPayments;
  final VoidCallback onAddPending;
  final ValueChanged<PendingPayment> onPendingTap;
  final ValueChanged<PendingPayment> onMarkPendingPaid;
  final VoidCallback onAddTransaction;
  final TransactionKind? kindFilter;
  final ValueChanged<TransactionKind?> onKindFilterChanged;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final List<RevenueEntry> recentEntries;

  const _FinancialDashboardView({
    required this.viewData,
    required this.selectedRange,
    required this.onRangeChanged,
    required this.pendingPayments,
    required this.onAddPending,
    required this.onPendingTap,
    required this.onMarkPendingPaid,
    required this.onAddTransaction,
    required this.kindFilter,
    required this.onKindFilterChanged,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.recentEntries,
  });

  @override
  State<_FinancialDashboardView> createState() => _FinancialDashboardViewState();
}

class _FinancialDashboardViewState extends State<_FinancialDashboardView> {
  int _selectedTabIndex = 0;

  static const _tabLabels = [
    'Overview',
    'Operations',
    'Source distribution',
    'Insurance',
    'Reports',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderSection(
            selectedRange: widget.selectedRange,
            onRangeChanged: widget.onRangeChanged,
            onAddTransaction: widget.onAddTransaction,
          ),
          const SizedBox(height: 24),
          _TabsSection(
            tabLabels: _tabLabels,
            selectedIndex: _selectedTabIndex,
            onTabSelected: (index) => setState(() => _selectedTabIndex = index),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _OverviewTab(
          viewData: widget.viewData,
          pendingPayments: widget.pendingPayments,
          onAddPending: widget.onAddPending,
          onPendingTap: widget.onPendingTap,
          onMarkPendingPaid: widget.onMarkPendingPaid,
          kindFilter: widget.kindFilter,
          onKindFilterChanged: widget.onKindFilterChanged,
          searchController: widget.searchController,
          searchQuery: widget.searchQuery,
          onSearchChanged: widget.onSearchChanged,
          onClearSearch: widget.onClearSearch,
          recentEntries: widget.recentEntries,
        );
      case 1:
        return _OperationsTab(invoices: widget.viewData.allInvoices);
      case 2:
        return _SourceDistributionTab(structures: widget.viewData.structures);
      case 3:
        return const _InsuranceTab();
      case 4:
        return _ReportsTab(viewData: widget.viewData);
      default:
        return _OverviewTab(
          viewData: widget.viewData,
          pendingPayments: widget.pendingPayments,
          onAddPending: widget.onAddPending,
          onPendingTap: widget.onPendingTap,
          onMarkPendingPaid: widget.onMarkPendingPaid,
          kindFilter: widget.kindFilter,
          onKindFilterChanged: widget.onKindFilterChanged,
          searchController: widget.searchController,
          searchQuery: widget.searchQuery,
          onSearchChanged: widget.onSearchChanged,
          onClearSearch: widget.onClearSearch,
          recentEntries: widget.recentEntries,
        );
    }
  }
}

// -----------------------------------------------------------------------------
// HEADER
// -----------------------------------------------------------------------------

class _HeaderSection extends StatelessWidget {
  final FinancialRange selectedRange;
  final ValueChanged<FinancialRange> onRangeChanged;
  final VoidCallback onAddTransaction;

  const _HeaderSection({
    required this.selectedRange,
    required this.onRangeChanged,
    required this.onAddTransaction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Finances',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
        Row(
          children: [
            PopupMenuButton<FinancialRange>(
              initialValue: selectedRange,
              onSelected: onRangeChanged,
              itemBuilder: (context) => FinancialRange.values
                  .map((range) => PopupMenuItem(
                        value: range,
                        child: Text(range.label),
                      ))
                  .toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      selectedRange.label,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: onAddTransaction,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Transaction'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.download_rounded, size: 20, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.settings_outlined, size: 20, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// TABS
// -----------------------------------------------------------------------------

class _TabsSection extends StatelessWidget {
  final List<String> tabLabels;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const _TabsSection({
    required this.tabLabels,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(tabLabels.length, (index) {
        final bool isActive = selectedIndex == index;
        return GestureDetector(
          onTap: () => onTabSelected(index),
          child: Padding(
            padding: const EdgeInsets.only(right: 24.0),
            child: Column(
              children: [
                Text(
                  tabLabels[index],
                  style: TextStyle(
                    color: isActive ? const Color(0xFF1A1A1A) : Colors.grey,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 2,
                  width: 40,
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF1A1A1A) : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// -----------------------------------------------------------------------------
// OVERVIEW TAB
// -----------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  final _FinancialDashboardViewData viewData;
  final List<PendingPayment> pendingPayments;
  final VoidCallback onAddPending;
  final ValueChanged<PendingPayment> onPendingTap;
  final ValueChanged<PendingPayment> onMarkPendingPaid;
  final TransactionKind? kindFilter;
  final ValueChanged<TransactionKind?> onKindFilterChanged;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final List<RevenueEntry> recentEntries;

  const _OverviewTab({
    required this.viewData,
    required this.pendingPayments,
    required this.onAddPending,
    required this.onPendingTap,
    required this.onMarkPendingPaid,
    required this.kindFilter,
    required this.onKindFilterChanged,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.recentEntries,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 250,
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search transactions...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: onClearSearch,
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StatsRow(viewData: viewData),
          const SizedBox(height: 24),
          _ChartSection(weeklyData: viewData.weeklyData),
          const SizedBox(height: 24),
          // Side-by-side panels: Recent Transactions LEFT, Pending Payments RIGHT
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isWide = constraints.maxWidth > 800;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Recent Transactions (left, wider)
                    Expanded(
                      flex: 2,
                      child: _RecentTransactionsPanel(
                        transactions: recentEntries
                            .map((e) => _TransactionData(
                                  name: e.payer ?? e.description,
                                  type: e.description,
                                  amount: _formatCurrency(e.amount),
                                  date: DateFormat('MMM d, h:mm a').format(e.date),
                                  icon: e.kind == TransactionKind.income
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  color: e.kind == TransactionKind.income
                                      ? Colors.green
                                      : Colors.red,
                                  isIncome: e.kind == TransactionKind.income,
                                ))
                            .toList(),
                        kindFilter: kindFilter,
                        onKindFilterChanged: onKindFilterChanged,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Pending Payments (right, narrower)
                    Expanded(
                      flex: 1,
                      child: _PendingPaymentsPanel(
                        pendingPayments: pendingPayments,
                        onAddPending: onAddPending,
                        onPendingTap: onPendingTap,
                        onMarkPendingPaid: onMarkPendingPaid,
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _RecentTransactionsPanel(
                      transactions: recentEntries
                          .map((e) => _TransactionData(
                                name: e.payer ?? e.description,
                                type: e.description,
                                amount: _formatCurrency(e.amount),
                                date: DateFormat('MMM d, h:mm a').format(e.date),
                                icon: e.kind == TransactionKind.income
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                color: e.kind == TransactionKind.income
                                    ? Colors.green
                                    : Colors.red,
                                isIncome: e.kind == TransactionKind.income,
                              ))
                          .toList(),
                      kindFilter: kindFilter,
                      onKindFilterChanged: onKindFilterChanged,
                    ),
                    const SizedBox(height: 16),
                    _PendingPaymentsPanel(
                      pendingPayments: pendingPayments,
                      onAddPending: onAddPending,
                      onPendingTap: onPendingTap,
                      onMarkPendingPaid: onMarkPendingPaid,
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PENDING PAYMENTS PANEL (smaller height)
// -----------------------------------------------------------------------------

class _PendingPaymentsPanel extends StatelessWidget {
  final List<PendingPayment> pendingPayments;
  final VoidCallback onAddPending;
  final ValueChanged<PendingPayment> onPendingTap;
  final ValueChanged<PendingPayment> onMarkPendingPaid;

  const _PendingPaymentsPanel({
    required this.pendingPayments,
    required this.onAddPending,
    required this.onPendingTap,
    required this.onMarkPendingPaid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300, // reduced from 400
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Pending Payments',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                TextButton.icon(
                  onPressed: onAddPending,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: pendingPayments.isEmpty
                ? Center(child: Text('No pending payments'))
                : ListView.builder(
                    itemCount: pendingPayments.length,
                    itemBuilder: (_, index) {
                      final pending = pendingPayments[index];
                      return GestureDetector(
                        onTap: () => onPendingTap(pending),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.1),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.hourglass_empty,
                                    size: 18, color: Colors.amber),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pending.description,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat.yMMMd().format(pending.date),
                                      style: TextStyle(
                                          color: Colors.grey[600], fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₹${pending.amount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.amber,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  GestureDetector(
                                    onTap: () => onMarkPendingPaid(pending),
                                    child: const Icon(Icons.check_circle_outline,
                                        size: 18, color: Color(0xFF4CAF50)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// RECENT TRANSACTIONS PANEL (kept height 400)
// -----------------------------------------------------------------------------

class _RecentTransactionsPanel extends StatelessWidget {
  final List<_TransactionData> transactions;
  final TransactionKind? kindFilter;
  final ValueChanged<TransactionKind?> onKindFilterChanged;

  const _RecentTransactionsPanel({
    required this.transactions,
    required this.kindFilter,
    required this.onKindFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Recent Transactions',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _KindFilterChip(
                  label: 'All',
                  selected: kindFilter == null,
                  onSelected: () => onKindFilterChanged(null),
                ),
                const SizedBox(width: 8),
                _KindFilterChip(
                  label: 'Income',
                  selected: kindFilter == TransactionKind.income,
                  selectedColor: Colors.green,
                  onSelected: () => onKindFilterChanged(TransactionKind.income),
                ),
                const SizedBox(width: 8),
                _KindFilterChip(
                  label: 'Expense',
                  selected: kindFilter == TransactionKind.expense,
                  selectedColor: Colors.red,
                  onSelected: () => onKindFilterChanged(TransactionKind.expense),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Text(
                      'No transactions found',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final transaction = transactions[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.1),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: transaction.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(transaction.icon,
                                  size: 18, color: transaction.color),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    transaction.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    transaction.type,
                                    style: TextStyle(
                                        color: Colors.grey[600], fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  transaction.amount,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: transaction.isIncome
                                        ? const Color(0xFF00C853)
                                        : const Color(0xFFFF1744),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  transaction.date,
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// KIND FILTER CHIP
// -----------------------------------------------------------------------------

class _KindFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? selectedColor;
  final VoidCallback onSelected;

  const _KindFilterChip({
    required this.label,
    required this.selected,
    this.selectedColor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = selectedColor ?? const Color(0xFF2196F3);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      backgroundColor: Colors.white,
      selectedColor: effectiveColor,
      side: BorderSide(
        color: selected ? effectiveColor : Colors.grey.shade300,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// STATS ROW
// -----------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  final _FinancialDashboardViewData viewData;

  const _StatsRow({required this.viewData});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = (constraints.maxWidth / 4) - 12;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatsCard(
              title: 'Revenue',
              amount: viewData.revenue,
              subtitle: viewData.invoiceSubtitle,
              percentage: 'Live',
              isPositive: true,
              width: width,
            ),
            _StatsCard(
              title: 'Expenses',
              amount: viewData.expenses,
              subtitle: 'tracked invoices only',
              percentage: '—',
              isPositive: true,
              width: width,
            ),
            _StatsCard(
              title: 'Profit',
              amount: viewData.profit,
              subtitle: 'paid invoices less expenses',
              percentage: 'Live',
              isPositive: true,
              width: width,
            ),
            _StatsCard(
              title: 'Outstanding Invoices',
              amount: viewData.outstandingInvoices,
              subtitle: viewData.outstandingSubtitle,
              percentage: 'Due',
              isPositive: false,
              width: width,
            ),
          ],
        );
      },
    );
  }
}

class _StatsCard extends StatelessWidget {
  final String title;
  final String amount;
  final String subtitle;
  final String percentage;
  final bool isPositive;
  final double width;

  const _StatsCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.percentage,
    required this.isPositive,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 12),
          Text(
            amount,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
              const SizedBox(width: 8),
              Icon(
                isPositive
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 14,
                color: isPositive
                    ? const Color(0xFF00C853)
                    : const Color(0xFFFF1744),
              ),
              const SizedBox(width: 4),
              Text(
                percentage,
                style: TextStyle(
                  color: isPositive
                      ? const Color(0xFF00C853)
                      : const Color(0xFFFF1744),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// CHART SECTION
// -----------------------------------------------------------------------------

class _ChartSection extends StatefulWidget {
  final _WeeklyFinancialData weeklyData;

  const _ChartSection({required this.weeklyData});

  @override
  State<_ChartSection> createState() => _ChartSectionState();
}

class _ChartSectionState extends State<_ChartSection> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Financial trends',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  _LegendItem(color: const Color(0xFF7B61FF), label: 'Revenue'),
                  const SizedBox(width: 16),
                  _LegendItem(
                    color: const Color(0xFFFFAA00),
                    label: 'Expenses',
                  ),
                  const SizedBox(width: 16),
                  _LegendItem(color: const Color(0xFF3F51B5), label: 'Profit'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final count = widget.weeklyData.revenue.length;
                final xPositions = List<double>.generate(count, (i) {
                  return count == 1 ? width / 2 : width * (i / (count - 1));
                });

                return MouseRegion(
                  onHover: (event) {
                    final localX = event.localPosition.dx;
                    if (count == 0) {
                      setState(() => _hoveredIndex = null);
                      return;
                    }
                    int nearest = 0;
                    double minDist = double.infinity;
                    for (int i = 0; i < count; i++) {
                      final dist = (xPositions[i] - localX).abs();
                      if (dist < minDist) {
                        minDist = dist;
                        nearest = i;
                      }
                    }
                    if (minDist < 20) {
                      setState(() => _hoveredIndex = nearest);
                    } else {
                      setState(() => _hoveredIndex = null);
                    }
                  },
                  onExit: (event) {
                    setState(() => _hoveredIndex = null);
                  },
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size(width, 200),
                        painter: _LineChartPainter(
                          width: width,
                          weeklyData: widget.weeklyData,
                        ),
                      ),
                      if (_hoveredIndex != null && count > 0) ...[
                        Positioned(
                          left: xPositions[_hoveredIndex!] - 4,
                          top: _yPosition(
                            widget.weeklyData.revenue[_hoveredIndex!],
                            widget.weeklyData,
                            200,
                          ) - 4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF7B61FF),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          left: xPositions[_hoveredIndex!] - 4,
                          top: _yPosition(
                            widget.weeklyData.expenses[_hoveredIndex!],
                            widget.weeklyData,
                            200,
                          ) - 4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFAA00),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          left: xPositions[_hoveredIndex!] - 4,
                          top: _yPosition(
                            widget.weeklyData.profit[_hoveredIndex!],
                            widget.weeklyData,
                            200,
                          ) - 4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF3F51B5),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          left: (xPositions[_hoveredIndex!] + 60) > width
                              ? xPositions[_hoveredIndex!] - 120
                              : xPositions[_hoveredIndex!] + 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1E2E),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _TooltipRow(
                                  color: const Color(0xFF7B61FF),
                                  text: _formatCurrency(
                                    widget.weeklyData.revenue[_hoveredIndex!],
                                  ),
                                ),
                                _TooltipRow(
                                  color: const Color(0xFFFFAA00),
                                  text: _formatCurrency(
                                    widget.weeklyData.expenses[_hoveredIndex!],
                                  ),
                                ),
                                _TooltipRow(
                                  color: const Color(0xFF3F51B5),
                                  text: _formatCurrency(
                                    widget.weeklyData.profit[_hoveredIndex!],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.weeklyData.dates.isEmpty
                                      ? 'No date'
                                      : DateFormat('EEE, MMM d, yyyy').format(
                                          widget.weeklyData.dates[_hoveredIndex!],
                                        ),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  double _yPosition(double value, _WeeklyFinancialData data, double height) {
    final maxValue = <double>[
      ...data.revenue,
      ...data.expenses,
      ...data.profit,
    ].fold<double>(0, (max, v) => v > max ? v : max);
    final chartMax = maxValue <= 0 ? 1.0 : maxValue;
    return (height - 22) - ((value / chartMax).clamp(0.0, 1.0) * (height - 42));
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
      ],
    );
  }
}

class _TooltipRow extends StatelessWidget {
  final Color color;
  final String text;

  const _TooltipRow({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final double width;
  final _WeeklyFinancialData weeklyData;

  _LineChartPainter({required this.width, required this.weeklyData});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint purplePaint = Paint()
      ..color = const Color(0xFF7B61FF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint orangePaint = Paint()
      ..color = const Color(0xFFFFAA00)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint bluePaint = Paint()
      ..color = const Color(0xFF3F51B5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint purpleFill = Paint()
      ..color = const Color(0xFF7B61FF).withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    final double w = size.width;
    final double h = size.height;
    final maxValue = <double>[
      ...weeklyData.revenue,
      ...weeklyData.expenses,
      ...weeklyData.profit,
    ].fold<double>(0, (max, value) => value > max ? value : max);
    final chartMax = maxValue <= 0 ? 1.0 : maxValue;

    Path buildSmoothPath(List<double> values) {
      final path = Path();
      final count = values.length;
      if (count == 0) return path;

      final points = List<Offset>.generate(count, (i) {
        final x = count == 1 ? 0.0 : w * (i / (count - 1));
        final y = (h - 22) - ((values[i] / chartMax).clamp(0.0, 1.0) * (h - 42));
        return Offset(x, y);
      });

      if (count == 1) {
        path.moveTo(points[0].dx, points[0].dy);
        path.lineTo(points[0].dx + 0.1, points[0].dy);
        return path;
      }

      path.moveTo(points[0].dx, points[0].dy);

      const double smoothness = 0.25;

      for (int i = 0; i < count - 1; i++) {
        final p0 = points[i > 0 ? i - 1 : 0];
        final p1 = points[i];
        final p2 = points[i + 1];
        final p3 = points[i + 2 < count ? i + 2 : count - 1];

        final control1 = Offset(
          p1.dx + (p2.dx - p0.dx) * smoothness,
          p1.dy + (p2.dy - p0.dy) * smoothness,
        );
        final control2 = Offset(
          p2.dx - (p3.dx - p1.dx) * smoothness,
          p2.dy - (p3.dy - p1.dy) * smoothness,
        );

        path.cubicTo(
          control1.dx,
          control1.dy,
          control2.dx,
          control2.dy,
          p2.dx,
          p2.dy,
        );
      }
      return path;
    }

    final Path pathPurple = buildSmoothPath(weeklyData.revenue);
    final Path pathOrange = buildSmoothPath(weeklyData.expenses);
    final Path pathBlue = buildSmoothPath(weeklyData.profit);

    if (weeklyData.revenue.isNotEmpty) {
      final Path fillPurple = Path.from(pathPurple);
      fillPurple.lineTo(w, h);
      fillPurple.lineTo(0, h);
      fillPurple.close();
      canvas.drawPath(fillPurple, purpleFill);
    }

    canvas.drawPath(pathPurple, purplePaint);
    canvas.drawPath(pathOrange, orangePaint);
    canvas.drawPath(pathBlue, bluePaint);

    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final TextStyle style = TextStyle(color: Colors.grey[500], fontSize: 10);
    final int yLabelCount = 7;
    final List<String> yLabels = List<String>.generate(yLabelCount, (index) {
      final value = chartMax * ((yLabelCount - 1 - index) / (yLabelCount - 1));
      if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
      if (value >= 1000) return '${(value / 1000).round()}k';
      return value.round().toString();
    });
    for (int i = 0; i < yLabels.length; i++) {
      textPainter.text = TextSpan(text: yLabels[i], style: style);
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(0, i * (h / (yLabels.length - 1)) - 6),
      );
    }

    final List<String> xLabels = weeklyData.labels;
    final int step = (xLabels.length > 15) ? (xLabels.length ~/ 7) : 1;
    for (int i = 0; i < xLabels.length; i += step) {
      textPainter.text = TextSpan(text: xLabels[i], style: style);
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(w * (i / (xLabels.length - 1)) - 10, h - 12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.weeklyData != weeklyData;
}

// -----------------------------------------------------------------------------
// OPERATIONS TAB
// -----------------------------------------------------------------------------

class _OperationsTab extends StatelessWidget {
  final List<InvoiceModel> invoices;

  const _OperationsTab({required this.invoices});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'All Invoices',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: invoices.isEmpty
                ? Center(
                    child: Text(
                      'No invoices for this period',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  )
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 40,
                        dataRowMinHeight: 56,
                        dataRowMaxHeight: 56,
                        columns: const [
                          DataColumn(label: Text('Patient')),
                          DataColumn(label: Text('Service')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Amount')),
                          DataColumn(label: Text('Status')),
                        ],
                        rows: invoices.map((invoice) {
                          return DataRow(
                            cells: [
                              DataCell(Text(invoice.patientName.isEmpty
                                  ? 'General Patient'
                                  : invoice.patientName)),
                              DataCell(Text(invoice.service.isEmpty ? '—' : invoice.service)),
                              DataCell(Text(DateFormat('dd/MM/yyyy').format(invoice.date))),
                              DataCell(Text(_formatCurrency(invoice.amount))),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: invoice.isPaid
                                        ? const Color(0xFFE8F5E9)
                                        : invoice.isOverdue
                                            ? const Color(0xFFFFEBEE)
                                            : const Color(0xFFFFF3E0),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    invoice.isPaid
                                        ? 'Paid'
                                        : invoice.isOverdue
                                            ? 'Overdue'
                                            : 'Pending',
                                    style: TextStyle(
                                      color: invoice.isPaid
                                          ? const Color(0xFF00C853)
                                          : invoice.isOverdue
                                              ? const Color(0xFFFF1744)
                                              : const Color(0xFFFFAA00),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SOURCE DISTRIBUTION TAB
// -----------------------------------------------------------------------------

class _SourceDistributionTab extends StatelessWidget {
  final List<_StructureData> structures;

  const _SourceDistributionTab({required this.structures});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Revenue by Service Category',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: structures.isEmpty
                ? Center(
                    child: Text(
                      'No revenue data for this period',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    itemCount: structures.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final structure = structures[index];
                      return Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: structure.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  structure.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: structure.percent / 100,
                                    backgroundColor: Colors.grey[200],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      structure.color,
                                    ),
                                    minHeight: 6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                structure.amount,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${structure.percent}%',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11,
                                ),
                              ),
                            ],
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

// -----------------------------------------------------------------------------
// INSURANCE TAB
// -----------------------------------------------------------------------------

class _InsuranceTab extends StatelessWidget {
  const _InsuranceTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'Insurance Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Insurance tracking will be available in a future update.',
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

// -----------------------------------------------------------------------------
// REPORTS TAB
// -----------------------------------------------------------------------------

class _ReportsTab extends StatelessWidget {
  final _FinancialDashboardViewData viewData;

  const _ReportsTab({required this.viewData});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Financial Reports',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ReportCard(
                title: 'Revenue',
                value: viewData.revenue,
                icon: Icons.trending_up,
                color: const Color(0xFF00C853),
              ),
              const SizedBox(width: 12),
              _ReportCard(
                title: 'Outstanding',
                value: viewData.outstandingInvoices,
                icon: Icons.pending_actions,
                color: const Color(0xFFFFAA00),
              ),
              const SizedBox(width: 12),
              _ReportCard(
                title: 'Profit',
                value: viewData.profit,
                icon: Icons.savings,
                color: const Color(0xFF7B61FF),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Export Options',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Export PDF'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.table_chart, size: 18),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ReportCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// BOTTOM SHEET FORMS
// -----------------------------------------------------------------------------

class _TransactionFormSheet extends StatefulWidget {
  const _TransactionFormSheet({
    required this.includeKindToggle,
    required this.includePayerField,
    required this.title,
  });

  final bool includeKindToggle;
  final bool includePayerField;
  final String title;

  @override
  State<_TransactionFormSheet> createState() => _TransactionFormSheetState();
}

class _TransactionFormSheetState extends State<_TransactionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  final _amountController = TextEditingController();
  final _payerController = TextEditingController();
  TransactionKind _selectedKind = TransactionKind.income;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _descController.dispose();
    _amountController.dispose();
    _payerController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final desc = _descController.text.trim();
    final amount = double.parse(_amountController.text.trim());
    final payerText =
        widget.includePayerField ? _payerController.text.trim() : null;
    final kind = widget.includeKindToggle ? _selectedKind : null;
    final now = DateTime.now();

    try {
      final repo = RevenueRepository();
      if (widget.includeKindToggle) {
        await repo.createRevenueEntry(
          RevenueEntry(
            id: '',
            date: _selectedDate,
            description: desc,
            amount: amount,
            type: RevenueType.miscellaneous,
            kind: kind!,
            payer: payerText?.isEmpty == true ? null : payerText,
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kind == TransactionKind.income
                ? 'Income recorded'
                : 'Expense recorded'),
          ),
        );
      } else {
        await repo.createPendingPayment(
          PendingPayment(
            id: '',
            date: _selectedDate,
            description: desc,
            amount: amount,
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pending payment added')),
        );
      }
      if (mounted) Navigator.pop(context);
    } on RevenueException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong. Please try again.')),
      );
      debugPrint('Error in _TransactionFormSheet: $e\n$stack');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: 24 + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.silver.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.title,
              style: AppColors.sectionHeading.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text(
              widget.includeKindToggle
                  ? 'Record an income or expense transaction.'
                  : 'Add a pending payment to track.',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            if (widget.includeKindToggle) ...[
              Text(
                'Type',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ToggleButtons(
                isSelected: [
                  _selectedKind == TransactionKind.income,
                  _selectedKind == TransactionKind.expense,
                ],
                onPressed: _isSaving
                    ? null
                    : (index) {
                        setState(() {
                          _selectedKind = index == 0
                              ? TransactionKind.income
                              : TransactionKind.expense;
                        });
                      },
                borderRadius: BorderRadius.circular(16),
                selectedColor: Colors.white,
                fillColor: _selectedKind == TransactionKind.income
                    ? AppColors.positiveGreen
                    : AppColors.negativeRed,
                color: AppColors.textSecondary,
                constraints: const BoxConstraints(minWidth: 100, minHeight: 42),
                textStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                children: const [
                  Text('Income'),
                  Text('Expense'),
                ],
              ),
              const SizedBox(height: 16),
            ],

            if (widget.includePayerField) ...[
              Text(
                _selectedKind == TransactionKind.expense
                    ? 'Paid To'
                    : 'Received From',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _payerController,
                enabled: !_isSaving,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: _selectedKind == TransactionKind.expense
                      ? 'e.g. "Staff salary — Priya" (optional)'
                      : 'e.g. "Patient name" (optional)',
                  hintStyle: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: AppColors.textSecondary,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Text(
              'Description',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              enabled: !_isSaving,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: widget.includeKindToggle
                    ? 'e.g. "Consultation fee"'
                    : 'e.g. "Lab test"',
                hintStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            Text(
              'Amount',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountController,
              enabled: !_isSaving,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '₹0.00',
                hintStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an amount';
                }
                final amount = double.tryParse(value.trim());
                if (amount == null || amount <= 0) {
                  return 'Enter a valid positive amount';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            Text(
              'Date',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _isSaving ? null : _pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('d MMM yyyy').format(_selectedDate),
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.slateBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    backgroundColor: AppColors.chartBarLight,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontWeight: FontWeight.w600,
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

class _PendingPaymentDetailsSheet extends StatefulWidget {
  const _PendingPaymentDetailsSheet({required this.pending});

  final PendingPayment pending;

  @override
  State<_PendingPaymentDetailsSheet> createState() =>
      _PendingPaymentDetailsSheetState();
}

class _PendingPaymentDetailsSheetState
    extends State<_PendingPaymentDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  late DateTime _selectedDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(text: widget.pending.description);
    _amountController = TextEditingController(
      text: _formatAmountForEditing(widget.pending.amount),
    );
    _notesController = TextEditingController(text: widget.pending.notes ?? '');
    _selectedDate = widget.pending.date;
  }

  @override
  void dispose() {
    _descController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatAmountForEditing(double amount) {
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toString();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _selectedDate.isAfter(now) ? now : _selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final desc = _descController.text.trim();
    final amount = double.parse(_amountController.text.trim());
    final notes = _notesController.text.trim();

    try {
      final repo = RevenueRepository();
      await repo.updatePendingPayment(widget.pending.id, {
        'description': desc,
        'amount': amount,
        'notes': notes.isEmpty ? null : notes,
        'date': _selectedDate,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pending payment updated')),
      );
      Navigator.pop(context);
    } on RevenueException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
      debugPrint('Error in _PendingPaymentDetailsSheet: $e\n$stack');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final patientName = widget.pending.payer?.trim();
    final hasPatientName = patientName != null && patientName.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: 24 + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.silver.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Pending Payment',
              style: AppColors.sectionHeading.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text(
              'Review and edit the details before collecting payment.',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            if (hasPatientName) ...[
              Text(
                'Patient Name',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: patientName,
                enabled: false,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.6),
                  suffixIcon: const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Text(
              'Description',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              enabled: !_isSaving,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. "Payment Received for Visitation"',
                hintStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            Text(
              'Amount',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountController,
              enabled: !_isSaving,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '₹0.00',
                hintStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an amount';
                }
                final amount = double.tryParse(value.trim());
                if (amount == null || amount <= 0) {
                  return 'Enter a valid positive amount';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            Text(
              'Notes',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              enabled: !_isSaving,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Add any additional notes (optional)',
                hintStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Date',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _isSaving ? null : _pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('d MMM yyyy').format(_selectedDate),
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.slateBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    backgroundColor: AppColors.chartBarLight,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontWeight: FontWeight.w600,
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