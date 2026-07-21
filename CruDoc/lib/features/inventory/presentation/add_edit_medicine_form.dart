import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/errors/inventory_exceptions.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';

/// Shows the Add/Edit Medicine dialog. Pass [medicine] to edit an existing
/// one; omit it to create a new medicine.
Future<void> showAddEditMedicineForm(
  BuildContext context, {
  MedicineModel? medicine,
  InventoryRepository? repository,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AddEditMedicineForm(
      medicine: medicine,
      repository: repository,
    ),
  );
}

/// Modal dialog for creating or editing a medicine, styled in the same
/// rounded-card / filled-field language as [RevenueScreen]'s entry dialog.
class AddEditMedicineForm extends StatefulWidget {
  const AddEditMedicineForm({super.key, this.medicine, this.repository});

  final MedicineModel? medicine;
  final InventoryRepository? repository;

  @override
  State<AddEditMedicineForm> createState() => _AddEditMedicineFormState();
}

class _AddEditMedicineFormState extends State<AddEditMedicineForm> {
  final _formKey = GlobalKey<FormState>();
  late final InventoryRepository _repository =
      widget.repository ?? InventoryRepository();

  late final _nameController = TextEditingController(
    text: widget.medicine?.name ?? '',
  );
  late final _categoryController = TextEditingController(
    text: widget.medicine?.category ?? '',
  );
  late final _unitController = TextEditingController(
    text: widget.medicine?.unit ?? '',
  );
  late final _stockController = TextEditingController(
    text: widget.medicine != null ? '${widget.medicine!.currentStock}' : '0',
  );
  late final _thresholdController = TextEditingController(
    text: widget.medicine != null
        ? '${widget.medicine!.reorderThreshold}'
        : '10',
  );
  late final _priceController = TextEditingController(
    text: widget.medicine?.unitPrice?.toString() ?? '',
  );
  late final _supplierController = TextEditingController(
    text: widget.medicine?.supplierName ?? '',
  );
  late final _batchController = TextEditingController(
    text: widget.medicine?.batchNumber ?? '',
  );

  DateTime? _expiryDate;
  bool _isSaving = false;
  String? _errorText;

  bool get _isEditing => widget.medicine != null;

  @override
  void initState() {
    super.initState();
    _expiryDate = widget.medicine?.expiryDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _unitController.dispose();
    _stockController.dispose();
    _thresholdController.dispose();
    _priceController.dispose();
    _supplierController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.slateBlue,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.cardSurface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    final unit = _unitController.text.trim();
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;
    final threshold = int.tryParse(_thresholdController.text.trim()) ?? 10;
    final price = _priceController.text.trim().isEmpty
        ? null
        : double.tryParse(_priceController.text.trim());
    final supplier = _supplierController.text.trim();
    final batch = _batchController.text.trim();

    try {
      if (_isEditing) {
        await _repository.updateMedicine(widget.medicine!.id, {
          'name': name,
          'category': category,
          'unit': unit,
          'currentStock': stock,
          'reorderThreshold': threshold,
          'unitPrice': price,
          'supplierName': supplier.isEmpty ? null : supplier,
          'batchNumber': batch.isEmpty ? null : batch,
          'expiryDate': _expiryDate,
        });
      } else {
        final now = DateTime.now();
        await _repository.createMedicine(
          MedicineModel(
            id: '',
            name: name,
            category: category,
            unit: unit,
            currentStock: stock,
            reorderThreshold: threshold,
            unitPrice: price,
            supplierName: supplier.isEmpty ? null : supplier,
            batchNumber: batch.isEmpty ? null : batch,
            expiryDate: _expiryDate,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      if (mounted) Navigator.pop(context);
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

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: AppColors.bodyFontFamily,
        color: AppColors.textSecondary,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontFamily: AppColors.bodyFontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppColors.cardSurface,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(
        _isEditing ? 'Edit Medicine' : 'Add Medicine',
        style: AppColors.sectionHeading.copyWith(fontSize: 20),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _label('Name'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSaving,
                  style: AppColors.bodyMedium,
                  decoration: _decoration('e.g. Amoxicillin 500mg'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Category'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _categoryController,
                            enabled: !_isSaving,
                            style: AppColors.bodyMedium,
                            decoration: _decoration('Antibiotic'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Unit'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _unitController,
                            enabled: !_isSaving,
                            style: AppColors.bodyMedium,
                            decoration: _decoration('tablet, vial...'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Current Stock'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _stockController,
                            enabled: !_isSaving,
                            keyboardType: TextInputType.number,
                            style: AppColors.bodyMedium,
                            decoration: _decoration('0'),
                            validator: (v) =>
                                int.tryParse(v?.trim() ?? '') == null
                                ? 'Enter a whole number'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Reorder Threshold'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _thresholdController,
                            enabled: !_isSaving,
                            keyboardType: TextInputType.number,
                            style: AppColors.bodyMedium,
                            decoration: _decoration('10'),
                            validator: (v) {
                              final n = int.tryParse(v?.trim() ?? '');
                              if (n == null) return 'Enter a whole number';
                              if (n < 0) return 'Cannot be negative';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _label('Unit Price (optional)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _priceController,
                  enabled: !_isSaving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: AppColors.bodyMedium,
                  decoration: _decoration('₹0.00'),
                  validator: (v) {
                    final trimmed = v?.trim() ?? '';
                    if (trimmed.isEmpty) return null;
                    return double.tryParse(trimmed) == null
                        ? 'Enter a valid amount'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                _label('Supplier (optional)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _supplierController,
                  enabled: !_isSaving,
                  style: AppColors.bodyMedium,
                  decoration: _decoration('Supplier name'),
                ),
                const SizedBox(height: 14),
                _label('Batch Number (optional)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _batchController,
                  enabled: !_isSaving,
                  style: AppColors.bodyMedium,
                  decoration: _decoration('Batch / lot number'),
                ),
                const SizedBox(height: 14),
                _label('Expiry Date (optional)'),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _isSaving ? null : _pickExpiryDate,
                  borderRadius: BorderRadius.circular(16),
                  child: InputDecorator(
                    decoration: _decoration('Select a date'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _expiryDate == null
                                ? 'Select a date'
                                : '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                            style: AppColors.bodyMedium.copyWith(
                              color: _expiryDate == null
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (_expiryDate != null)
                          GestureDetector(
                            onTap: _isSaving
                                ? null
                                : () => setState(() => _expiryDate = null),
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: AppColors.silver,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.redAccent,
                        size: 16,
                      ),
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
