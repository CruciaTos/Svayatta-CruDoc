import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/errors/revenue_exceptions.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_invoices_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_add_transaction_dialog.dart';
export 'package:doctor_management_app/features/revenue/presentation/desktop_add_transaction_dialog.dart';

// =============================================================================
// COLOR PALETTE & DESIGN TOKENS
// =============================================================================

/// Primary accent color used for main actions, active states, and focal points.
const _kPrimaryAccent = Color(0xFF2563EB); // Royal cobalt blue
const _kAccentTint = Color(0xFFEFF6FF); // Soft blue wash

/// Semantic colors for financial states.
const _kSuccessGreen = Color(0xFF10B981); // Positive / Income
const _kSuccessTint = Color(0xFFECFDF5);
const _kDangerRose = Color(0xFFF43F5E); // Negative / Expense
const _kDangerTint = Color(0xFFFFF1F2);
const _kWarningAmber = Color(0xFFF59E0B); // Pending / Outstanding
const _kWarningTint = Color(0xFFFFFBEB);

/// Neutral typography and surface hierarchy.
const _kTextDark = Color(0xFF0F172A); // High-contrast charcoal
const _kTextMedium = Color(0xFF334155); // Subheadings and labels
const _kTextMuted = Color(0xFF64748B); // Subtext and timestamps
const _kBorderLight = Color(0xFFE2E8F0); // Modular card border
const _kCardBg = Colors.white; // Solid crisp card background
const _kInnerSurface = Color(0xFFF8FAFC); // Nested surface wash

final _currencyFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String _formatCurrency(double value) => _currencyFormatter.format(value);

// =============================================================================
// TIME RANGE DEFINITION
// =============================================================================

enum FinancialRange { today, threeMonths, sixMonths, twelveMonths }

extension FinancialRangeExtension on FinancialRange {
  String get label {
    switch (this) {
      case FinancialRange.today:
        return 'Today';
      case FinancialRange.threeMonths:
        return '3 Months';
      case FinancialRange.sixMonths:
        return '6 Months';
      case FinancialRange.twelveMonths:
        return '12 Months';
    }
  }

  String get shortLabel {
    switch (this) {
      case FinancialRange.today:
        return 'Today';
      case FinancialRange.threeMonths:
        return '90 Days';
      case FinancialRange.sixMonths:
        return '180 Days';
      case FinancialRange.twelveMonths:
        return '1 Year';
    }
  }
}

// =============================================================================
// VIEW MODELS
// =============================================================================

class _FinancialDashboardViewData {
  final String revenue;
  final String expenses;
  final String profit;
  final String profitMargin;
  final String outstandingInvoices;
  final String invoiceSubtitle;
  final String expenseSubtitle;
  final String outstandingSubtitle;
  final int pendingCount;
  final List<_TransactionData> recentTransactions;
  final List<_StructureData> structures;
  final _WeeklyFinancialData weeklyData;
  final List<InvoiceModel> allInvoices;

