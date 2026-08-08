import 'package:flutter/material.dart';

/// Desktop version of the Inventory tab.
///
/// Features a clean header with stats, tabs, medication cards,
/// striped progress bars, and a side alerts panel.
/// Wrapped in a centered container to respect the side navigation.
class DesktopInventoryListScreen extends StatelessWidget {
  const DesktopInventoryListScreen({super.key, this.autoOpenAddForm = false});

  final bool autoOpenAddForm;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFCFCFD),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24.0),
            child: const _InventoryDashboardView(),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// MAIN DASHBOARD VIEW
// ==============================================================================

class _InventoryDashboardView extends StatelessWidget {
  const _InventoryDashboardView();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- 1. HEADER SECTION ---
        const _InventoryHeaderSection(),
        const SizedBox(height: 32),

        // --- 2. MAIN BODY (Filter + Cards Left, Alerts Right) ---
        LayoutBuilder(
          builder: (context, constraints) {
            final bool isWideScreen = constraints.maxWidth > 1100;

            if (isWideScreen) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Filters & Responsive 2-Column Medication Grid
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FilterRow(),
                        const SizedBox(height: 24),
                        const _MedicationGrid(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Right Column: Alerts Panel
                  const _AlertsPanel(),
                ],
              );
            } else {
              // Mobile / narrow screen layout
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FilterRow(),
                  const SizedBox(height: 24),
                  const _MedicationGrid(),
                  const SizedBox(height: 32),
                  const _AlertsPanel(),
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
// 1. HEADER, TABS & STATS
// ==============================================================================

class _InventoryHeaderSection extends StatelessWidget {
  const _InventoryHeaderSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Title & Action Buttons ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Inventory',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)),
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2937),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add item', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.settings_outlined, size: 20, color: Color(0xFF4B5563)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        // --- Tabs ---
        Row(
          children: [
            _TabItem(label: 'Items', isActive: true),
            _TabItem(label: 'Vendors', isActive: false),
            _TabItem(label: 'Orders', isActive: false),
            _TabItem(label: 'Usage analytics', isActive: false),
          ],
        ),
        const SizedBox(height: 24),

        // --- 5 Stats Cards ---
        LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                Expanded(child: _NewStatCard(
                  title: 'Total items',
                  value: '1,248',
                  subtext: 'across all locations',
                )),
                const SizedBox(width: 12),
                Expanded(child: _NewStatCard(
                  title: 'Low stock alerts',
                  value: '36',
                  subtext: 'needs restocking soon',
                )),
                const SizedBox(width: 12),
                Expanded(child: _NewStatCard(
                  title: 'Out of stock',
                  value: '12',
                  subtext: 'immediate attention',
                )),
                const SizedBox(width: 12),
                Expanded(child: _NewStatCard(
                  title: 'Inventory value',
                  value: '\$184,320',
                  subtext: 'estimated total value',
                )),
                const SizedBox(width: 12),
                Expanded(child: _NewStatCard(
                  title: 'Monthly usage',
                  value: '8,420 units',
                  subtext: 'per last month',
                  hasPositiveGrowth: true,
                )),
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

  const _TabItem({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 24.0),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFF1F2937) : const Color(0xFF6B7280),
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
          style: TextStyle(color: const Color(0xFF6B7280), fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)),
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
              const Icon(Icons.arrow_upward_rounded, size: 12, color: Color(0xFF00C853)),
              const SizedBox(width: 4),
              const Text(
                '+12%',
                style: TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ==============================================================================
// 2. FILTER ROW & RESPONSIVE MEDICATION GRID
// ==============================================================================

class _FilterRow extends StatelessWidget {
  const _FilterRow();

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
              _FilterTab(label: 'All', isActive: true),
              _FilterTab(label: 'Active', isActive: false),
              _FilterTab(label: 'Paused', isActive: false),
              _FilterTab(label: 'Completed', isActive: false),
            ],
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A1A),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Prescription', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool isActive;

  const _FilterTab({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isActive
            ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]
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
    );
  }
}

