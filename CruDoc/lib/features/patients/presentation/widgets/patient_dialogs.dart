import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the Record payment dialog returns.
class PaymentInput {
  const PaymentInput(this.amount, this.note);
  final double amount;
  final String note;
}

/// Amount (prefilled with the balance, 0 < x ≤ balance) and an
/// optional note. Pops a [PaymentInput].
class RecordPaymentDialog extends StatefulWidget {
  const RecordPaymentDialog({super.key, required this.summary});
  final PatientSummary summary;

  @override
  State<RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<RecordPaymentDialog> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  String? _error;

  double get _balance => widget.summary.balance;

  @override
  void initState() {
    super.initState();
    final b = _balance;
    _amount = TextEditingController(
      text: b <= 0
          ? ''
          : (b == b.roundToDouble() ? '${b.toInt()}' : b.toStringAsFixed(2)),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _amount.text.replaceAll(RegExp(r'[₹,\s]'), '');
    final value = double.tryParse(raw);
    String? error;
    if (value == null || value <= 0) {
      error = 'Enter an amount above ₹0.';
    } else if (_balance > 0 && value > _balance) {
      error = 'That is more than the ${PatientFormat.rupees(_balance)} due.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(PaymentInput(value!, _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return PatientDialog(
      title: 'Record payment',
      cancelLabel: 'Cancel',
      confirmLabel: 'Record payment',
      onConfirm: _submit,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.summary.name} · ${PatientFormat.rupees(_balance)} due',
            style: CruType.text.tabular.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s16),
          const _FieldLabel('Amount'),
          const SizedBox(height: CruSpace.s6),
          _CruField(
            controller: _amount,
            autofocus: true,
            prefix: '₹',
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: CruSpace.s6),
            Text(_error!, style: CruType.caption.w500.tint(c.amberText)),
          ],
          const SizedBox(height: CruSpace.s14),
          const _FieldLabel('Note (optional)'),
          const SizedBox(height: CruSpace.s6),
          _CruField(
            controller: _note,
            hint: 'Cash, UPI, card…',
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: CruType.subhead.w500.tint(context.cru.label2));
}

/// A 44 px inset text field, radius 12.
class _CruField extends StatelessWidget {
  const _CruField({
    required this.controller,
    this.hint,
    this.prefix,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hint;
  final String? prefix;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: CruSize.actionButton,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (prefix != null) ...[
            Text(prefix!, style: CruType.input.w500.tint(c.label2)),
            const SizedBox(width: CruSpace.s4),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              onSubmitted: onSubmitted,
              cursorColor: c.accent,
              style: CruType.input.tabular.tint(c.label),
              decoration: InputDecoration.collapsed(
                hintText: hint,
                hintStyle: CruType.input.tint(c.label3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A calm, on-token dialog: surface card, title, body, a secondary
/// cancel and one filled action.
class PatientDialog extends StatelessWidget {
  const PatientDialog({
    super.key,
    required this.title,
    required this.body,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
  });

  final String title;
  final Widget body;
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: c.surface.withValues(alpha: 0),
      shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: CruSize.dialog),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: CruType.title2.tint(c.label)),
              const SizedBox(height: CruSpace.s12),
              body,
              const SizedBox(height: CruSpace.s24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CruButton(
                    label: cancelLabel,
                    kind: CruButtonKind.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: CruSpace.s10),
                  CruButton(label: confirmLabel, onPressed: onConfirm),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