  const _FinancialDashboardViewData({
    required this.revenue,
    required this.expenses,
    required this.profit,
    required this.profitMargin,
    required this.outstandingInvoices,
    required this.invoiceSubtitle,
    required this.expenseSubtitle,
    required this.outstandingSubtitle,
    required this.pendingCount,
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
  final TransactionKind kind;

  const _TransactionData({
    required this.name,
    required this.type,
    required this.amount,
    required this.date,
    required this.icon,
    required this.color,
    required this.isIncome,
    required this.kind,
  });
}

class _StructureData {
  final String label;
  final String amount;
  final double rawAmount;
  final int percent;
  final Color color;

  const _StructureData({
    required this.label,
    required this.amount,
    required this.rawAmount,
    required this.percent,
    required this.color,
  });
}

// =============================================================================
// DATA MAPPING & AGGREGATION LOGIC
// =============================================================================

_FinancialDashboardViewData _mapFinancialData({
  required List<InvoiceModel> invoices,
  required List<RevenueEntry> entries,
  required List<PendingPayment> pendingPayments,
  required FinancialRange range,
}) {
  final now = DateTime.now();
  DateTime startDate;
  List<DateTime> dates;
  List<String> labels;
  int pointCount;

  switch (range) {
    case FinancialRange.today:
      startDate = DateTime(now.year, now.month, now.day);
      pointCount = 6;
      dates = List.generate(
        pointCount,
        (i) => DateTime(now.year, now.month, now.day, 8 + i * 3),
      );
      labels = dates.map((d) => DateFormat('h a').format(d)).toList();
      break;

    case FinancialRange.threeMonths:
      startDate = DateTime(now.year, now.month - 2, 1);
      pointCount = 3;
      dates = List.generate(
        pointCount,
        (i) => DateTime(startDate.year, startDate.month + i, 1),
      );
      labels = dates.map((d) => DateFormat('MMM').format(d)).toList();
      break;

    case FinancialRange.sixMonths:
      startDate = DateTime(now.year, now.month - 5, 1);
      pointCount = 6;
      dates = List.generate(
        pointCount,
        (i) => DateTime(startDate.year, startDate.month + i, 1),
      );
      labels = dates.map((d) => DateFormat('MMM').format(d)).toList();
      break;

    case FinancialRange.twelveMonths:
      startDate = DateTime(now.year, now.month - 11, 1);
      pointCount = 12;
      dates = List.generate(
        pointCount,
        (i) => DateTime(startDate.year, startDate.month + i, 1),
      );
      labels = dates.map((d) => DateFormat('MMM yy').format(d)).toList();
      break;
  }

  final bucketRevenue = List<double>.filled(pointCount, 0);
  final bucketExpenses = List<double>.filled(pointCount, 0);
  final bucketProfit = List<double>.filled(pointCount, 0);

  double paidInvoiceTotal = 0;
  double outstandingInvoiceTotal = 0;
  int unpaidInvoiceCount = 0;
  int paidInvoiceCount = 0;
  final serviceTotals = <String, double>{};
  final filteredInvoices = <InvoiceModel>[];

  // Process Invoices
  for (final invoice in invoices) {
    final invoiceDate = DateTime(
      invoice.date.year,
      invoice.date.month,
      invoice.date.day,
    );
    if (invoiceDate.isBefore(startDate) || invoiceDate.isAfter(now)) continue;

    filteredInvoices.add(invoice);

    if (invoice.isPaid) {
      paidInvoiceTotal += invoice.amount;
      paidInvoiceCount++;
    } else {
      outstandingInvoiceTotal += invoice.amount;
      unpaidInvoiceCount++;
    }

    int index = -1;
    switch (range) {
      case FinancialRange.today:
        final hour = invoice.date.hour;
        index = ((hour - 8) / 3).floor().clamp(0, pointCount - 1);
        break;
      case FinancialRange.threeMonths:
        index = (invoiceDate.year - startDate.year) * 12 + (invoiceDate.month - startDate.month);
        break;
      case FinancialRange.sixMonths:
        index = (invoiceDate.year - startDate.year) * 12 + (invoiceDate.month - startDate.month);
        break;
      case FinancialRange.twelveMonths:
        index = (invoiceDate.year - startDate.year) * 12 + (invoiceDate.month - startDate.month);
        break;
    }

    if (index >= 0 && index < pointCount) {
      if (invoice.isPaid) {
        bucketRevenue[index] += invoice.amount;
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

  // Process Revenue Entries (Expenses & Miscellaneous Income)
  double totalExpenses = 0;
  int expenseCount = 0;
  double additionalIncomeTotal = 0;

  for (final entry in entries) {
    final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
    if (entryDate.isBefore(startDate) || entryDate.isAfter(now)) continue;

    int index = -1;
    switch (range) {
      case FinancialRange.today:
        final hour = entry.date.hour;
        index = ((hour - 8) / 3).floor().clamp(0, pointCount - 1);
        break;
      case FinancialRange.threeMonths:
        index = (entryDate.year - startDate.year) * 12 + (entryDate.month - startDate.month);
        break;
      case FinancialRange.sixMonths:
        index = (entryDate.year - startDate.year) * 12 + (entryDate.month - startDate.month);
        break;
      case FinancialRange.twelveMonths:
        index = (entryDate.year - startDate.year) * 12 + (entryDate.month - startDate.month);
        break;
    }

    if (entry.kind == TransactionKind.expense) {
      totalExpenses += entry.amount;
      expenseCount++;
      if (index >= 0 && index < pointCount) {
        bucketExpenses[index] += entry.amount;
      }
    } else {
      // Miscellaneous income entry outside invoices
      additionalIncomeTotal += entry.amount;
      if (index >= 0 && index < pointCount) {
        bucketRevenue[index] += entry.amount;
      }
    }
  }

  // Calculate Net Totals
  final double totalRevenue = paidInvoiceTotal + additionalIncomeTotal;
  final double netProfit = totalRevenue - totalExpenses;
  final int profitMarginPercent = totalRevenue > 0
      ? ((netProfit / totalRevenue) * 100).clamp(-100, 100).round()
      : 0;

  // Process Pending Payments
  double pendingPaymentsSum = 0;
  for (final p in pendingPayments) {
    pendingPaymentsSum += p.amount;
  }
  final double totalOutstanding = outstandingInvoiceTotal + pendingPaymentsSum;
  final int totalPendingCount = unpaidInvoiceCount + pendingPayments.length;

  // Compute Weekly / Interval Profits
  for (var i = 0; i < pointCount; i++) {
    bucketProfit[i] = bucketRevenue[i] - bucketExpenses[i];
  }

  // Service Breakdown Structures
  final structuresList = serviceTotals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top4Total = structuresList.take(4).fold<double>(0, (sum, e) => sum + e.value);

  const breakdownColors = <Color>[
    Color(0xFF2563EB), // Primary Cobalt
    Color(0xFF10B981), // Emerald
    Color(0xFF8B5CF6), // Purple
    Color(0xFFF59E0B), // Amber
    Color(0xFF06B6D4), // Cyan
  ];

  final structures = structuresList.take(4).toList().asMap().entries.map((entry) {
    final value = entry.value.value;
    return _StructureData(
      label: entry.value.key,
      amount: _formatCurrency(value),
      rawAmount: value,
      percent: top4Total <= 0 ? 0 : ((value / top4Total) * 100).round(),
      color: breakdownColors[entry.key % breakdownColors.length],
    );
  }).toList();

  return _FinancialDashboardViewData(
    revenue: _formatCurrency(totalRevenue),
    expenses: _formatCurrency(totalExpenses),
    profit: _formatCurrency(netProfit),
    profitMargin: '$profitMarginPercent%',
    outstandingInvoices: _formatCurrency(totalOutstanding),
    invoiceSubtitle: '$paidInvoiceCount paid invoices this period',
    expenseSubtitle: '$expenseCount logged operating expenses',
    outstandingSubtitle: '$totalPendingCount pending accounts',
    pendingCount: totalPendingCount,
    recentTransactions: List.unmodifiable(
      filteredInvoices.take(6).map(_mapInvoiceToTransaction),
    ),
    structures: List.unmodifiable(structures),
    weeklyData: _WeeklyFinancialData(
      labels: labels,
      dates: dates,
      revenue: bucketRevenue,
      expenses: bucketExpenses,
      profit: bucketProfit,
    ),
    allInvoices: List.unmodifiable(filteredInvoices),
  );
}

String _categoryForService(String rawService) {
  final service = rawService.trim();
  if (service.isEmpty) return 'Clinical Consultations';
  if (service.length <= 24) return service;
  return '${service.substring(0, 21)}...';
}

_TransactionData _mapInvoiceToTransaction(InvoiceModel invoice) {
  final statusColor = invoice.isPaid
      ? _kSuccessGreen
      : (invoice.isOverdue ? _kDangerRose : _kWarningAmber);
  return _TransactionData(
    name: invoice.patientName.isEmpty ? 'General Patient' : invoice.patientName,
    type: invoice.service.isEmpty ? 'Consultation' : invoice.service,
    amount: _formatCurrency(invoice.amount),
    date: DateFormat('MMM d, yyyy').format(invoice.date),
    icon: invoice.isPaid ? Icons.arrow_downward_rounded : Icons.pending_actions_rounded,
    color: statusColor,
    isIncome: true,
    kind: TransactionKind.income,
  );
}

// =============================================================================
// MAIN SCREEN WIDGET
// =============================================================================

class DesktopRevenueScreen extends StatefulWidget {
  const DesktopRevenueScreen({super.key});

  @override
  State<DesktopRevenueScreen> createState() => _DesktopRevenueScreenState();
}

class _DesktopRevenueScreenState extends State<DesktopRevenueScreen> {
  final InvoiceRepository _invoiceRepository = InvoiceRepository();
  final RevenueRepository _revenueRepository = RevenueRepository();
  final VisitRepository _visitRepository = VisitRepository();

  FinancialRange _selectedRange = FinancialRange.today;
  TransactionKind? _kindFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAddTransactionSheet() {
    showDesktopAddTransactionDialog(
      context,
      repository: _revenueRepository,
    );
  }

  void _openAddPendingSheet() {
    showDesktopAddTransactionDialog(
      context,
      isPending: true,
      repository: _revenueRepository,
    );
  }

  void _openPendingPaymentDetails(PendingPayment pending) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorderLight),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A0F172A),
                  blurRadius: 32,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SingleChildScrollView(
                child: _PendingPaymentDetailsSheet(pending: pending),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markAsPaid(PendingPayment pending) async {
    try {
      await _visitRepository.markVisitationPaymentPaid(pending.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Marked "${pending.description}" as paid'),
            ],
          ),
          backgroundColor: _kSuccessGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: _kDangerRose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<RevenueEntry> _filterEntries(
    List<RevenueEntry> entries,
    FinancialRange range,
  ) {
    final now = DateTime.now();
    DateTime startDate;
    switch (range) {
      case FinancialRange.today:
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case FinancialRange.threeMonths:
        startDate = DateTime(now.year, now.month - 2, 1);
        break;
      case FinancialRange.sixMonths:
        startDate = DateTime(now.year, now.month - 5, 1);
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
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (e) =>
                e.description.toLowerCase().contains(q) ||
                (e.payer != null && e.payer!.toLowerCase().contains(q)),
          )
          .toList();
    }
    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InvoiceModel>>(
      stream: _invoiceRepository.watchInvoices(),
      builder: (context, invoiceSnapshot) {
        return StreamBuilder<List<PendingPayment>>(
          stream: _revenueRepository.watchPendingPayments(),
          builder: (context, pendingSnapshot) {
            return StreamBuilder<List<RevenueEntry>>(
              stream: _revenueRepository.watchRevenueEntries(),
              builder: (context, entriesSnapshot) {
                final invoices = invoiceSnapshot.data ?? const <InvoiceModel>[];
                final pendingPayments = pendingSnapshot.data ?? const <PendingPayment>[];
                final allEntries = entriesSnapshot.data ?? const <RevenueEntry>[];

                final viewData = _mapFinancialData(
                  invoices: invoices,
                  entries: allEntries,
                  pendingPayments: pendingPayments,
                  range: _selectedRange,
                );

                final filteredEntries = _filterEntries(allEntries, _selectedRange);

                return Stack(
                  children: [
                    SizedBox.expand(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F9FF).withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFCBD5E1),
                                width: 0.75,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0C000000),
                                  blurRadius: 20,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _FinancialDashboardView(
                              viewData: viewData,
                              selectedRange: _selectedRange,
                              onRangeChanged: (range) => setState(() => _selectedRange = range),
                              pendingPayments: pendingPayments,
                              onAddPending: _openAddPendingSheet,
                              onPendingTap: _openPendingPaymentDetails,
                              onMarkPendingPaid: _markAsPaid,
                              onAddTransaction: _openAddTransactionSheet,
                              kindFilter: _kindFilter,
                              onKindFilterChanged: (kind) => setState(() => _kindFilter = kind),
                              searchController: _searchController,
                              searchQuery: _searchQuery,
                              onSearchChanged: (value) => setState(() => _searchQuery = value),
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
                      ),
                    ),
                    if (invoiceSnapshot.hasError || entriesSnapshot.hasError)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: _RevenueStatusBanner(
                          icon: Icons.error_outline_rounded,
                          message: 'Failed to sync live revenue data',
                          color: _kDangerRose,
                          backgroundColor: _kDangerTint,
                        ),
                      )
                    else if (invoiceSnapshot.connectionState == ConnectionState.waiting &&
                        !invoiceSnapshot.hasData)
                      const Positioned(
                        top: 16,
                        right: 16,
                        child: _RevenueStatusBanner(
                          icon: Icons.sync_rounded,
                          message: 'Updating financial data...',
                          color: _kPrimaryAccent,
                          backgroundColor: _kAccentTint,
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
}

// =============================================================================
// STATUS BANNER
// =============================================================================

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
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              message,
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MAIN DASHBOARD VIEW
// =============================================================================

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

  static const _tabLabels = ['Financial Overview', 'Invoice Management'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Unified Header Bar
          _HeaderSection(
            selectedRange: widget.selectedRange,
            onRangeChanged: widget.onRangeChanged,
            onAddTransaction: widget.onAddTransaction,
            onAddPending: widget.onAddPending,
          ),
          const SizedBox(height: 18),

          // 2. Navigation Tabs
          _TabsSection(
            tabLabels: _tabLabels,
            selectedIndex: _selectedTabIndex,
            onTabSelected: (index) => setState(() => _selectedTabIndex = index),
          ),
          const SizedBox(height: 18),

          // 3. Tab Body
          Expanded(child: _buildTabContent()),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _OverviewTab(
          viewData: widget.viewData,
          selectedRange: widget.selectedRange,
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
        return const DesktopInvoicesScreen(isSubScreen: true);
      default:
        return const SizedBox.shrink();
    }
  }
}

// =============================================================================
// HEADER SECTION
// =============================================================================

class _HeaderSection extends StatelessWidget {
  final FinancialRange selectedRange;
  final ValueChanged<FinancialRange> onRangeChanged;
  final VoidCallback onAddTransaction;
  final VoidCallback onAddPending;

  const _HeaderSection({
    required this.selectedRange,
    required this.onRangeChanged,
    required this.onAddTransaction,
    required this.onAddPending,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Title & Context
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Finances & Revenue',
              style: TextStyle(
                fontFamily: AppColors.headingFontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _kTextDark,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),

        // Controls
        Row(
          children: [
            // Period Segmented Selector with smooth horizontal sliding pill
            _SlidingPeriodSelector(
              selectedRange: selectedRange,
              onRangeChanged: onRangeChanged,
            ),
            const SizedBox(width: 12),

            // Secondary: Add Pending
            OutlinedButton.icon(
              onPressed: onAddPending,
              icon: const Icon(Icons.hourglass_empty_rounded, size: 16),
              label: const Text('Add Pending'),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _kTextDark,
                side: const BorderSide(color: _kBorderLight),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Primary Action: Add Transaction
            ElevatedButton.icon(
              onPressed: onAddTransaction,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Record Transaction'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// SLIDING PERIOD SELECTOR (Smooth Horizontal Pill Indicator)
// =============================================================================

class _SlidingPeriodSelector extends StatelessWidget {
  final FinancialRange selectedRange;
  final ValueChanged<FinancialRange> onRangeChanged;

  const _SlidingPeriodSelector({
    required this.selectedRange,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ranges = FinancialRange.values;
    final selectedIndex = ranges.indexOf(selectedRange).clamp(0, ranges.length - 1);
    const double itemWidth = 88.0;
    const double itemHeight = 34.0;
    const double padding = 3.0;

    return Container(
      height: itemHeight + (padding * 2),
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderLight, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      child: SizedBox(
        width: itemWidth * ranges.length,
        height: itemHeight,
        child: Stack(
          children: [
            // Sliding Pill (Continuous Horizontal Glide Across Intermediate Options)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              left: selectedIndex * itemWidth,
              top: 0,
              bottom: 0,
              width: itemWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: _kPrimaryAccent,
                  borderRadius: BorderRadius.circular(7.5),
                  boxShadow: [
                    BoxShadow(
                      color: _kPrimaryAccent.withValues(alpha: 0.32),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),

            // Foreground Clickable Labels
            Row(
              children: ranges.map((range) {
                final isSelected = selectedRange == range;
                return SizedBox(
                  width: itemWidth,
                  height: itemHeight,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onRangeChanged(range),
                      borderRadius: BorderRadius.circular(7.5),
                      hoverColor: isSelected
                          ? Colors.transparent
                          : _kPrimaryAccent.withValues(alpha: 0.05),
                      splashColor: isSelected
                          ? Colors.transparent
                          : _kPrimaryAccent.withValues(alpha: 0.1),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 220),
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? Colors.white : _kTextMedium,
                            letterSpacing: -0.1,
                          ),
                          child: Text(
                            range.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TABS SECTION
// =============================================================================

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
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorderLight, width: 1)),
      ),
      child: Row(
        children: List.generate(tabLabels.length, (index) {
          final bool isActive = selectedIndex == index;
          return InkWell(
            onTap: () => onTabSelected(index),
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.only(right: 32.0, bottom: 10.0),
              child: Column(
                children: [
                  Text(
                    tabLabels[index],
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: isActive ? _kTextDark : _kTextMuted,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 2.5,
                    width: 48,
                    decoration: BoxDecoration(
                      color: isActive ? _kPrimaryAccent : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// =============================================================================
// OVERVIEW TAB (Responsive Grid System)
// =============================================================================

class _OverviewTab extends StatelessWidget {
  final _FinancialDashboardViewData viewData;
  final FinancialRange selectedRange;
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
    required this.selectedRange,
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
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Hero KPI Row (Content Primacy)
          _HeroStatsRow(viewData: viewData),
          const SizedBox(height: 18),

          // 2. Middle Row: Financial Trends Chart (2/3) + Service Breakdown (1/3)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 880;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _ChartSection(
                        weeklyData: viewData.weeklyData,
                        selectedRange: selectedRange,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 3,
                      child: _ServiceBreakdownSection(
                        structures: viewData.structures,
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _ChartSection(
                      weeklyData: viewData.weeklyData,
                      selectedRange: selectedRange,
                    ),
                    const SizedBox(height: 18),
                    _ServiceBreakdownSection(
                      structures: viewData.structures,
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 18),

          // 3. Lower Row: Transaction Ledger (2/3) + Pending Collections (1/3)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 880;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _RecentTransactionsPanel(
                        transactions: recentEntries.isNotEmpty
                            ? recentEntries.map((e) => _mapEntryToTransaction(e)).toList()
                            : viewData.recentTransactions,
                        kindFilter: kindFilter,
                        onKindFilterChanged: onKindFilterChanged,
                        searchController: searchController,
                        searchQuery: searchQuery,
                        onSearchChanged: onSearchChanged,
                        onClearSearch: onClearSearch,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 3,
                      child: _PendingPaymentsPanel(
                        pendingPayments: pendingPayments,
                        totalOutstanding: viewData.outstandingInvoices,
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
                      transactions: recentEntries.isNotEmpty
                          ? recentEntries.map((e) => _mapEntryToTransaction(e)).toList()
                          : viewData.recentTransactions,
                      kindFilter: kindFilter,
                      onKindFilterChanged: onKindFilterChanged,
                      searchController: searchController,
                      searchQuery: searchQuery,
                      onSearchChanged: onSearchChanged,
                      onClearSearch: onClearSearch,
                    ),
                    const SizedBox(height: 18),
                    _PendingPaymentsPanel(
                      pendingPayments: pendingPayments,
                      totalOutstanding: viewData.outstandingInvoices,
                      onAddPending: onAddPending,
                      onPendingTap: onPendingTap,
                      onMarkPendingPaid: onMarkPendingPaid,
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static _TransactionData _mapEntryToTransaction(RevenueEntry e) {
    final isIncome = e.kind == TransactionKind.income;
    return _TransactionData(
      name: (e.payer != null && e.payer!.trim().isNotEmpty)
          ? e.payer!
          : (isIncome ? 'Direct Revenue' : 'Operating Expense'),
      type: e.description,
      amount: '${isIncome ? '+' : '-'}₹${e.amount.toInt()}',
      date: DateFormat('MMM d, h:mm a').format(e.date),
      icon: isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
      color: isIncome ? _kSuccessGreen : _kDangerRose,
      isIncome: isIncome,
      kind: e.kind,
    );
  }
}

// =============================================================================
// HERO STATS ROW (Modular Consistency & Content Primacy)
// =============================================================================

class _HeroStatsRow extends StatelessWidget {
  final _FinancialDashboardViewData viewData;

  const _HeroStatsRow({required this.viewData});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive 4-card layout
        final double width = (constraints.maxWidth - (16 * 3)) / 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _MetricCard(
              title: 'Total Revenue',
              amount: viewData.revenue,
              subtitle: viewData.invoiceSubtitle,
              badgeText: 'Collected',
              badgeColor: _kSuccessGreen,
              badgeBg: _kSuccessTint,
              width: width,
            ),
            _MetricCard(
              title: 'Net Profit',
              amount: viewData.profit,
              subtitle: '${viewData.profitMargin} net margin',
              badgeText: 'Live Margin',
              badgeColor: _kSuccessGreen,
              badgeBg: _kSuccessTint,
              width: width,
            ),
            _MetricCard(
              title: 'Operating Expenses',
              amount: viewData.expenses,
              subtitle: viewData.expenseSubtitle,
              badgeText: 'Expenses',
              badgeColor: _kDangerRose,
              badgeBg: _kDangerTint,
              width: width,
            ),
            _MetricCard(
              title: 'Accounts Receivable',
              amount: viewData.outstandingInvoices,
              subtitle: viewData.outstandingSubtitle,
              badgeText: 'Pending',
              badgeColor: _kWarningAmber,
              badgeBg: _kWarningTint,
              width: width,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String amount;
  final String subtitle;
  final String badgeText;
  final Color badgeColor;
  final Color badgeBg;
  final double width;

  const _MetricCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.badgeText,
    required this.badgeColor,
    required this.badgeBg,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width.clamp(230.0, double.infinity),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderLight, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Metric title
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              color: _kTextMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Big bold number (Content Primacy)
          Text(
            amount,
            style: const TextStyle(
              fontFamily: AppColors.headingFontFamily,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _kTextDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),

          // Bottom row: Subtitle & status pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: _kTextMuted,
                    fontSize: 11.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FINANCIAL TRENDS CHART SECTION
// =============================================================================

class _ChartSection extends StatefulWidget {
  final _WeeklyFinancialData weeklyData;
  final FinancialRange selectedRange;

  const _ChartSection({
    required this.weeklyData,
    required this.selectedRange,
  });

  @override
  State<_ChartSection> createState() => _ChartSectionState();
}

class _ChartSectionState extends State<_ChartSection> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderLight, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Legends
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Financial Trajectory',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Revenue vs Operating Expenses vs Net Profit',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 12,
                      color: _kTextMuted,
                    ),
                  ),
                ],
              ),
              Row(
                children: const [
                  _LegendPill(color: _kPrimaryAccent, label: 'Revenue'),
                  SizedBox(width: 12),
                  _LegendPill(color: _kDangerRose, label: 'Expenses'),
                  SizedBox(width: 12),
                  _LegendPill(color: _kSuccessGreen, label: 'Profit'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Custom Painted Chart Area
          SizedBox(
            height: 220,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final count = widget.weeklyData.revenue.length;
                final xPositions = List<double>.generate(count, (i) {
                  return count <= 1 ? width / 2 : width * (i / (count - 1));
                });

                return MouseRegion(
                  onHover: (event) {
                    if (count == 0) {
                      setState(() => _hoveredIndex = null);
                      return;
                    }
                    final localX = event.localPosition.dx;
                    int nearest = 0;
                    double minDist = double.infinity;
                    for (int i = 0; i < count; i++) {
                      final dist = (xPositions[i] - localX).abs();
                      if (dist < minDist) {
                        minDist = dist;
                        nearest = i;
                      }
                    }
                    if (minDist < 35) {
                      setState(() => _hoveredIndex = nearest);
                    } else {
                      setState(() => _hoveredIndex = null);
                    }
                  },
                  onExit: (_) => setState(() => _hoveredIndex = null),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Smooth Custom Line Chart
                      CustomPaint(
                        size: Size(width, 220),
                        painter: _EnhancedChartPainter(
                          width: width,
                          weeklyData: widget.weeklyData,
                          hoveredIndex: _hoveredIndex,
                        ),
                      ),

                      // Tooltip Overlay
                      if (_hoveredIndex != null && count > 0)
                        _buildFloatingTooltip(width, xPositions[_hoveredIndex!]),
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

  Widget _buildFloatingTooltip(double chartWidth, double xPos) {
    final idx = _hoveredIndex!;
    final revenue = widget.weeklyData.revenue[idx];
    final expenses = widget.weeklyData.expenses[idx];
    final profit = widget.weeklyData.profit[idx];

    final dateLabel = widget.weeklyData.dates.isNotEmpty && idx < widget.weeklyData.dates.length
        ? DateFormat('EEE, MMM d, yyyy').format(widget.weeklyData.dates[idx])
        : widget.weeklyData.labels[idx];

    final isRightSide = (xPos + 180) > chartWidth;
    final tooltipLeft = isRightSide ? (xPos - 170) : (xPos + 14);

    return Positioned(
      left: tooltipLeft.clamp(8.0, chartWidth - 170.0),
      top: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kTextDark.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dateLabel,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            _TooltipMetricRow(
              color: _kPrimaryAccent,
              label: 'Revenue',
              value: _formatCurrency(revenue),
            ),
            const SizedBox(height: 3),
            _TooltipMetricRow(
              color: _kDangerRose,
              label: 'Expenses',
              value: _formatCurrency(expenses),
            ),
            const SizedBox(height: 3),
            _TooltipMetricRow(
              color: _kSuccessGreen,
              label: 'Net Profit',
              value: _formatCurrency(profit),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendPill({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: _kTextMedium,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TooltipMetricRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _TooltipMetricRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EnhancedChartPainter extends CustomPainter {
  final double width;
  final _WeeklyFinancialData weeklyData;
  final int? hoveredIndex;

  _EnhancedChartPainter({
    required this.width,
    required this.weeklyData,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final maxValue = <double>[
      ...weeklyData.revenue,
      ...weeklyData.expenses,
      ...weeklyData.profit,
    ].fold<double>(0, (max, v) => v > max ? v : max);

    final chartMax = maxValue <= 0 ? 1000.0 : maxValue;
    final double chartBottom = h - 24;
    final double chartTop = 14;

    // Draw horizontal dashed grid lines
    final gridPaint = Paint()
      ..color = _kBorderLight
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const int gridRows = 4;
    for (int i = 0; i <= gridRows; i++) {
      final y = chartTop + (i * ((chartBottom - chartTop) / gridRows));
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Smooth Path Builder
    Path buildSmoothPath(List<double> values) {
      final path = Path();
      final count = values.length;
      if (count == 0) return path;

      final points = List<Offset>.generate(count, (i) {
        final x = count <= 1 ? w / 2 : w * (i / (count - 1));
        final normalized = (values[i] / chartMax).clamp(0.0, 1.0);
        final y = chartBottom - (normalized * (chartBottom - chartTop));
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

    final pathRevenue = buildSmoothPath(weeklyData.revenue);
    final pathExpenses = buildSmoothPath(weeklyData.expenses);
    final pathProfit = buildSmoothPath(weeklyData.profit);

    // Draw Subtle Revenue Gradient Fill
    if (weeklyData.revenue.isNotEmpty) {
      final fillPath = Path.from(pathRevenue)
        ..lineTo(w, chartBottom)
        ..lineTo(0, chartBottom)
        ..close();

      final fillPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, chartTop),
          Offset(0, chartBottom),
          [
            _kPrimaryAccent.withValues(alpha: 0.14),
            _kPrimaryAccent.withValues(alpha: 0.0),
          ],
        )
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, fillPaint);
    }

    // Draw Series Lines
    final revenuePaint = Paint()
      ..color = _kPrimaryAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final expensesPaint = Paint()
      ..color = _kDangerRose
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final profitPaint = Paint()
      ..color = _kSuccessGreen
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(pathRevenue, revenuePaint);
    canvas.drawPath(pathExpenses, expensesPaint);
    canvas.drawPath(pathProfit, profitPaint);

    // Draw Vertical Crosshair & Highlight Dots when hovered
    final count = weeklyData.revenue.length;
    if (hoveredIndex != null && hoveredIndex! < count) {
      final x = count <= 1 ? w / 2 : w * (hoveredIndex! / (count - 1));

      final crosshairPaint = Paint()
        ..color = _kPrimaryAccent.withValues(alpha: 0.3)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(x, chartTop), Offset(x, chartBottom), crosshairPaint);

      // Draw anchor circles
      void drawDot(double value, Color color) {
        final normalized = (value / chartMax).clamp(0.0, 1.0);
        final y = chartBottom - (normalized * (chartBottom - chartTop));
        canvas.drawCircle(Offset(x, y), 5.0, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color);
      }

      drawDot(weeklyData.revenue[hoveredIndex!], _kPrimaryAccent);
      drawDot(weeklyData.expenses[hoveredIndex!], _kDangerRose);
      drawDot(weeklyData.profit[hoveredIndex!], _kSuccessGreen);
    }

    // Bottom X-Axis Labels
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final xLabels = weeklyData.labels;
    final int step = (xLabels.length > 15) ? (xLabels.length ~/ 7) : 1;

    for (int i = 0; i < xLabels.length; i += step) {
      final x = count <= 1 ? w / 2 : w * (i / (count - 1));
      textPainter.text = TextSpan(
        text: xLabels[i],
        style: const TextStyle(
          fontFamily: AppColors.bodyFontFamily,
          color: _kTextMuted,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - (textPainter.width / 2), chartBottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _EnhancedChartPainter oldDelegate) =>
      oldDelegate.weeklyData != weeklyData || oldDelegate.hoveredIndex != hoveredIndex;
}

// =============================================================================
// REVENUE BY SERVICE BREAKDOWN (Replaces Old Placeholders!)
// =============================================================================

class _ServiceBreakdownSection extends StatelessWidget {
  final List<_StructureData> structures;

  const _ServiceBreakdownSection({required this.structures});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderLight, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Revenue by Service',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _kTextDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Clinical stream contribution',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 12,
                      color: _kTextMuted,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _kAccentTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Top Streams',
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: _kPrimaryAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (structures.isEmpty)
            Container(
              height: 190,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pie_chart_outline_rounded, size: 36, color: _kTextMuted.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  const Text(
                    'No invoice collections recorded yet',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: _kTextMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: structures.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: item.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                item.label,
                                style: const TextStyle(
                                  fontFamily: AppColors.bodyFontFamily,
                                  color: _kTextDark,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                item.amount,
                                style: const TextStyle(
                                  fontFamily: AppColors.bodyFontFamily,
                                  color: _kTextDark,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${item.percent}%',
                                style: const TextStyle(
                                  fontFamily: AppColors.bodyFontFamily,
                                  color: _kTextMuted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (item.percent / 100.0).clamp(0.0, 1.0),
                          backgroundColor: _kInnerSurface,
                          color: item.color,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// RECENT TRANSACTIONS PANEL (Ledger View)
// =============================================================================

class _RecentTransactionsPanel extends StatelessWidget {
  final List<_TransactionData> transactions;
  final TransactionKind? kindFilter;
  final ValueChanged<TransactionKind?> onKindFilterChanged;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  const _RecentTransactionsPanel({
    required this.transactions,
    required this.kindFilter,
    required this.onKindFilterChanged,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 440,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderLight, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with search & filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                const Text(
                  'Transaction Ledger',
                  style: TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: _kTextDark,
                  ),
                ),
                const SizedBox(width: 14),

                // Search Input
                SizedBox(
                  width: 210,
                  height: 34,
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    style: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 12.5,
                      color: _kTextDark,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search payer or note...',
                      hintStyle: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 12,
                        color: _kTextMuted,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16, color: _kTextMuted),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 14, color: _kTextMuted),
                              onPressed: onClearSearch,
                              padding: EdgeInsets.zero,
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: _kInnerSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kPrimaryAccent, width: 1.2),
                      ),
                    ),
                  ),
                ),
                const Spacer(),

                // Filter Chips
                _ModernFilterChip(
                  label: 'All',
                  isSelected: kindFilter == null,
                  onTap: () => onKindFilterChanged(null),
                ),
                const SizedBox(width: 6),
                _ModernFilterChip(
                  label: 'Income',
                  isSelected: kindFilter == TransactionKind.income,
                  selectedColor: _kSuccessGreen,
                  selectedBg: _kSuccessTint,
                  onTap: () => onKindFilterChanged(TransactionKind.income),
                ),
                const SizedBox(width: 6),
                _ModernFilterChip(
                  label: 'Expense',
                  isSelected: kindFilter == TransactionKind.expense,
                  selectedColor: _kDangerRose,
                  selectedBg: _kDangerTint,
                  onTap: () => onKindFilterChanged(TransactionKind.expense),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorderLight),

          // Scrollable List
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_outlined, size: 34, color: _kTextMuted.withValues(alpha: 0.4)),
                        const SizedBox(height: 8),
                        const Text(
                          'No transactions match your filter',
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            color: _kTextMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: transactions.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: _kBorderLight),
                    itemBuilder: (context, index) {
                      final item = transactions[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        child: Row(
                          children: [
                            // Direction Avatar
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: item.isIncome ? _kSuccessTint : _kDangerTint,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                item.icon,
                                size: 18,
                                color: item.isIncome ? _kSuccessGreen : _kDangerRose,
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Payer & Description
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontFamily: AppColors.bodyFontFamily,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                      color: _kTextDark,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.type,
                                    style: const TextStyle(
                                      fontFamily: AppColors.bodyFontFamily,
                                      color: _kTextMuted,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Amount & Timestamp
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  item.amount,
                                  style: TextStyle(
                                    fontFamily: AppColors.headingFontFamily,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: item.isIncome ? _kSuccessGreen : _kDangerRose,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.date,
                                  style: const TextStyle(
                                    fontFamily: AppColors.bodyFontFamily,
                                    color: _kTextMuted,
                                    fontSize: 11,
                                  ),
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

class _ModernFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? selectedColor;
  final Color? selectedBg;
  final VoidCallback onTap;

  const _ModernFilterChip({
    required this.label,
    required this.isSelected,
    this.selectedColor,
    this.selectedBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = selectedColor ?? _kPrimaryAccent;
    final activeBg = selectedBg ?? _kAccentTint;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? activeColor.withValues(alpha: 0.4) : _kBorderLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: isSelected ? activeColor : _kTextMedium,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PENDING PAYMENTS PANEL (Receivables View)
// =============================================================================

class _PendingPaymentsPanel extends StatelessWidget {
  final List<PendingPayment> pendingPayments;
  final String totalOutstanding;
  final VoidCallback onAddPending;
  final ValueChanged<PendingPayment> onPendingTap;
  final ValueChanged<PendingPayment> onMarkPendingPaid;

  const _PendingPaymentsPanel({
    required this.pendingPayments,
    required this.totalOutstanding,
    required this.onAddPending,
    required this.onPendingTap,
    required this.onMarkPendingPaid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 440,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderLight, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with count badge and Add button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Pending Collections',
                      style: TextStyle(
                        fontFamily: AppColors.headingFontFamily,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kWarningTint,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${pendingPayments.length}',
                        style: const TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          color: _kWarningAmber,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: onAddPending,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: _kPrimaryAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorderLight),

          // Outstanding Highlight Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            color: _kInnerSurface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Outstanding',
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: _kTextMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  totalOutstanding,
                  style: const TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    color: _kWarningAmber,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorderLight),

          // Pending List
          Expanded(
            child: pendingPayments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 34, color: _kSuccessGreen.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        const Text(
                          'All payments settled',
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            color: _kTextMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: pendingPayments.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: _kBorderLight),
                    itemBuilder: (_, index) {
                      final pending = pendingPayments[index];
                      return InkWell(
                        onTap: () => onPendingTap(pending),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: _kWarningTint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.hourglass_empty_rounded,
                                  size: 16,
                                  color: _kWarningAmber,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pending.description,
                                      style: const TextStyle(
                                        fontFamily: AppColors.bodyFontFamily,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: _kTextDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat('MMM d, yyyy').format(pending.date),
                                      style: const TextStyle(
                                        fontFamily: AppColors.bodyFontFamily,
                                        color: _kTextMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatCurrency(pending.amount),
                                    style: const TextStyle(
                                      fontFamily: AppColors.headingFontFamily,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: _kWarningAmber,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () => onMarkPendingPaid(pending),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _kSuccessTint,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: _kSuccessGreen.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.check_rounded, size: 12, color: _kSuccessGreen),
                                          SizedBox(width: 3),
                                          Text(
                                            'Mark Paid',
                                            style: TextStyle(
                                              fontFamily: AppColors.bodyFontFamily,
                                              color: _kSuccessGreen,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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

// =============================================================================
// PENDING PAYMENT DETAILS MODAL
// =============================================================================

class _PendingPaymentDetailsSheet extends StatefulWidget {
  const _PendingPaymentDetailsSheet({required this.pending});

  final PendingPayment pending;

  @override
  State<_PendingPaymentDetailsSheet> createState() => _PendingPaymentDetailsSheetState();
}

class _PendingPaymentDetailsSheetState extends State<_PendingPaymentDetailsSheet> {
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
      text: widget.pending.amount == widget.pending.amount.roundToDouble()
          ? widget.pending.amount.toStringAsFixed(0)
          : widget.pending.amount.toString(),
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
        SnackBar(
          content: const Text('Pending payment updated successfully'),
          backgroundColor: _kSuccessGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context);
    } on RevenueException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: _kDangerRose),
      );
    } catch (e, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
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
        top: 20,
        bottom: 24 + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kWarningTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    color: _kWarningAmber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Pending Collection Details',
                        style: TextStyle(
                          fontFamily: AppColors.headingFontFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _kTextDark,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Review or modify receivable details before recording collection.',
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 12,
                          color: _kTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _kTextMuted, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: _kBorderLight),
            const SizedBox(height: 20),

            if (hasPatientName) ...[
              const Text(
                'Patient Name',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kTextDark,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: patientName,
                enabled: false,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: _kTextDark,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _kInnerSurface,
                  suffixIcon: const Icon(Icons.lock_outline_rounded, size: 16, color: _kTextMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorderLight),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            const Text(
              'Description',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kTextDark,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              enabled: !_isSaving,
              style: const TextStyle(fontFamily: AppColors.bodyFontFamily, color: _kTextDark),
              decoration: InputDecoration(
                hintText: 'e.g. "Consultation fee"',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorderLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorderLight),
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

            const Text(
              'Amount',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kTextDark,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountController,
              enabled: !_isSaving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontFamily: AppColors.bodyFontFamily, color: _kTextDark),
              decoration: InputDecoration(
                hintText: '₹0.00',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorderLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorderLight),
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

            const Text(
              'Notes (Optional)',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kTextDark,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              enabled: !_isSaving,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(fontFamily: AppColors.bodyFontFamily, color: _kTextDark),
              decoration: InputDecoration(
                hintText: 'Add additional collection details...',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorderLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorderLight),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Date',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kTextDark,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _isSaving ? null : _pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorderLight),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 16, color: _kTextMuted),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('d MMM yyyy').format(_selectedDate),
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: _kTextDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Footer Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: _kTextMedium,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontFamily: AppColors.bodyFontFamily, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    backgroundColor: _kPrimaryAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
