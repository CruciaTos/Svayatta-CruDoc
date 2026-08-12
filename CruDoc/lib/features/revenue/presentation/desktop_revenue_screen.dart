import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';

const _emptyFinancialDashboardData = _FinancialDashboardViewData(
  revenue: '₹0',
  expenses: '₹0',
  profit: '₹0',
  outstandingInvoices: '₹0',
  invoiceSubtitle: '0 invoices this week',
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
);

final _currencyFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String _formatCurrency(double value) => _currencyFormatter.format(value);

_FinancialDashboardViewData _mapInvoicesToFinancialData(
  List<InvoiceModel> invoices,
) {
  final now = DateTime.now();
  final weekStart = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - DateTime.monday));
  final weekDates = List<DateTime>.generate(
    7,
    (index) => weekStart.add(Duration(days: index)),
  );
  final weekRevenue = List<double>.filled(7, 0);
  final weekExpenses = List<double>.filled(7, 0);
  final weekProfit = List<double>.filled(7, 0);

  double paidTotal = 0;
  double outstandingTotal = 0;
  int unpaidCount = 0;
  int invoicesThisWeek = 0;
  final serviceTotals = <String, double>{};

  for (final invoice in invoices) {
    if (invoice.isPaid) {
      paidTotal += invoice.amount;
    } else {
      outstandingTotal += invoice.amount;
      unpaidCount += 1;
    }

    final invoiceDay = DateTime(
      invoice.date.year,
      invoice.date.month,
      invoice.date.day,
    );
    final dayIndex = invoiceDay.difference(weekStart).inDays;
    if (dayIndex >= 0 && dayIndex < 7) {
      invoicesThisWeek += 1;
      if (invoice.isPaid) {
        weekRevenue[dayIndex] += invoice.amount;
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

  for (var i = 0; i < 7; i += 1) {
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
    invoiceSubtitle: '$invoicesThisWeek invoices this week',
    outstandingSubtitle: '$unpaidCount unpaid invoices',
    recentTransactions: List.unmodifiable(
      invoices.take(6).map(_mapInvoiceToTransaction),
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
      labels: weekDates.map((date) => DateFormat('E').format(date)).toList(),
      dates: weekDates,
      revenue: weekRevenue,
      expenses: weekExpenses,
      profit: weekProfit,
    ),
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

/// Desktop version of the Revenue & Financials tab.
///
/// Fully redesigned to match the CareOps financial dashboard exactly.
/// Includes stats, an interactive chart with tooltip, a recent transactions
/// list, and the exact horizontal pill-bar layout for financial structure.
/// Wrapped in a centered container to respect the side navigation.
class DesktopRevenueScreen extends StatefulWidget {
  const DesktopRevenueScreen({super.key});

  @override
  State<DesktopRevenueScreen> createState() => _DesktopRevenueScreenState();
}

class _DesktopRevenueScreenState extends State<DesktopRevenueScreen> {
  final InvoiceRepository _repository = InvoiceRepository();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InvoiceModel>>(
      stream: _repository.watchInvoices(),
      builder: (context, snapshot) {
        final viewData = snapshot.hasData
            ? _mapInvoicesToFinancialData(
                snapshot.data ?? const <InvoiceModel>[],
              )
            : _emptyFinancialDashboardData;

        return Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
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
                    padding: const EdgeInsets.all(24.0),
                    child: _FinancialDashboardView(viewData: viewData),
                  ),
                ),
              ),
            ),
            if (snapshot.hasError)
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
            else if (snapshot.connectionState == ConnectionState.waiting)
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

// ==============================================================================
// MAIN DASHBOARD VIEW
// ==============================================================================

class _FinancialDashboardView extends StatelessWidget {
  final _FinancialDashboardViewData viewData;

  const _FinancialDashboardView({required this.viewData});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HeaderSection(),
        const SizedBox(height: 24),
        const _TabsSection(),
        const SizedBox(height: 24),
        _StatsRow(viewData: viewData),
        const SizedBox(height: 24),
        _ChartSection(weeklyData: viewData.weeklyData),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > 800) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _RecentTransactionsSection(
                      transactions: viewData.recentTransactions,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: _FinancialStructureSection(
                      structures: viewData.structures,
                    ),
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  _RecentTransactionsSection(
                    transactions: viewData.recentTransactions,
                  ),
                  const SizedBox(height: 16),
                  _FinancialStructureSection(structures: viewData.structures),
                ],
              );
            }
          },
        ),
      ],
    );
  }
}

