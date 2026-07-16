import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/errors/revenue_exceptions.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';
import 'package:intl/intl.dart';

/// Revenue tracking screen.
class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key, RevenueRepository? repository})
      : _repository = repository;

  final RevenueRepository? _repository;

  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  late final RevenueRepository _repository =
      widget._repository ?? RevenueRepository();

  String _selectedFilter = 'Weekly';

  List<RevenueEntry> _filterEntries(List<RevenueEntry> entries) {
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
      default:
        startDate = DateTime(2000);
    }
    return entries
        .where((e) =>
            e.date.isAfter(startDate) || e.date.isAtSameMomentAs(startDate))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  RevenueEntry? _lastPaidEntry(List<RevenueEntry> entries) {
    final paid = entries.where((e) => e.payer != null).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return paid.isNotEmpty ? paid.first : null;
  }

  Future<void> _showEntryDialog({
    required String title,
    required String descHint,
    required Future<void> Function(String description, double amount) onSubmit,
  }) async {
    final descController = TextEditingController();
    final amountController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (_) {
        bool isSaving = false;
        String? errorText;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> handleSubmit() async {
              final desc = descController.text.trim();
              final amountText = amountController.text.trim();
              if (desc.isEmpty || amountText.isEmpty) {
                setDialogState(() => errorText = 'Please fill in both fields.');
                return;
              }
              final amount = double.tryParse(amountText);
              if (amount == null || amount <= 0) {
                setDialogState(() => errorText = 'Enter a valid amount.');
                return;
              }

              setDialogState(() {
                isSaving = true;
                errorText = null;
              });

              try {
                await onSubmit(desc, amount);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } on RevenueException catch (e) {
                setDialogState(() {
                  isSaving = false;
                  errorText = e.message;
                });
              } catch (e) {
                setDialogState(() {
                  isSaving = false;
                  errorText = 'Failed to save: $e';
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              backgroundColor: AppColors.cardSurface,
              title: Text(title, style: AppColors.sectionHeading),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descController,
                    enabled: !isSaving,
                    style: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: descHint,
                      hintStyle: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textSecondary,
                      ),
                      enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.divider)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    enabled: !isSaving,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Amount',
                      hintStyle: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textSecondary,
                      ),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.divider)),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.silver,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: isSaving ? null : handleSubmit,
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.beige),
                        )
                      : const Text(
                          'Add',
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            color: AppColors.beige,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    descController.dispose();
    amountController.dispose();
  }

  Future<void> _showAddMiscDialog() {
    return _showEntryDialog(
      title: 'Add Miscellaneous Income',
      descHint: 'Description',
      onSubmit: (desc, amount) async {
        final now = DateTime.now();
        await _repository.createRevenueEntry(
          RevenueEntry(
            id: '',
            date: now,
            description: 'Misc: $desc',
            amount: amount,
            type: RevenueType.miscellaneous,
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Income recorded')),
        );
      },
    );
  }

  Future<void> _showAddPendingDialog() {
    return _showEntryDialog(
      title: 'Add Pending Payment',
      descHint: 'Description (e.g. "Lab test")',
      onSubmit: (desc, amount) async {
        final now = DateTime.now();
        await _repository.createPendingPayment(
          PendingPayment(
            id: '',
            date: now,
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
      },
    );
  }

  Future<void> _markAsPaid(PendingPayment pending) async {
    try {
      await _repository.markPendingPaymentAsPaid(pending.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked "${pending.description}" as paid')),
      );
    } on RevenueException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RevenueEntry>>(
      stream: _repository.watchRevenueEntries(),
      builder: (context, entriesSnapshot) {
        final allEntries = entriesSnapshot.data ?? const <RevenueEntry>[];
        final stillLoading = !entriesSnapshot.hasData &&
            entriesSnapshot.connectionState == ConnectionState.waiting;

        return StreamBuilder<List<PendingPayment>>(
          stream: _repository.watchPendingPayments(),
          builder: (context, pendingSnapshot) {
            final pendingPayments =
                pendingSnapshot.data ?? const <PendingPayment>[];
            final filtered = _filterEntries(allEntries);
            final totalRevenue =
                filtered.fold<double>(0, (sum, e) => sum + e.amount);
            final lastPaid = _lastPaidEntry(allEntries);

            return Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: stillLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.beige),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Revenue',
                              style: AppColors.pageHeading,
                            ),
                            const SizedBox(height: 16),
                            if (lastPaid != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.cardSurface,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.person_pin,
                                        color: AppColors.beige, size: 28),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Last Paid: ${lastPaid.payer}',
                                            style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w300,
                                                fontFamily:
                                                    AppColors.headingFontFamily),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${lastPaid.description} • ${DateFormat.yMMMd().format(lastPaid.date)}',
                                            style: const TextStyle(
                                              fontFamily: AppColors.bodyFontFamily,
                                              color: AppColors.textSecondary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '₹${lastPaid.amount.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                          color: Color(0xFF4CAF50),
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),

                            // ---- Filter chips ----
                            Row(
                              children: ['Weekly', 'Monthly', 'Yearly', 'All']
                                  .map((filter) {
                                final isSelected = filter == _selectedFilter;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedFilter = filter),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.beige
                                          : AppColors.cardSurface,
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    child: Text(
                                      filter,
                                      style: TextStyle(
                                        fontFamily: AppColors.bodyFontFamily,
                                        color: isSelected
                                            ? AppColors.midnightBlue
                                            : AppColors.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),

                            // ---- INCOME title and value ----
                            const SizedBox(height: 28),   // more breathing room above heading
                            Text(
                              'INCOME',
                              style: AppColors.pageHeading.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary, // keep original colour
                              ),
                            ),
                            const SizedBox(height: 8),    // tighter gap to amount below
                            Text(
                              '₹${totalRevenue.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontFamily: AppColors.bodyFontFamily,
                                color: Colors.black,
                                fontSize: 48,
                                fontWeight: FontWeight.w300,
                              ),
                            ),

                            // ---- PENDING PAYMENTS SECTION ----
                            if (pendingPayments.isNotEmpty) ...[
                              const SizedBox(height: 28),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Pending Payments',
                                    style: AppColors.pageHeading.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _showAddPendingDialog,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: AppColors.chartBarLight,   // accent-blue fill
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.add,
                                          size: 18, color: Colors.white), // white icon
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 170,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: pendingPayments.length,
                                  itemBuilder: (_, index) {
                                    final pending = pendingPayments[index];
                                    return Container(
                                      width: 180,
                                      margin:
                                          const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.cardSurface,
                                        borderRadius:
                                            BorderRadius.circular(28),
                                        border: Border.all(
                                            color: Colors.amber
                                                .withOpacity(0.4),
                                            width: 1),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '₹${pending.amount.toStringAsFixed(0)}',
                                                  style: const TextStyle(
                                                    fontFamily: AppColors.bodyFontFamily,
                                                    color: Colors.amber,
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () =>
                                                    _markAsPaid(pending),
                                                child: const Icon(
                                                    Icons.check_circle_outline,
                                                    size: 20,
                                                    color: Color(0xFF4CAF50)),
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          Text(
                                            pending.description,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w300,
                                              fontFamily:
                                                  AppColors.headingFontFamily,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat.yMMMd()
                                                .format(pending.date),
                                            style: const TextStyle(
                                              fontFamily: AppColors.bodyFontFamily,
                                              color: AppColors.textSecondary,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],

                            if (pendingPayments.isEmpty)
                              GestureDetector(
                                onTap: _showAddPendingDialog,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardSurface,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: AppColors.chartBarLight,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.add,
                                            size: 18, color: Colors.white),
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Add Pending Payment',
                                        style: TextStyle(
                                          fontFamily: AppColors.bodyFontFamily,
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // ---- RECENT PAYMENTS + Add Misc Income ----
                            const SizedBox(height: 28),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Recent Payments',
                                  style: AppColors.pageHeading.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary.withOpacity(0.85),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _showAddMiscDialog,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: AppColors.chartBarLight,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.add,
                                        size: 18, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            Expanded(
                              child: filtered.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No revenue entries for this period',
                                        style: TextStyle(
                                          fontFamily: AppColors.bodyFontFamily,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      physics:
                                          const ClampingScrollPhysics(),
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
                                            icon = Icons
                                                .miscellaneous_services;
                                            break;
                                        }
                                        return Container(
                                          margin: const EdgeInsets.only(
                                              bottom: 8),
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: AppColors.cardSurface,
                                            borderRadius:
                                                BorderRadius.circular(24),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(icon,
                                                  color: AppColors.silver,
                                                  size: 22),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .start,
                                                  children: [
                                                    Text(
                                                      entry.description,
                                                      style: const TextStyle(
                                                        fontFamily: AppColors.bodyFontFamily,
                                                        color: AppColors.textPrimary,
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      DateFormat.yMMMd()
                                                          .format(entry.date),
                                                      style: const TextStyle(
                                                        fontFamily: AppColors.bodyFontFamily,
                                                        color: AppColors.textSecondary,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                '₹${entry.amount.toStringAsFixed(0)}',
                                                style: const TextStyle(
                                                  fontFamily: AppColors.bodyFontFamily,
                                                  color: Color(0xFF4CAF50),
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
            );
          },
        );
      },
    );
  }
}