import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:intl/intl.dart'; // add intl: ^0.18.1 to pubspec.yaml

// ---------- DATA MODEL ----------
enum RevenueType { visit, online, miscellaneous }

class RevenueEntry {
  final String id;
  final DateTime date;
  final String description;   // e.g., "Emily Clark - Visit"
  final double amount;
  final RevenueType type;
  final String? payer;        // patient name, null for misc

  const RevenueEntry({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    this.payer,
  });
}

// ---------- REVENUE SCREEN ----------
class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key});

  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  // ----- FILTER -----
  String _selectedFilter = 'Weekly'; // Weekly, Monthly, Yearly, All

  // ----- SAMPLE DATA -----
  final List<RevenueEntry> _allEntries = [
    RevenueEntry(
      id: '1',
      date: DateTime(2026, 7, 6, 10, 30),
      description: 'Emily Clark - Visit',
      amount: 150.0,
      type: RevenueType.visit,
      payer: 'Emily Clark',
    ),
    RevenueEntry(
      id: '2',
      date: DateTime(2026, 7, 5, 14, 0),
      description: 'Michael Brown - Visit',
      amount: 200.0,
      type: RevenueType.visit,
      payer: 'Michael Brown',
    ),
    RevenueEntry(
      id: '3',
      date: DateTime(2026, 7, 4, 11, 0),
      description: 'Online Session: Follow-up',
      amount: 100.0,
      type: RevenueType.online,
      payer: 'Sophia Lee',
    ),
    RevenueEntry(
      id: '4',
      date: DateTime(2026, 6, 28),
      description: 'Misc: Equipment sterilization',
      amount: 50.0,
      type: RevenueType.miscellaneous,
      payer: null,
    ),
    RevenueEntry(
      id: '5',
      date: DateTime(2026, 6, 25),
      description: 'Online Session: Consultation',
      amount: 120.0,
      type: RevenueType.online,
      payer: 'James Wilson',
    ),
    RevenueEntry(
      id: '6',
      date: DateTime(2026, 6, 15),
      description: 'Olivia Martinez - Visit',
      amount: 180.0,
      type: RevenueType.visit,
      payer: 'Olivia Martinez',
    ),
  ];

  // ----- FILTERED ENTRIES -----
  List<RevenueEntry> get _filteredEntries {
    final now = DateTime.now();
    DateTime startDate;

    switch (_selectedFilter) {
      case 'Weekly':
        startDate = now.subtract(const Duration(days: 7));
        break;
      case 'Monthly':
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 'Yearly':
        startDate = DateTime(now.year, 1, 1);
        break;
      default: // All
        startDate = DateTime(2000);
    }

    return _allEntries
        .where((e) => e.date.isAfter(startDate) || e.date.isAtSameMomentAs(startDate))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date)); // newest first
  }

  // ----- LAST PAID -----
  RevenueEntry? get _lastPaidEntry {
    final paid = _allEntries
        .where((e) => e.payer != null)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return paid.isNotEmpty ? paid.first : null;
  }

  // ----- ADD MISCELLANEOUS -----
  void _showAddMiscDialog() {
    final descController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: const Text(
          'Add Miscellaneous Income',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: descController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Description',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.divider),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Amount',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.divider),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.silver)),
          ),
          TextButton(
            onPressed: () {
              final desc = descController.text.trim();
              final amountText = amountController.text.trim();
              if (desc.isEmpty || amountText.isEmpty) return;
              final amount = double.tryParse(amountText);
              if (amount == null) return;

              setState(() {
                _allEntries.add(RevenueEntry(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  date: DateTime.now(),
                  description: 'Misc: $desc',
                  amount: amount,
                  type: RevenueType.miscellaneous,
                  payer: null,
                ));
              });
              Navigator.pop(ctx);
            },
            child: const Text('Add', style: TextStyle(color: AppColors.beige)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEntries;
    final totalRevenue = filtered.fold<double>(0, (sum, e) => sum + e.amount);
    final lastPaid = _lastPaidEntry;

    return Scaffold(
      backgroundColor: AppColors.midnightBlue,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Revenue',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                // Last paid info
                if (lastPaid != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_pin, color: AppColors.beige, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last Paid: ${lastPaid.payer}',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${lastPaid.description} • ${DateFormat.yMMMd().format(lastPaid.date)}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '\$${lastPaid.amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.beige,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // Total revenue for selected period
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Revenue',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '\$${totalRevenue.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.beige,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Filter buttons
                Row(
                  children: ['Weekly', 'Monthly', 'Yearly', 'All'].map((filter) {
                    final isSelected = filter == _selectedFilter;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedFilter = filter),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.beige : AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          filter,
                          style: TextStyle(
                            color: isSelected ? AppColors.midnightBlue : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // List of revenue entries
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No revenue entries for this period',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          physics: const ClampingScrollPhysics(),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            IconData icon;
                            switch (entry.type) {
                              case RevenueType.visit:
                                icon = Icons.medical_services;
                                break;
                              case RevenueType.online:
                                icon = Icons.videocam;
                                break;
                              case RevenueType.miscellaneous:
                                icon = Icons.miscellaneous_services;
                                break;
                            }
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.cardSurface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(icon, color: AppColors.silver, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.description,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          DateFormat.yMMMd().format(entry.date),
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '\$${entry.amount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: AppColors.beige,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.beige,
        onPressed: _showAddMiscDialog,
        child: const Icon(Icons.add, color: AppColors.midnightBlue),
      ),
    );
  }
}