class _MedicationGrid extends StatelessWidget {
  const _MedicationGrid();

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> medications = [
      {
        'name': 'Metformin',
        'subtitle': 'Glucophage · 500 mg',
        'status': 'Active',
        'dose': '10 tablets',
        'daysLeft': '7 days left',
        'progress': 0.6,
        'progressColor': const Color(0xFF9FA8FF),
        'synced': 'Dr. Anna Nowak',
        'nextDose': 'Today, 13:00',
        'isPaused': false,
        'buttonFilled': false,
      },
      {
        'name': 'Atorvastatin',
        'subtitle': 'Lipitor · 20 mg',
        'status': 'Active',
        'dose': '4 tablets',
        'daysLeft': '7 days left',
        'progress': 0.35,
        'progressColor': const Color(0xFFFFAB40),
        'synced': 'Dr. Piotr Wiśni...',
        'nextDose': '21 March, 14:00',
        'isPaused': false,
        'buttonFilled': false,
      },
      {
        'name': 'Lisinopril',
        'subtitle': 'Zestril · 10 mg',
        'status': 'Active',
        'dose': '10 tablets',
        'daysLeft': '36 days left',
        'progress': 0.6,
        'progressColor': const Color(0xFF9FA8FF),
        'synced': 'Dr. Sarah Lee',
        'nextDose': '23 March , 11:00',
        'isPaused': false,
        'buttonFilled': false,
      },
      {
        'name': 'Vitamin D3',
        'subtitle': 'Generic · 1000 IU',
        'status': 'Active',
        'dose': '2 capsules',
        'daysLeft': '1 days left',
        'progress': 0.15,
        'progressColor': const Color(0xFFFF8A80),
        'synced': 'Dr. Anna Nowak',
        'nextDose': '2 May, 11:00',
        'isPaused': false,
        'buttonFilled': true,
      },
      {
        'name': 'Amoxicillin',
        'subtitle': 'Antibiotic · 500 mg',
        'status': 'Paused',
        'dose': '5 tablets',
        'daysLeft': '24 days left',
        'progress': 0.4,
        'progressColor': const Color(0xFF9FA8FF),
        'synced': 'Dr. Anna Nowak',
        'nextDose': '-',
        'isPaused': true,
        'buttonFilled': false,
      },
      {
        'name': 'Omega B6',
        'subtitle': 'Generic · 50 mg',
        'status': 'Paused',
        'dose': '10 capsules',
        'daysLeft': '16 days left',
        'progress': 0.3,
        'progressColor': const Color(0xFF9FA8FF),
        'synced': 'Dr. Anna Nowak',
        'nextDose': '-',
        'isPaused': true,
        'buttonFilled': false,
      },
    ];

    // Use LayoutBuilder to perfectly split the available width into 2 columns
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth = (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: medications.map((med) {
            return SizedBox(
              width: cardWidth,
              child: _MedicationCard(data: med),
            );
          }).toList(),
        );
      },
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _MedicationCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final bool isPaused = data['isPaused'] as bool;
    final Color statusColor = isPaused ? const Color(0xFFFFA000) : const Color(0xFF00C853);

    return Container(
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
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)],
                ),
                child: const Icon(Icons.medication, color: Color(0xFFD17A28), size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A1A1A)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data['subtitle'],
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    data['status'],
                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(data['dose'], style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              const Spacer(),
              Text(data['daysLeft'], style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          _StripedProgressBar(
            value: data['progress'],
            color: data['progressColor'],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Synced from', style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(data['synced'], style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: Color(0xFF1A1A1A))),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next dose', style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(data['nextDose'], style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: Color(0xFF1A1A1A))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: data['buttonFilled'] == true ? const Color(0xFF1A1A1A) : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: data['buttonFilled'] == true ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                ),
                child: Icon(
                  Icons.arrow_outward_rounded,
                  size: 16,
                  color: data['buttonFilled'] == true ? Colors.white : Colors.grey[700],
                ),
              ),
            ],
          ),
        ],
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
      ..color = Colors.white.withOpacity(0.6)
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
// 3. ALERTS PANEL (Right Side)
// ==============================================================================

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 350, // Fixed width to match the clean side-column look
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Alerts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.more_horiz, size: 20, color: Color(0xFF4B5563)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Alert Items
            _AlertItem(
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.amber.shade700,
              bgColor: Colors.amber.shade50,
              title: 'Face Masks (N95)',
              subtitle: 'Purchase request pe...',
              actionLabel: 'Approve',
            ),
            const SizedBox(height: 8),
            _AlertItem(
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.amber.shade700,
              bgColor: Colors.amber.shade50,
              title: 'IV Drip Sets',
              subtitle: 'Supplier: MedSupply Co.',
              actionLabel: 'View',
            ),
            const SizedBox(height: 8),
            _AlertItem(
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.orange.shade700,
              bgColor: Colors.orange.shade50,
              title: 'Syringes 5ml',
              subtitle: 'ER Department',
              actionLabel: 'View',
            ),
            const SizedBox(height: 8),
            _AlertItem(
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.orange.shade700,
              bgColor: Colors.orange.shade50,
              title: 'Disinfectant Solution',
              subtitle: '8 units',
              actionLabel: 'Restock',
            ),
            const SizedBox(height: 8),
            _AlertItem(
              icon: Icons.check_circle_outline_rounded,
              iconColor: Colors.green.shade700,
              bgColor: Colors.green.shade50,
              title: 'Syringes 5ml',
              subtitle: 'Stock updated: 500 units',
              actionLabel: 'View',
            ),
            const SizedBox(height: 8),
            _AlertItem(
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.orange.shade700,
              bgColor: Colors.orange.shade50,
              title: 'IV Drip Sets',
              subtitle: '',
              actionLabel: 'View',
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final String actionLabel;

  const _AlertItem({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
  });

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
          // Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),

          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1F2937)),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),

          // Action Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              actionLabel,
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