// ==============================================================================
// 1. HEADER & TABS
// ==============================================================================

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

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
            _buildDropdownButton('This week'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.download_rounded,
                size: 20,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.settings_outlined,
                size: 20,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDropdownButton(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
        ],
      ),
    );
  }
}

class _TabsSection extends StatelessWidget {
  const _TabsSection();

  @override
  Widget build(BuildContext context) {
    final List<String> tabs = [
      'Overview',
      'Operations',
      'Source distribution',
      'Insurance',
      'Reports',
    ];
    return Row(
      children: tabs.map((tab) {
        final bool isActive = tab == 'Overview';
        return Padding(
          padding: const EdgeInsets.only(right: 24.0),
          child: Column(
            children: [
              Text(
                tab,
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
                  color: isActive
                      ? const Color(0xFF1A1A1A)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ==============================================================================
// 2. STATS CARDS
// ==============================================================================

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

// ==============================================================================
// 3. FINANCIAL TRENDS (EXACT WAVY CHART)
// ==============================================================================

class _ChartSection extends StatelessWidget {
  final _WeeklyFinancialData weeklyData;

  const _ChartSection({required this.weeklyData});

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
                return Stack(
                  children: [
                    // Chart Painter
                    CustomPaint(
                      size: Size(constraints.maxWidth, 200),
                      painter: _LineChartPainter(
                        width: constraints.maxWidth,
                        weeklyData: weeklyData,
                      ),
                    ),
                    // Tooltip & Dots (Absolutely positioned to match image)
                    Positioned(
                      left: constraints.maxWidth * 0.68 - 60,
                      top: 30,
                      child: Container(
                        padding: const EdgeInsets.all(12),
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
                                weeklyData.revenue.isEmpty
                                    ? 0
                                    : weeklyData.revenue.last,
                              ),
                            ),
                            _TooltipRow(
                              color: const Color(0xFFFFAA00),
                              text: _formatCurrency(
                                weeklyData.expenses.isEmpty
                                    ? 0
                                    : weeklyData.expenses.last,
                              ),
                            ),
                            _TooltipRow(
                              color: const Color(0xFF3F51B5),
                              text: _formatCurrency(
                                weeklyData.profit.isEmpty
                                    ? 0
                                    : weeklyData.profit.last,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              weeklyData.dates.isEmpty
                                  ? 'Live Firebase data'
                                  : DateFormat(
                                      'EEE, MMM d, yyyy',
                                    ).format(weeklyData.dates.last),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Dots on chart lines
                    Positioned(
                      top: 55,
                      left: constraints.maxWidth * 0.68 - 5,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF7B61FF),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 93,
                      left: constraints.maxWidth * 0.68 - 5,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFAA00),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 35,
                      left: constraints.maxWidth * 0.68 - 5,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF3F51B5),
                          shape: BoxShape.circle,
                        ),
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

// Custom Paint for the wavy lines and exact labels
class _LineChartPainter extends CustomPainter {
  final double width;
  final _WeeklyFinancialData weeklyData;

  _LineChartPainter({required this.width, required this.weeklyData});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint purplePaint = Paint()
      ..color = const Color(0xFF7B61FF)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final Paint orangePaint = Paint()
      ..color = const Color(0xFFFFAA00)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final Paint bluePaint = Paint()
      ..color = const Color(0xFF3F51B5)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final Paint purpleFill = Paint()
      ..color = const Color(0xFF7B61FF).withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final double w = size.width;
    final double h = size.height;
    final maxValue = <double>[
      ...weeklyData.revenue,
      ...weeklyData.expenses,
      ...weeklyData.profit,
    ].fold<double>(0, (max, value) => value > max ? value : max);
    final chartMax = maxValue <= 0 ? 1.0 : maxValue;

    Path buildPath(List<double> values) {
      final path = Path();
      for (var i = 0; i < values.length; i += 1) {
        final x = values.length == 1 ? 0.0 : w * (i / (values.length - 1));
        final y =
            (h - 22) - ((values[i] / chartMax).clamp(0.0, 1.0) * (h - 42));
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    final Path pathPurple = buildPath(weeklyData.revenue);
    final Path pathOrange = buildPath(weeklyData.expenses);
    final Path pathBlue = buildPath(weeklyData.profit);

    // Draw Fills
    final Path fillPurple = Path.from(pathPurple);
    fillPurple.lineTo(w, h);
    fillPurple.lineTo(0, h);
    fillPurple.close();
    canvas.drawPath(fillPurple, purpleFill);

    // Draw Lines
    canvas.drawPath(pathPurple, purplePaint);
    canvas.drawPath(pathOrange, orangePaint);
    canvas.drawPath(pathBlue, bluePaint);

    // Draw Y-Axis Labels
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final TextStyle style = TextStyle(color: Colors.grey[500], fontSize: 10);
    final List<String> yLabels = List<String>.generate(7, (index) {
      final value = chartMax * ((6 - index) / 6);
      if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
      if (value >= 1000) return '${(value / 1000).round()}k';
      return value.round().toString();
    });
    for (int i = 0; i < yLabels.length; i++) {
      textPainter.text = TextSpan(text: yLabels[i], style: style);
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, i * (h / (yLabels.length - 1)) - 6));
    }

    // Draw X-Axis Labels
    final List<String> xLabels = weeklyData.labels;
    for (int i = 0; i < xLabels.length; i++) {
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

// ==============================================================================
// 4. RECENT TRANSACTIONS (REPLACED DEPARTMENT PERFORMANCE)
// ==============================================================================

class _RecentTransactionsSection extends StatelessWidget {
  final List<_TransactionData> transactions;

  const _RecentTransactionsSection({required this.transactions});

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
                'Recent transactions',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.more_horiz, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (transactions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No invoice transactions yet',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ),
            )
          else
            ...transactions.asMap().entries.expand((entry) sync* {
              if (entry.key > 0) yield const SizedBox(height: 12);
              final transaction = entry.value;
              yield _TransactionRow(
                name: transaction.name,
                type: transaction.type,
                amount: transaction.amount,
                date: transaction.date,
                icon: transaction.icon,
                color: transaction.color,
                isIncome: transaction.isIncome,
              );
            }),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final String name;
  final String type;
  final String amount;
  final String date;
  final IconData icon;
  final Color color;
  final bool isIncome;

  const _TransactionRow({
    required this.name,
    required this.type,
    required this.amount,
    required this.date,
    required this.icon,
    required this.color,
    required this.isIncome,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  type,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isIncome
                      ? const Color(0xFF00C853)
                      : const Color(0xFFFF1744),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                date,
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// 5. FINANCIAL STRUCTURE (HORIZONTAL PILL BARS)
// ==============================================================================

class _FinancialStructureSection extends StatelessWidget {
  final List<_StructureData> structures;

  const _FinancialStructureSection({required this.structures});

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
            'Financial structure',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (structures.isEmpty)
            Text(
              'No paid invoice categories yet',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: structures.asMap().entries.expand((entry) sync* {
                if (entry.key > 0) yield const SizedBox(width: 12);
                final structure = entry.value;
                yield Expanded(
                  child: _StructureItem(
                    label: structure.label,
                    amount: structure.amount,
                    percent: structure.percent,
                    color: structure.color,
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _StructureItem extends StatelessWidget {
  final String label;
  final String amount;
  final int percent;
  final Color color;

  const _StructureItem({
    required this.label,
    required this.amount,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const SizedBox(),
        ),
        const SizedBox(height: 4),
        Text(
          '$percent%',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
