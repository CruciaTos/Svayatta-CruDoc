import 'package:flutter/material.dart';

/// Desktop version of the Revenue & Financials tab.
///
/// Fully redesigned to match the CareOps financial dashboard exactly.
/// Includes stats, an interactive chart with tooltip, a recent transactions
/// list, and the exact horizontal pill-bar layout for financial structure.
/// Wrapped in a centered container to respect the side navigation.
class DesktopRevenueScreen extends StatelessWidget {
  const DesktopRevenueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
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
                  color: Colors.grey.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24.0),
            child: const _FinancialDashboardView(),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// MAIN DASHBOARD VIEW
// ==============================================================================

class _FinancialDashboardView extends StatelessWidget {
  const _FinancialDashboardView();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HeaderSection(),
        const SizedBox(height: 24),
        const _TabsSection(),
        const SizedBox(height: 24),
        const _StatsRow(),
        const SizedBox(height: 24),
        const _ChartSection(),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > 800) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _RecentTransactionsSection()),
                  const SizedBox(width: 16),
                  Expanded(flex: 1, child: _FinancialStructureSection()),
                ],
              );
            } else {
              return Column(
                children: [
                  _RecentTransactionsSection(),
                  const SizedBox(height: 16),
                  _FinancialStructureSection(),
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
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
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

  Widget _buildDropdownButton(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
      'Reports'
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
                  color: isActive ? const Color(0xFF1A1A1A) : Colors.transparent,
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
  const _StatsRow();

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
              amount: '\$1,248,320',
              subtitle: 'per last week',
              percentage: '+14%',
              isPositive: true,
              width: width,
            ),
            _StatsCard(
              title: 'Expenses',
              amount: '\$642,800',
              subtitle: 'per last week',
              percentage: '+6.2%',
              isPositive: true,
              width: width,
            ),
            _StatsCard(
              title: 'Profit',
              amount: '\$605,520',
              subtitle: 'per last week',
              percentage: '+18.9%',
              isPositive: true,
              width: width,
            ),
            _StatsCard(
              title: 'Outstanding Invoices',
              amount: '\$42,800',
              subtitle: 'per last week',
              percentage: '+11.3%',
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
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 12),
          Text(amount, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              const SizedBox(width: 8),
              Icon(isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 14, color: isPositive ? const Color(0xFF00C853) : const Color(0xFFFF1744)),
              const SizedBox(width: 4),
              Text(
                percentage,
                style: TextStyle(
                  color: isPositive ? const Color(0xFF00C853) : const Color(0xFFFF1744),
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
  const _ChartSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Financial trends', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  _LegendItem(color: const Color(0xFF7B61FF), label: 'Revenue'),
                  const SizedBox(width: 16),
                  _LegendItem(color: const Color(0xFFFFAA00), label: 'Expenses'),
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
                      painter: _LineChartPainter(constraints.maxWidth),
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
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            _TooltipRow(color: Color(0xFF7B61FF), text: '\$548,300'),
                            _TooltipRow(color: Color(0xFFFFAA00), text: '\$175,500'),
                            _TooltipRow(color: Color(0xFF3F51B5), text: '\$375,800'),
                            SizedBox(height: 4),
                            Text('Thu, Feb 3, 2026', style: TextStyle(color: Colors.white70, fontSize: 10)),
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
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
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
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// Custom Paint for the wavy lines and exact labels
class _LineChartPainter extends CustomPainter {
  final double width;

  _LineChartPainter(this.width);

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
      ..color = const Color(0xFF7B61FF).withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final double w = size.width;
    final double h = size.height;

    // Wavy paths approximating the image
    final Path pathPurple = Path()
      ..moveTo(0, h * 0.6)
      ..quadraticBezierTo(w * 0.2, h * 0.5, w * 0.4, h * 0.6)
      ..quadraticBezierTo(w * 0.6, h * 0.2, w * 0.8, h * 0.5)
      ..quadraticBezierTo(w * 0.9, h * 0.6, w, h * 0.4);

    final Path pathOrange = Path()
      ..moveTo(0, h * 0.8)
      ..quadraticBezierTo(w * 0.2, h * 0.8, w * 0.4, h * 0.7)
      ..quadraticBezierTo(w * 0.6, h * 0.5, w * 0.8, h * 0.6)
      ..quadraticBezierTo(w * 0.9, h * 0.65, w, h * 0.5);

    final Path pathBlue = Path()
      ..moveTo(0, h * 0.5)
      ..quadraticBezierTo(w * 0.2, h * 0.4, w * 0.4, h * 0.5)
      ..quadraticBezierTo(w * 0.6, h * 0.1, w * 0.8, h * 0.4)
      ..quadraticBezierTo(w * 0.9, h * 0.5, w, h * 0.3);

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
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final TextStyle style = TextStyle(color: Colors.grey[500], fontSize: 10);
    final List<String> yLabels = ['600k', '500k', '400k', '300k', '200k', '100k', '0'];
    for (int i = 0; i < yLabels.length; i++) {
      textPainter.text = TextSpan(text: yLabels[i], style: style);
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, i * (h / (yLabels.length - 1)) - 6));
    }

    // Draw X-Axis Labels
    final List<String> xLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    for (int i = 0; i < xLabels.length; i++) {
      textPainter.text = TextSpan(text: xLabels[i], style: style);
      textPainter.layout();
      textPainter.paint(canvas, Offset(w * (i / (xLabels.length - 1)) - 10, h - 12));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==============================================================================
// 4. RECENT TRANSACTIONS (REPLACED DEPARTMENT PERFORMANCE)
// ==============================================================================

class _RecentTransactionsSection extends StatelessWidget {
  const _RecentTransactionsSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent transactions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.more_horiz, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _TransactionRow(
            name: 'Emily Parker',
            type: 'Patient Payment',
            amount: '\$450.00',
            date: 'Today, 10:30 AM',
            icon: Icons.person,
            color: Color(0xFF7B61FF),
            isIncome: true,
          ),
          const SizedBox(height: 12),
          const _TransactionRow(
            name: 'City Lab Services',
            type: 'Lab Invoice',
            amount: '\$1,280.00',
            date: 'Yesterday, 4:15 PM',
            icon: Icons.science_outlined,
            color: Color(0xFFFFAA00),
            isIncome: false,
          ),
          const SizedBox(height: 12),
          const _TransactionRow(
            name: 'Wellness Pharmacy',
            type: 'Pharmacy Payment',
            amount: '\$340.00',
            date: 'Yesterday, 2:00 PM',
            icon: Icons.local_hospital_outlined,
            color: Color(0xFF3F51B5),
            isIncome: false,
          ),
          const SizedBox(height: 12),
          const _TransactionRow(
            name: 'Green Valley Insurance',
            type: 'Insurance Payout',
            amount: '\$1,890.00',
            date: 'Feb 2, 2026',
            icon: Icons.health_and_safety_outlined,
            color: Color(0xFF00C853),
            isIncome: true,
          ),
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
              color: color.withOpacity(0.1),
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
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
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
                  color: isIncome ? const Color(0xFF00C853) : const Color(0xFFFF1744),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                date,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
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
// 5. FINANCIAL STRUCTURE (HORIZONTAL PILL BARS)
// ==============================================================================

class _FinancialStructureSection extends StatelessWidget {
  const _FinancialStructureSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Financial structure', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _StructureItem(
                label: 'Patient services',
                amount: '\$45,600',
                percent: 38,
                color: const Color(0xFF7B61FF),
              )),
              const SizedBox(width: 12),
              Expanded(child: _StructureItem(
                label: 'Insurance claims',
                amount: '\$36,000',
                percent: 30,
                color: const Color(0xFFBDA6FF),
              )),
              const SizedBox(width: 12),
              Expanded(child: _StructureItem(
                label: 'Packages',
                amount: '\$14,400',
                percent: 12,
                color: const Color(0xFFE2D5FF),
              )),
              const SizedBox(width: 12),
              Expanded(child: _StructureItem(
                label: 'Other',
                amount: '\$12,000',
                percent: 10,
                color: Colors.grey[200]!,
                borderColor: Colors.grey[400]!,
              )),
            ],
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
  final Color? borderColor;

  const _StructureItem({
    required this.label,
    required this.amount,
    required this.percent,
    required this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(amount, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            border: borderColor != null ? Border.all(color: borderColor!, width: 1.5) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          // Transparent visual if it's the grey one
          child: borderColor != null ? null : SizedBox(),
        ),
        const SizedBox(height: 4),
        Text('$percent%', style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }
}