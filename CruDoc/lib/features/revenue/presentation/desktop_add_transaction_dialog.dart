import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/errors/revenue_exceptions.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_icons.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens the desktop Add Transaction dialog (Record payment, Record
/// expense or Add pending payment). The optional `initial…` values
/// prefill the form. Returns true when the transaction was saved.
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
    builder: (_) => DesktopAddTransactionDialog(
      initialKind: initialKind,
      isPending: isPending,
      repository: repository,
      initialAmount: initialAmount,
      initialDescription: initialDescription,
      initialPayer: initialPayer,
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
  // Saved as written into the description; shown in sentence case.
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

  bool _dirty = false;
  bool _saving = false;
  bool _submitted = false;
  String? _notice;

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

  List<String> get _currentCategories => switch (_formType) {
        _TransactionFormType.income => _incomeCategories,
        _TransactionFormType.expense => _expenseCategories,
        _TransactionFormType.pending => _pendingCategories,
      };

  void _edited([Object? _]) {
    setState(() {
      _dirty = true;
      _notice = null;
    });
  }

  void _onTypeChanged(_TransactionFormType type) {
    if (type == _formType) return;
    setState(() {
      _formType = type;
      _selectedCategory = null;
      _dirty = true;
      _notice = null;
    });
  }

  void _onCategoryTap(String cat) {
    setState(() {
      final selected = _selectedCategory != cat;
      _selectedCategory = selected ? cat : null;
      if (selected && _descriptionController.text.trim().isEmpty) {
        _descriptionController.text = cat;
      }
      _dirty = true;
      _notice = null;
    });
  }

  Future<void> _pickDate() async {
    final c = context.cru;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Transaction date',
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
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = picked;
      _dirty = true;
      _notice = null;
    });
  }

  String? _validateAmount(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Add an amount.';
    final parsed = double.tryParse(t);
    if (parsed == null || parsed <= 0) return 'Enter an amount above ₹0.';
    return null;
  }

  String? _validateDescription(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Add a description.' : null;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _notice = null;
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
        _saving = false;
        _notice = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      final what = switch (_formType) {
        _TransactionFormType.income => 'this payment',
        _TransactionFormType.expense => 'this expense',
        _TransactionFormType.pending => 'this pending payment',
      };
      setState(() {
        _saving = false;
        _notice = "Couldn't save $what. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final submitLabel = switch (_formType) {
      _TransactionFormType.income => 'Record payment',
      _TransactionFormType.expense => 'Record expense',
      _TransactionFormType.pending => 'Save pending payment',
    };
    final (String payerLabel, String payerHint) = switch (_formType) {
      _TransactionFormType.income => (
          'Received from',
          'Patient, self-pay or insurer',
        ),
      _TransactionFormType.expense => (
          'Paid to',
          'Supplier, landlord or lab',
        ),
      _TransactionFormType.pending => (
          'Owed by',
          'Patient, insurer or company',
        ),
    };

    return CruFormDialog(
      title: title,
      subtitle: subtitle,
      leading: CruIconTile(icon: icon, tone: tone),
      submitLabel: submitLabel,
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Amount',
              description: 'Money in, money out, or a balance to collect.',
              children: [
                CruFieldFrame(
                  label: 'Type',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CruSegmentedControl<_TransactionFormType>(
                      semanticLabel: 'Transaction type',
                      segments: const [
                        CruSegment(_TransactionFormType.income, 'Money in'),
                        CruSegment(_TransactionFormType.expense, 'Money out'),
                        CruSegment(_TransactionFormType.pending, 'Pending'),
                      ],
                      selected: _formType,
                      onChanged: _onTypeChanged,
                    ),
                  ),
                ),
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Amount',
                      controller: _amountController,
                      autofocus: _amountController.text.isEmpty,
                      prefix: '₹',
                      hint: '0',
                      tabular: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      validator: _validateAmount,
                      onChanged: _edited,
                    ),
                    CruPickerField(
                      label: 'Date',
                      icon: CruIcons.calendar,
                      value: DateFormat('d MMM yyyy').format(_selectedDate),
                      placeholder: 'Pick a date',
                      trailing: RevenueBuilder.sameDay(
                        _selectedDate,
                        DateTime.now(),
                      )
                          ? const CruInfoPill(text: 'Today')
                          : null,
                      onTap: _pickDate,
                    ),
                  ],
                ),
              ],
            ),
            CruFormSection(
              title: 'Details',
              description: 'What it was for and who it was with.',
              children: [
                CruFieldFrame(
                  label: 'Category',
                  optional: true,
                  help: 'Picking one fills in the description.',
                  child: Wrap(
                    spacing: CruSpace.s8,
                    runSpacing: CruSpace.s8,
                    children: [
                      for (final cat in _currentCategories)
                        IntrinsicWidth(
                          child: _CategoryChip(
                            label: RevenueBuilder.sentence(cat),
                            selected: _selectedCategory == cat,
                            onTap: () => _onCategoryTap(cat),
                          ),
                        ),
                    ],
                  ),
                ),
                CruTextField(
                  label: 'Description',
                  controller: _descriptionController,
                  hint: 'Root canal consultation, gloves and masks…',
                  textCapitalization: TextCapitalization.sentences,
                  validator: _validateDescription,
                  onChanged: _edited,
                ),
                CruTextField(
                  label: payerLabel,
                  optional: true,
                  controller: _payerController,
                  hint: payerHint,
                  textCapitalization: TextCapitalization.words,
                  onChanged: _edited,
                ),
              ],
            ),
            CruFormSection(
              title: 'Notes',
              description: 'Invoice, cheque or payment reference.',
              children: [
                CruTextField(
                  label: 'Notes',
                  optional: true,
                  controller: _notesController,
                  maxLines: 3,
                  hint: 'Invoice number, cheque ID or voucher',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: _edited,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                CruIcon(CruIcons.check, size: 14, strokeWidth: 2.2, color: c.surface),
                const SizedBox(width: CruSpace.s6),
              ],
              Text(
                label,
                maxLines: 1,
                style: (selected ? CruType.subhead.w600 : CruType.subhead.w500)
                    .tint(selected ? c.surface : c.label2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
