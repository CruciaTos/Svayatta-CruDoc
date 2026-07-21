import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/errors/inventory_exceptions.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';

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

  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();

  StockTransactionType _type = StockTransactionType.restock;
  bool _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final quantity = int.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      setState(() => _errorText = 'Enter a valid quantity.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await _repository.recordTransaction(
        medicineId: widget.medicine.id,
        type: _type,
        quantity: quantity,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      ref.invalidate(medicineTransactionsProvider(widget.medicine.id));
      if (mounted) Navigator.pop(context);
    } on InsufficientStockException catch (e) {
      setState(() {
        _isSaving = false;
        _errorText = e.message;
      });
    } on MedicineValidationException catch (e) {
      setState(() {
        _isSaving = false;
        _errorText = e.message;
      });
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorText = 'Failed to save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppColors.cardSurface,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(
        'Adjust Stock — ${widget.medicine.name}',
        style: AppColors.sectionHeading.copyWith(fontSize: 18),
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _TypeChip(
                    label: 'Restock',
                    icon: Icons.add_circle_outline,
                    selected: _type == StockTransactionType.restock,
                    onTap: () => setState(
                      () => _type = StockTransactionType.restock,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeChip(
                    label: 'Dispense',
                    icon: Icons.remove_circle_outline,
                    selected: _type == StockTransactionType.dispense,
                    onTap: () => setState(
                      () => _type = StockTransactionType.dispense,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Quantity',
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _quantityController,
              enabled: !_isSaving,
              keyboardType: TextInputType.number,
              style: AppColors.bodyMedium,
              decoration: InputDecoration(
                hintText: 'e.g. 20',
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
            const Text(
              'Note (optional)',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              enabled: !_isSaving,
              style: AppColors.bodyMedium,
              decoration: InputDecoration(
                hintText: 'e.g. Dispensed to patient visit',
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
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _errorText!,
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
      ),
      actions: [
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
        FilledButton(
          onPressed: _isSaving ? null : _handleSubmit,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
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
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.chartBarLight : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.chartBarLight : AppColors.divider,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
