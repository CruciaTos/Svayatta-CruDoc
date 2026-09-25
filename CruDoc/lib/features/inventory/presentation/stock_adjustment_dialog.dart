import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/errors/inventory_exceptions.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Shows the quick restock/dispense dialog for [medicine].
Future<void> showStockAdjustmentDialog(
  BuildContext context, {
  required MedicineModel medicine,
  InventoryRepository? repository,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => StockAdjustmentDialog(
      medicine: medicine,
      repository: repository,
    ),
  );
}

/// Quick-action dialog for logging a restock or dispense transaction
/// against a single medicine.
class StockAdjustmentDialog extends ConsumerStatefulWidget {
  const StockAdjustmentDialog({
    super.key,
    required this.medicine,
    this.repository,
  });

  final MedicineModel medicine;
  final InventoryRepository? repository;

  @override
  ConsumerState<StockAdjustmentDialog> createState() =>
      _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState
    extends ConsumerState<StockAdjustmentDialog> {
  late final InventoryRepository _repository =
      widget.repository ?? InventoryRepository();

  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _note = TextEditingController();

  StockTransactionType _type = StockTransactionType.restock;
  bool _dirty = false;
  bool _saving = false;
  bool _submitted = false;
  String? _notice;

  bool get _restock => _type == StockTransactionType.restock;

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  void _edited([Object? _]) {
    setState(() {
      _dirty = true;
      _notice = null;
    });
  }

  String? _validateQuantity(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n <= 0) ? 'Enter a quantity above 0.' : null;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    final quantity = int.parse(_quantity.text.trim());

    setState(() {
      _saving = true;
      _notice = null;
    });

    try {
      await _repository.recordTransaction(
        medicineId: widget.medicine.id,
        type: _type,
        quantity: quantity,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      ref.invalidate(medicineTransactionsProvider(widget.medicine.id));
      if (mounted) Navigator.pop(context);
    } on InsufficientStockException catch (e) {
      _fail(e.message);
    } on MedicineValidationException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail("Couldn't save this change. Try again.");
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _notice = message;
    });
  }

  /// Under the quantity: what the stock becomes.
  String? get _after {
    final n = int.tryParse(_quantity.text.trim());
    if (n == null || n <= 0) return null;
    final m = widget.medicine;
    final after = m.currentStock + (_restock ? n : -n);
    if (after < 0) return null;
    return 'Stock becomes ${InventoryFormat.quantity(after, m.unit)}';
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.medicine;
    final u = m.unit.trim().toLowerCase();
    const pills = ['tablet', 'capsule', 'strip', 'pill'];
    return CruFormDialog(
      width: CruSize.dialog,
      title: 'Adjust stock',
      subtitle: '${m.name} · '
          '${InventoryFormat.quantity(m.currentStock, m.unit)} in stock',
      leading: CruIconTile(
        icon: pills.any(u.startsWith) ? InventoryIcons.pill : CruIcons.box,
        tone: CruTileTone.neutral,
      ),
      submitLabel: _restock ? 'Add stock' : 'Dispense',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      body: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CruFieldFrame(
                label: 'Change',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CruSegmentedControl<StockTransactionType>(
                    semanticLabel: 'Change',
                    segments: const [
                      CruSegment(StockTransactionType.restock, 'Restock'),
                      CruSegment(StockTransactionType.dispense, 'Dispense'),
                    ],
                    selected: _type,
                    onChanged: (v) {
                      _type = v;
                      _edited();
                    },
                  ),
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Quantity',
                controller: _quantity,
                autofocus: true,
                hint: 'How many',
                help: _after,
                tabular: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(7),
                ],
                validator: _validateQuantity,
                onChanged: _edited,
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Note',
                optional: true,
                controller: _note,
                hint: _restock ? 'Supplier bill, order…' : 'Visit, patient…',
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                onChanged: _edited,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
