import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/errors/revenue_exceptions.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/presentation/transaction_details.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';
import 'package:doctor_management_app/features/revenue/widgets/expense_tile.dart';
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

  static const List<String> _filterOptions = [
    'Today',
    'Weekly',
    'Monthly',
    'Yearly',
    'Lifetime',
  ];

  String _selectedFilter = 'Weekly';
  TransactionKind? _kindFilter = null; // null = show all
  double _chevronAngle = 0.0; // for animated rotation

  void _cycleFilter() {
    setState(() {
      final idx = _filterOptions.indexOf(_selectedFilter);
      _selectedFilter = _filterOptions[(idx + 1) % _filterOptions.length];
      _chevronAngle += 0.5; // rotate 180° on each tap
    });
  }

  List<RevenueEntry> _filterEntries(List<RevenueEntry> entries) {
    final now = DateTime.now();
    DateTime startDate;
    switch (_selectedFilter) {
      case 'Today':
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case 'Weekly':
        startDate = now.subtract(const Duration(days: 7));
        break;
      case 'Monthly':
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 'Yearly':
        startDate = DateTime(now.year, 1, 1);
        break;
      case 'Lifetime':
        startDate = DateTime(2000); // shows all entries
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

  // ────────────────────────────────────────────────────────────
  // NEW: Unified modal bottom sheet for adding transactions
  // ────────────────────────────────────────────────────────────
  Future<void> _showAddTransactionSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: AppColors.cardSurface,
      builder: (_) => const _TransactionFormSheet(
        includeKindToggle: true,
        includePayerField: true,
        title: 'Add Transaction',
      ),
    ).then((_) {
      // Refresh the screen after the sheet is closed (handled by StreamBuilder)
    });
  }

  Future<void> _showAddPendingSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: AppColors.cardSurface,
      builder: (_) => const _TransactionFormSheet(
        includeKindToggle: false,
        includePayerField: false,
        title: 'Add Pending Payment',
      ),
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
    } catch (e, stackTrace) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      debugPrint('Error marking pending as paid: $e\n$stackTrace');
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
                        child: RepaintBoundary(
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
                              // Gradient summary card – net revenue
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
                                                'Net revenue',
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
                                                '₹${net.toStringAsFixed(0)}',
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
                                    // Time filter pill
                                    Row(
                                      children: <Widget>[
                                        Flexible(
                                          child: Material(
                                            color: Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: InkWell(
                                              onTap: _cycleFilter,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              splashColor: Colors.white
                                                  .withValues(alpha: 0.3),
                                              highlightColor: Colors.white
                                                  .withValues(alpha: 0.1),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.16),
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: <Widget>[
                                                    const Icon(
                                                      Icons
                                                          .calendar_month_rounded,
                                                      color: Colors.white,
                                                      size: 16,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      _selectedFilter,
                                                      style: const TextStyle(
                                                        fontFamily: AppColors
                                                            .bodyFontFamily,
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    AnimatedRotation(
                                                      turns: _chevronAngle,
                                                      duration:
                                                          const Duration(
                                                              milliseconds:
                                                                  300),
                                                      child: const Icon(
                                                        Icons.arrow_drop_down,
                                                        color: Colors.white70,
                                                        size: 18,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Pending payments section
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
                                    onPressed: _showAddPendingSheet,
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
                                  onTap: _showAddPendingSheet,
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
                                      onSelected: () =>
                                          setState(() => _kindFilter = null),
                                    ),
                                    const SizedBox(width: 8),
                                    _KindFilterChip(
                                      label: 'Income',
                                      selected:
                                          _kindFilter == TransactionKind.income,
                                      selectedColor: AppColors.positiveGreen,
                                      onSelected: () => setState(() =>
                                          _kindFilter = TransactionKind.income),
                                    ),
                                    const SizedBox(width: 8),
                                    _KindFilterChip(
                                      label: 'Expense',
                                      selected:
                                          _kindFilter == TransactionKind.expense,
                                      selectedColor: AppColors.negativeRed,
                                      onSelected: () => setState(() =>
                                          _kindFilter = TransactionKind.expense),
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
                                    onPressed: _showAddTransactionSheet,
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
                                    return TransactionTile(
                                      entry: entry,
                                      onTap: () {
                                        FocusScope.of(context).unfocus();
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (!mounted) return;
                                          try {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    TransactionDetailsPage(
                                                      entry: entry,
                                                    ),
                                              ),
                                            );
                                          } catch (e, stack) {
                                            debugPrint(
                                                'Navigation error: $e\n$stack');
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Error opening details: $e'),
                                              ),
                                            );
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                            ],
                          ),
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
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      backgroundColor: AppColors.cardSurface,
      selectedColor: effectiveSelectedColor,
      side: BorderSide(
        color: selected
            ? effectiveSelectedColor
            : AppColors.silver.withValues(alpha: 0.4),
        width: 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

// ────────────────────────────────────────────────────────────
// NEW: Self‑contained bottom sheet form widget
// ────────────────────────────────────────────────────────────
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
        // Regular transaction
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
        // Pending payment
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
            // Handle bar
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

            // Kind toggle (only for regular transactions)
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

            // Payer field (conditional)
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

            // Description
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

            // Amount
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

            // Date picker
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

            // Action buttons
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