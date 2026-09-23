import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/errors/revenue_exceptions.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_icons.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// Dialog frame. Not tokens yet; see NEEDS.md (Builder 4).
const double _dialogMaxWidth = 860;
const double _dialogMaxHeight = 740;

/// Opens the desktop Add Transaction dialog (Record payment, Record
/// expense or Add pending payment). The optional `initial…` values
/// prefill the form.
Future<bool?> showDesktopAddTransactionDialog(
  BuildContext context, {
  TransactionKind? initialKind,
  bool isPending = false,
  RevenueRepository? repository,
  double? initialAmount,
  String? initialDescription,
  String? initialPayer,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final c = ctx.cru;
      return Dialog(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface.withValues(alpha: 0),
        shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(CruSpace.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _dialogMaxWidth,
            maxHeight: _dialogMaxHeight,
          ),
          child: DesktopAddTransactionDialog(
            initialKind: initialKind,
            isPending: isPending,
            repository: repository,
            initialAmount: initialAmount,
            initialDescription: initialDescription,
            initialPayer: initialPayer,
          ),
        ),
      );
    },
  );
}

enum _TransactionFormType { income, expense, pending }

class DesktopAddTransactionDialog extends StatefulWidget {
  const DesktopAddTransactionDialog({
    super.key,
    this.initialKind,
    this.isPending = false,
    this.repository,
    this.initialAmount,
    this.initialDescription,
    this.initialPayer,
  });

  final TransactionKind? initialKind;
  final bool isPending;
  final RevenueRepository? repository;
  final double? initialAmount;
  final String? initialDescription;
  final String? initialPayer;

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

