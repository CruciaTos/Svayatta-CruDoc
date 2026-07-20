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
  TransactionKind? _kindFilter = null; // null = show all

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

    var filtered = entries
        .where((e) =>
            e.date.isAfter(startDate) || e.date.isAtSameMomentAs(startDate))
        .toList();

    // Apply kind filter if set
    if (_kindFilter != null) {
      filtered = filtered.where((e) => e.kind == _kindFilter).toList();
    }

    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  RevenueEntry? _lastPaidEntry(List<RevenueEntry> entries) {
    final paid = entries.where((e) => e.payer != null).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return paid.isNotEmpty ? paid.first : null;
  }

  Future<void> _showEntryDialog({
    required String title,
    required String descHint,
    required Future<void> Function(String description, double amount, TransactionKind kind) onSubmit,
    TransactionKind initialKind = TransactionKind.income,
    bool includeKindSelector = false,
  }) async {
    final descController = TextEditingController();
    final amountController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (_) {
        TransactionKind selectedKind = initialKind;
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
                await onSubmit(desc, amount, selectedKind);
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
                borderRadius: BorderRadius.circular(24),
              ),
              backgroundColor: AppColors.cardSurface,
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppColors.sectionHeading.copyWith(fontSize: 20)),
                  const SizedBox(height: 4),
                  Text(
                    'Use a short description and the exact amount to save quickly.',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  if (includeKindSelector) ...[
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
                        selectedKind == TransactionKind.income,
                        selectedKind == TransactionKind.expense,
                      ],
                      onPressed: isSaving
                          ? null
                          : (index) {
                              setDialogState(() {
                                selectedKind = index == 0
                                    ? TransactionKind.income
                                    : TransactionKind.expense;
                              });
                            },
                      borderRadius: BorderRadius.circular(16),
                      selectedColor: Colors.white,
                      fillColor: selectedKind == TransactionKind.income
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
                    'Amount',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountController,
                    enabled: !isSaving,
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
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
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
                      color: AppColors.slateBlue,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: isSaving ? null : handleSubmit,
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
                  child: isSaving
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
            );
          },
        );
      },
    );

    descController.dispose();
    amountController.dispose();
  }

  Future<void> _showAddTransactionDialog() {
    return _showEntryDialog(
      title: 'Add Transaction',
      descHint: 'Description',
      includeKindSelector: true,
      onSubmit: (desc, amount, kind) async {
        final now = DateTime.now();
        await _repository.createRevenueEntry(
          RevenueEntry(
            id: '',
            date: now,
            description: desc,
            amount: amount,
            type: RevenueType.miscellaneous,
            kind: kind,
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kind == TransactionKind.income
                  ? 'Income recorded'
                  : 'Expense recorded',
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddPendingDialog() {
    return _showEntryDialog(
      title: 'Add Pending Payment',
      descHint: 'Description (e.g. "Lab test")',
      includeKindSelector: false,
      onSubmit: (desc, amount, _) async {
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

            // Split totals
            final totalIncome = filtered
                .where((e) => e.kind == TransactionKind.income)
                .fold<double>(0, (sum, e) => sum + e.amount);
            final totalExpenses = filtered
                .where((e) => e.kind == TransactionKind.expense)
                .fold<double>(0, (sum, e) => sum + e.amount);
            final net = totalIncome - totalExpenses;

            final lastPaid = _lastPaidEntry(allEntries);

            return Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: stillLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.beige,
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        'Revenue',
                                        style: AppColors.pageHeading.copyWith(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            // Gradient summary card – income only, as decided
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF1E78FF),
                                    Color(0xFF5BA6FF)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x33000000),
                                    blurRadius: 16,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              'Total income',
                                              style: TextStyle(
                                                fontFamily:
                                                    AppColors.bodyFontFamily,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white70,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '₹${totalIncome.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontFamily:
                                                    AppColors.bodyFontFamily,
                                                fontSize: 32,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.18,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(18),
                                        ),
                                        child: const Icon(
                                          Icons.account_balance_wallet_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: <Widget>[
                                      // Time filter chip (already existing)
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.16,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: Row(
                                            children: <Widget>[
                                              const Icon(
                                                Icons.calendar_month_rounded,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                _selectedFilter,
                                                style: const TextStyle(
                                                  fontFamily:
                                                      AppColors.bodyFontFamily,
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Expenses compact chip
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.16,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: Row(
                                            children: <Widget>[
                                              const Icon(
                                                Icons.trending_down_rounded,
                                                color: Colors.white70,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Expenses ₹${totalExpenses.toStringAsFixed(0)}',
                                                style: const TextStyle(
                                                  fontFamily:
                                                      AppColors.bodyFontFamily,
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Last paid chip (keep or remove? I kept it, but now there are three chips. Should be fine)
                                      if (lastPaid != null)
                                        Expanded(
                                          child: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.16,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                Text(
                                                  'Last paid',
                                                  style: TextStyle(
                                                    fontFamily:
                                                        AppColors.bodyFontFamily,
                                                    fontSize: 11,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${lastPaid.payer ?? 'Unknown'} • ${DateFormat.yMMMd().format(lastPaid.date)}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontFamily:
                                                        AppColors.bodyFontFamily,
                                                    fontSize: 12,
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w600,
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
                            // Net row below the card
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                    color: AppColors.textSecondary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Net',
                                    style: TextStyle(
                                      fontFamily: AppColors.bodyFontFamily,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '₹${net >= 0 ? '+' : ''}${net.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontFamily: AppColors.bodyFontFamily,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: net >= 0 ? const Color(0xFF2E7D32) : AppColors.negativeRed,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Pending payments section unchanged
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  'Pending payments',
                                  style: AppColors.pageHeading.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _showAddPendingDialog,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Add'),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        AppColors.chartBarLight,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (pendingPayments.isEmpty)
                              GestureDetector(
                                onTap: _showAddPendingDialog,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardSurface,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: AppColors.chartBarDim.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.chartBarLight,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.hourglass_empty_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            const Text(
                                              'No pending items',
                                              style: TextStyle(
                                                fontFamily:
                                                    AppColors.bodyFontFamily,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Create a pending payment card to follow upcoming collections.',
                                              style: TextStyle(
                                                fontFamily:
                                                    AppColors.bodyFontFamily,
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                height: 170,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: pendingPayments.length,
                                  itemBuilder: (_, index) {
                                    final pending = pendingPayments[index];
                                    return Container(
                                      width: 190,
                                      margin: const EdgeInsets.only(right: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppColors.cardSurface,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: Colors.amber.withValues(
                                            alpha: 0.35,
                                          ),
                                          width: 1,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black12,
                                            blurRadius: 8,
                                            offset: Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Row(
                                            children: <Widget>[
                                              Expanded(
                                                child: Text(
                                                  '₹${pending.amount.toStringAsFixed(0)}',
                                                  style: const TextStyle(
                                                    fontFamily: AppColors
                                                        .bodyFontFamily,
                                                    color: Colors.amber,
                                                    fontSize: 23,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () =>
                                                    _markAsPaid(pending),
                                                child: const Icon(
                                                  Icons.check_circle_outline,
                                                  size: 20,
                                                  color: Color(0xFF4CAF50),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          Text(
                                            pending.description,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              fontFamily:
                                                  AppColors.headingFontFamily,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat.yMMMd()
                                                .format(pending.date),
                                            style: const TextStyle(
                                              fontFamily:
                                                  AppColors.bodyFontFamily,
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 8),
                            // Kind filter chips
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  _KindFilterChip(
                                    label: 'All',
                                    selected: _kindFilter == null,
                                    onSelected: () => setState(() => _kindFilter = null),
                                  ),
                                  const SizedBox(width: 8),
                                  _KindFilterChip(
                                    label: 'Income',
                                    selected: _kindFilter == TransactionKind.income,
                                    selectedColor: AppColors.positiveGreen,
                                    onSelected: () => setState(() => _kindFilter = TransactionKind.income),
                                  ),
                                  const SizedBox(width: 8),
                                  _KindFilterChip(
                                    label: 'Expense',
                                    selected: _kindFilter == TransactionKind.expense,
                                    selectedColor: AppColors.negativeRed,
                                    onSelected: () => setState(() => _kindFilter = TransactionKind.expense),
                                  ),
                                ],
                              ),
                            ),
                            // Recent transactions header + list
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  'Recent transactions',
                                  style: AppColors.pageHeading.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _showAddTransactionDialog,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Add'),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        AppColors.chartBarLight,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (filtered.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: AppColors.cardSurface,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Center(
                                  child: Text(
                                    'No transactions for this period',
                                    style: TextStyle(
                                      fontFamily: AppColors.bodyFontFamily,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final entry = filtered[index];
                                  final isExpense = entry.kind == TransactionKind.expense;

                                  IconData icon;
                                  Color avatarBackground;
                                  Color iconColor;
                                  if (isExpense) {
                                    icon = Icons.money_off;
                                    avatarBackground = AppColors.negativeRed.withValues(alpha: 0.15);
                                    iconColor = AppColors.negativeRed;
                                  } else {
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
                                    avatarBackground = AppColors.chartBarDim;
                                    iconColor = Colors.white;
                                  }

                                  final amountColor = isExpense
                                      ? AppColors.negativeRed
                                      : const Color(0xFF2E7D32);
                                  final amountPrefix = isExpense ? '−' : '+';

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.cardSurface,
                                      borderRadius: BorderRadius.circular(22),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: avatarBackground,
                                          child: Icon(
                                            icon,
                                            color: iconColor,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                entry.description,
                                                style: const TextStyle(
                                                  fontFamily:
                                                      AppColors.bodyFontFamily,
                                                  color: AppColors.textPrimary,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                DateFormat.yMMMd()
                                                    .format(entry.date),
                                                style: const TextStyle(
                                                  fontFamily:
                                                      AppColors.bodyFontFamily,
                                                  color: AppColors.textSecondary,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '$amountPrefix₹${entry.amount.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontFamily:
                                                AppColors.bodyFontFamily,
                                            color: amountColor,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
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

/// Simple filter chip styled for the revenue screen.
class _KindFilterChip extends StatelessWidget {
  const _KindFilterChip({
    required this.label,
    required this.selected,
    this.selectedColor,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final Color? selectedColor;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final effectiveSelectedColor = selectedColor ?? AppColors.chartBarLight;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: AppColors.bodyFontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppColors.textSecondary,
        ),
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      backgroundColor: AppColors.cardSurface,
      selectedColor: effectiveSelectedColor,
      side: BorderSide(
        color: selected ? effectiveSelectedColor : AppColors.silver.withValues(alpha: 0.4),
        width: 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}