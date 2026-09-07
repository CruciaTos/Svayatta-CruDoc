import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/errors/revenue_exceptions.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';

/// Opens the desktop-specific Add Transaction modal popup dialog.
Future<bool?> showDesktopAddTransactionDialog(
  BuildContext context, {
  TransactionKind? initialKind,
  bool isPending = false,
  RevenueRepository? repository,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 860,
          maxHeight: 740,
        ),
        child: DesktopAddTransactionDialog(
          initialKind: initialKind,
          isPending: isPending,
          repository: repository,
        ),
      ),
    ),
  );
}

enum _TransactionFormType { income, expense, pending }

class DesktopAddTransactionDialog extends StatefulWidget {
  const DesktopAddTransactionDialog({
    super.key,
    this.initialKind,
    this.isPending = false,
    this.repository,
  });

  final TransactionKind? initialKind;
  final bool isPending;
  final RevenueRepository? repository;

  @override
  State<DesktopAddTransactionDialog> createState() =>
      _DesktopAddTransactionDialogState();
}

class _DesktopAddTransactionDialogState
    extends State<DesktopAddTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final RevenueRepository _repository =
      widget.repository ?? RevenueRepository();

  late _TransactionFormType _formType;
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _payerController;
  late final TextEditingController _notesController;

  DateTime _selectedDate = DateTime.now();
  String? _selectedCategory;
  bool _isSaving = false;
  String? _errorText;

  static const List<String> _incomeCategories = [
    'Consultation Fee',
    'Procedure / Treatment',
    'Follow-up Visit',
    'Diagnostic / Lab',
    'Pharmacy Sale',
    'Package Advance',
    'Other Revenue',
  ];

  static const List<String> _expenseCategories = [
    'Medical Supplies',
    'Medication Restock',
    'Clinic Rent',
    'Utilities & Electric',
    'Staff Salary',
    'Equipment & Maintenance',
    'Software / Tech',
    'Other Expense',
  ];

  static const List<String> _pendingCategories = [
    'Pending Visit Payment',
    'Pending Lab Test',
    'Procedure Balance',
    'Insurance Claim Due',
    'Corporate Billing',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isPending) {
      _formType = _TransactionFormType.pending;
    } else if (widget.initialKind == TransactionKind.expense) {
      _formType = _TransactionFormType.expense;
    } else {
      _formType = _TransactionFormType.income;
    }

    _amountController = TextEditingController();
    _descriptionController = TextEditingController();
    _payerController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _payerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  List<String> get _currentCategories {
    switch (_formType) {
      case _TransactionFormType.income:
        return _incomeCategories;
      case _TransactionFormType.expense:
        return _expenseCategories;
      case _TransactionFormType.pending:
        return _pendingCategories;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final description = _descriptionController.text.trim();
    final payer = _payerController.text.trim();
    final notes = _notesController.text.trim();
    final now = DateTime.now();

    try {
      if (_formType == _TransactionFormType.pending) {
        await _repository.createPendingPayment(
          PendingPayment(
            id: '',
            doctorId: '',
            date: _selectedDate,
            description: description,
            amount: amount,
            isPaid: false,
            payer: payer.isEmpty ? null : payer,
            notes: notes.isEmpty ? null : notes,
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        final kind = _formType == _TransactionFormType.income
            ? TransactionKind.income
            : TransactionKind.expense;

        final fullDesc = notes.isEmpty ? description : '$description ($notes)';

        await _repository.createRevenueEntry(
          RevenueEntry(
            id: '',
            doctorId: '',
            date: _selectedDate,
            description: fullDesc,
            amount: amount,
            type: RevenueType.miscellaneous,
            kind: kind,
            payer: payer.isEmpty ? null : payer,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RevenueValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = 'Failed to save transaction: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Type selection, Amount, Date
                      Expanded(
                        flex: 11,
                        child: _buildLeftColumn(),
                      ),
                      const SizedBox(width: 24),
                      // Divider
                      Container(
                        width: 1,
                        height: 520,
                        color: const Color(0xFFF1F5F9),
                      ),
                      const SizedBox(width: 24),
                      // Right Column: Category, Payer/Payee, Description, Preview
                      Expanded(
                        flex: 10,
                        child: _buildRightColumn(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_errorText != null) _buildErrorBanner(),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    Color iconBg;
    IconData iconData;
    String titleText;
    String subtitleText;

    switch (_formType) {
      case _TransactionFormType.income:
        iconBg = const Color(0xFF059669);
        iconData = Icons.arrow_downward_rounded;
        titleText = 'Record Income';
        subtitleText = 'Log patient fees, clinic earnings, or miscellaneous cash inflows';
        break;
      case _TransactionFormType.expense:
        iconBg = const Color(0xFFDC2626);
        iconData = Icons.arrow_upward_rounded;
        titleText = 'Record Expense';
        subtitleText = 'Track operational costs, medical supplies, salaries, and clinic bills';
        break;
      case _TransactionFormType.pending:
        iconBg = const Color(0xFFD97706);
        iconData = Icons.pending_actions_rounded;
        titleText = 'Add Pending Payment';
        subtitleText = 'Schedule outstanding patient receivables or unpaid balances to collect';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              iconData,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TRANSACTION TYPE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTypeCard(
                type: _TransactionFormType.income,
                title: 'Income',
                desc: 'Payment In',
                icon: Icons.arrow_downward_rounded,
                activeColor: const Color(0xFF059669),
                activeBg: const Color(0xFFECFDF5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTypeCard(
                type: _TransactionFormType.expense,
                title: 'Expense',
                desc: 'Payment Out',
                icon: Icons.arrow_upward_rounded,
                activeColor: const Color(0xFFDC2626),
                activeBg: const Color(0xFFFEF2F2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTypeCard(
                type: _TransactionFormType.pending,
                title: 'Pending',
                desc: 'Awaiting',
                icon: Icons.pending_actions_rounded,
                activeColor: const Color(0xFFD97706),
                activeBg: const Color(0xFFFFFBEB),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'AMOUNT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 14, right: 8),
              child: Center(
                widthFactor: 0.0,
                child: Text(
                  '₹',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ),
            hintText: '0.00',
            hintStyle: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Color(0xFFCBD5E1),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) return 'Enter an amount';
            final parsed = double.tryParse(val.trim());
            if (parsed == null || parsed <= 0) return 'Enter a valid amount > 0';
            return null;
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'DATE OF TRANSACTION',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedDate.year == DateTime.now().year &&
                                _selectedDate.month == DateTime.now().month &&
                                _selectedDate.day == DateTime.now().day
                            ? 'Today'
                            : DateFormat('MMM dd').format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'INTERNAL NOTES (OPTIONAL)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _notesController,
          maxLines: 3,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            hintText: 'Add invoice number, check ID, payment method reference, or voucher details...',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeCard({
    required _TransactionFormType type,
    required String title,
    required String desc,
    required IconData icon,
    required Color activeColor,
    required Color activeBg,
  }) {
    final isSelected = _formType == type;

    return InkWell(
      onTap: () {
        setState(() {
          _formType = type;
          _selectedCategory = null;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? activeColor : const Color(0xFF64748B),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: activeColor,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? activeColor : const Color(0xFF1E293B),
              ),
            ),
            Text(
              desc,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? activeColor.withValues(alpha: 0.8) : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightColumn() {
    final payerLabel = _formType == _TransactionFormType.expense
        ? 'PAID TO (SUPPLIER / VENDOR / PAYEE)'
        : 'RECEIVED FROM (PATIENT / CLIENT / PAYER)';
    final payerHint = _formType == _TransactionFormType.expense
        ? 'e.g. Apex Dental Supplies, Landlord, Lab Co.'
        : 'e.g. John Doe, Self-pay, Insurance Provider';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CATEGORY PRESETS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _currentCategories.map((cat) {
            final isSelected = _selectedCategory == cat;
            return ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCategory = selected ? cat : null;
                  if (selected && _descriptionController.text.trim().isEmpty) {
                    _descriptionController.text = cat;
                  }
                });
              },
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
              selectedColor: const Color(0xFF1E293B),
              backgroundColor: const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : const Color(0xFFE2E8F0),
                ),
              ),
              showCheckmark: false,
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text(
          'DESCRIPTION / TITLE *',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _descriptionController,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'e.g. Root canal therapy consultation, Clinic sanitization supplies...',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
          validator: (val) =>
              (val == null || val.trim().isEmpty) ? 'Please enter a description' : null,
        ),
        const SizedBox(height: 20),
        Text(
          payerLabel,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _payerController,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: payerHint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Live Preview Box
        _buildTransactionSummaryCard(),
      ],
    );
  }

  Widget _buildTransactionSummaryCard() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final desc = _descriptionController.text.trim().isEmpty
        ? 'Untitled Transaction'
        : _descriptionController.text.trim();
    final payer = _payerController.text.trim();

    Color badgeColor;
    String typeLabel;
    switch (_formType) {
      case _TransactionFormType.income:
        badgeColor = const Color(0xFF059669);
        typeLabel = '+ INCOME INFLOW';
        break;
      case _TransactionFormType.expense:
        badgeColor = const Color(0xFFDC2626);
        typeLabel = '- EXPENSE OUTFLOW';
        break;
      case _TransactionFormType.pending:
        badgeColor = const Color(0xFFD97706);
        typeLabel = '⌛ PENDING RECEIVABLE';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                '₹${NumberFormat('#,##0.00').format(amount)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: badgeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (payer.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Party: $payer',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorText!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    String actionLabel;
    Color buttonColor;
    switch (_formType) {
      case _TransactionFormType.income:
        actionLabel = 'Record Income';
        buttonColor = const Color(0xFF059669);
        break;
      case _TransactionFormType.expense:
        actionLabel = 'Record Expense';
        buttonColor = const Color(0xFFDC2626);
        break;
      case _TransactionFormType.pending:
        actionLabel = 'Save Pending Payment';
        buttonColor = const Color(0xFFD97706);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _isSaving ? null : _handleSave,
            style: FilledButton.styleFrom(
              backgroundColor: buttonColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        actionLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