    final amount = widget.initialAmount;
    _amountController = TextEditingController(
      text: amount == null || amount <= 0
          ? ''
          : (amount == amount.roundToDouble()
              ? amount.toStringAsFixed(0)
              : amount.toStringAsFixed(2)),
    );
    _descriptionController =
        TextEditingController(text: widget.initialDescription ?? '');
    _payerController = TextEditingController(text: widget.initialPayer ?? '');
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
    final c = context.cru;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: c.accent,
                  onPrimary: c.onAccent,
                  surface: c.surface,
                  onSurface: c.label,
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
        _errorText = "Couldn't save the transaction: $e";
      });
    }
  }

  // -------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const CruSeparator(),
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CruSpace.s24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: type, amount, date, notes.
                  Expanded(flex: 11, child: _buildLeftColumn()),
                  const SizedBox(width: CruSpace.s24),
                  // Right: category, description, paid to / received
                  // from, preview; split off by a separator.
                  Expanded(
                    flex: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: context.cru.separator),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: CruSpace.s24),
                        child: _buildRightColumn(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_errorText != null) _buildErrorBanner(),
        const CruSeparator(),
        _buildFooter(),
      ],
    );
  }

  Widget _buildHeader() {
    final c = context.cru;
    final (CruIconData icon, CruTileTone tone, String title, String subtitle) =
        switch (_formType) {
      _TransactionFormType.income => (
          CruIcons.rupee,
          CruTileTone.green,
          'Record payment',
          'Patient fees, clinic earnings or other money received',
        ),
      _TransactionFormType.expense => (
          RevenueIcons.receipt,
          CruTileTone.neutral,
          'Record expense',
          'Supplies, salaries, rent and other clinic costs',
        ),
      _TransactionFormType.pending => (
          CruIcons.clock,
          CruTileTone.amber,
          'Add pending payment',
          'An unpaid balance to collect later',
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s24,
        CruSpace.s20,
        CruSpace.s20,
        CruSpace.s20,
      ),
      child: Row(
        children: [
          CruIconTile(icon: icon, tone: tone),
          const SizedBox(width: CruSpace.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: CruType.title2.tint(c.label)),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(subtitle, style: CruType.subhead.tint(c.label2)),
              ],
            ),
          ),
          CruSquareButton(
            icon: CruIcons.close,
            iconSize: 16,
            strokeWidth: 2.2,
            semanticLabel: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftColumn() {
    final c = context.cru;
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Type'),
        const SizedBox(height: CruSpace.s8),
        CruSegmentedControl<_TransactionFormType>(
          semanticLabel: 'Transaction type',
          segments: const [
            CruSegment(_TransactionFormType.income, 'Money in'),
            CruSegment(_TransactionFormType.expense, 'Money out'),
            CruSegment(_TransactionFormType.pending, 'Pending'),
          ],
          selected: _formType,
          onChanged: (type) => setState(() {
            _formType = type;
            _selectedCategory = null;
          }),
        ),
        const SizedBox(height: CruSpace.s24),
        const _FieldLabel('Amount'),
        const SizedBox(height: CruSpace.s8),
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: CruType.title2.tabular.tint(c.label),
          cursorColor: c.accent,
          onChanged: (_) => setState(() {}),
          decoration: _decoration(context, hint: '0').copyWith(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(
                left: CruSpace.s14,
                right: CruSpace.s8,
              ),
              child: Text('₹', style: CruType.title2.tint(c.label2)),
            ),
            prefixIconConstraints: const BoxConstraints(),
            hintStyle: CruType.title2.tabular.tint(c.label3),
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) return 'Enter an amount';
            final parsed = double.tryParse(val.trim());
            if (parsed == null || parsed <= 0) {
              return 'Enter an amount above ₹0';
            }
            return null;
          },
        ),
        const SizedBox(height: CruSpace.s24),
        const _FieldLabel('Date'),
        const SizedBox(height: CruSpace.s8),
        CruPressable(
          onTap: _pickDate,
          scaleOnPress: false,
          semanticLabel: 'Date, ${DashFormat.dateLine(_selectedDate)}',
          builder: (context, hovered) => AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s14,
              vertical: CruSpace.s12,
            ),
            decoration: ShapeDecoration(
              color: hovered ? cruHoverShade(c.inset, c) : c.inset,
              shape: cruShape(CruRadius.control),
            ),
            child: Row(
              children: [
                CruIcon(CruIcons.calendar, size: 18, color: c.label2),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE, d MMMM y').format(_selectedDate),
                        style: CruType.callout.tabular.tint(c.label),
                      ),
                      Text(
                        isToday
                            ? 'Today'
                            : DateFormat('d MMM').format(_selectedDate),
                        style: CruType.caption.tabular.tint(c.label2),
                      ),
                    ],
                  ),
                ),
                CruIcon(CruIcons.chevronRight, size: 18, color: c.label3),
              ],
            ),
          ),
        ),
        const SizedBox(height: CruSpace.s24),
        const _FieldLabel('Notes (optional)'),
        const SizedBox(height: CruSpace.s8),
        TextFormField(
          controller: _notesController,
          maxLines: 3,
          style: CruType.text.tint(c.label),
          cursorColor: c.accent,
          decoration: _decoration(
            context,
            hint: 'Invoice number, cheque ID, payment reference or voucher',
          ),
        ),
      ],
    );
  }

  Widget _buildRightColumn() {
    final c = context.cru;
    final payerLabel = _formType == _TransactionFormType.expense
        ? 'Paid to (supplier, vendor or payee)'
        : 'Received from (patient, client or payer)';
    final payerHint = _formType == _TransactionFormType.expense
        ? 'e.g. Apex Dental Supplies, landlord, lab'
        : 'e.g. patient name, self-pay, insurer';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Category'),
        const SizedBox(height: CruSpace.s8),
        Wrap(
          spacing: CruSpace.s8,
          runSpacing: CruSpace.s8,
          children: [
            for (final cat in _currentCategories)
              _CategoryChip(
                label: cat,
                selected: _selectedCategory == cat,
                onTap: () => setState(() {
                  final selected = _selectedCategory != cat;
                  _selectedCategory = selected ? cat : null;
                  if (selected && _descriptionController.text.trim().isEmpty) {
                    _descriptionController.text = cat;
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: CruSpace.s20),
        const _FieldLabel('Description'),
        const SizedBox(height: CruSpace.s8),
        TextFormField(
          controller: _descriptionController,
          style: CruType.text.tint(c.label),
          cursorColor: c.accent,
          onChanged: (_) => setState(() {}),
          decoration: _decoration(
            context,
            hint: 'e.g. Root canal consultation, sanitisation supplies',
          ),
          validator: (val) => (val == null || val.trim().isEmpty)
              ? 'Enter a description'
              : null,
        ),
        const SizedBox(height: CruSpace.s20),
        _FieldLabel(payerLabel),
        const SizedBox(height: CruSpace.s8),
        TextFormField(
          controller: _payerController,
          style: CruType.text.tint(c.label),
          cursorColor: c.accent,
          onChanged: (_) => setState(() {}),
          decoration: _decoration(context, hint: payerHint),
        ),
        const SizedBox(height: CruSpace.s24),
        // Live preview.
        _buildTransactionSummaryCard(),
      ],
    );
  }

  Widget _buildTransactionSummaryCard() {
    final c = context.cru;
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final desc = _descriptionController.text.trim().isEmpty
        ? 'Untitled transaction'
        : _descriptionController.text.trim();
    final payer = _payerController.text.trim();

    final (String label, Color fill, Color fg) = switch (_formType) {
      _TransactionFormType.income => ('Money in', c.greenTint, c.greenText),
      _TransactionFormType.expense => ('Money out', c.inset, c.label2),
      _TransactionFormType.pending => ('Pending', c.amberTint, c.amberText),
    };
    final money = DashFormat.rupees(amount);

    return Container(
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: ShapeDecoration(
        color: c.canvas,
        shape: cruShape(CruRadius.panel, side: BorderSide(color: c.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CruPill(text: label, background: fill, foreground: fg),
              const Spacer(),
              Text(
                _formType == _TransactionFormType.expense ? '−$money' : money,
                style: CruType.row.tabular.tint(c.label),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s10),
          Text(
            desc,
            style: CruType.callout.tint(c.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (payer.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s4),
            Text(
              _formType == _TransactionFormType.expense
                  ? 'Paid to $payer'
                  : 'Received from $payer',
              style: CruType.caption.tint(c.label2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    final c = context.cru;
    // Amber, not red: red is reserved for allergies.
    return Container(
      margin: const EdgeInsets.fromLTRB(
        CruSpace.s24,
        0,
        CruSpace.s24,
        CruSpace.s12,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s14,
        vertical: CruSpace.s10,
      ),
      decoration: ShapeDecoration(
        color: c.amberTint,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          CruIcon(CruIcons.warning, size: 18, color: c.amberText),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: Text(
              _errorText!,
              style: CruType.subhead.w500.tint(c.amberText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final actionLabel = switch (_formType) {
      _TransactionFormType.income => 'Record payment',
      _TransactionFormType.expense => 'Record expense',
      _TransactionFormType.pending => 'Save pending payment',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s24,
        vertical: CruSpace.s16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          CruButton(
            label: 'Cancel',
            kind: CruButtonKind.secondary,
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: CruSpace.s10),
          CruButton(
            label: _isSaving ? 'Saving…' : actionLabel,
            icon: _isSaving ? null : CruIcons.check,
            onPressed: _isSaving ? null : _handleSave,
          ),
        ],
      ),
    );
  }
}

/// Inset field: fill, radius 12, accent ring on focus, amber errors.
InputDecoration _decoration(BuildContext context, {String? hint}) {
  final c = context.cru;
  OutlineInputBorder border([Color? color, double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(CruRadius.control),
        borderSide: color == null
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: CruType.text.tint(c.label3),
    filled: true,
    fillColor: c.inset,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: CruSpace.s14,
      vertical: CruSpace.s12,
    ),
    border: border(),
    enabledBorder: border(),
    focusedBorder: border(c.accent, 1.5),
    errorBorder: border(c.amber),
    focusedErrorBorder: border(c.amber, 1.5),
    errorStyle: CruType.caption.w500.tint(c.amberText),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: CruType.subhead.w500.tint(context.cru.label2));
}

/// A category preset: inset capsule, filled with the label colour when
/// chosen.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.chip,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected
                ? c.label
                : hovered
                    ? cruHoverShade(c.inset, c)
                    : c.inset,
            shape: const StadiumBorder(),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: (selected ? CruType.subhead.w600 : CruType.subhead.w500)
                .tint(selected ? c.surface : c.label2),
          ),
        ),
      ),
    );
  }
}
