import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/errors/inventory_exceptions.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';
import 'package:doctor_management_app/features/inventory/data/services/ocr_service.dart';

/// Opens the desktop-specific Add/Edit Medicine modal popup dialog.
///
/// If [medicine] is provided, fields are pre-populated for editing.
/// If [medicine] is null, a blank form is presented to create a new item.
Future<bool?> showDesktopAddEditMedicineDialog(
  BuildContext context, {
  MedicineModel? medicine,
  InventoryRepository? repository,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 900,
          maxHeight: 800,
        ),
        child: DesktopAddEditMedicineDialog(
          medicine: medicine,
          repository: repository,
        ),
      ),
    ),
  );
}

class DesktopAddEditMedicineDialog extends StatefulWidget {
  const DesktopAddEditMedicineDialog({
    super.key,
    this.medicine,
    this.repository,
  });

  final MedicineModel? medicine;
  final InventoryRepository? repository;

  @override
  State<DesktopAddEditMedicineDialog> createState() =>
      _DesktopAddEditMedicineDialogState();
}

class _DesktopAddEditMedicineDialogState
    extends State<DesktopAddEditMedicineDialog> {
  final _formKey = GlobalKey<FormState>();
  late final InventoryRepository _repository =
      widget.repository ?? InventoryRepository();

  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _unitController;
  late final TextEditingController _stockController;
  late final TextEditingController _thresholdController;
  late final TextEditingController _priceController;
  late final TextEditingController _supplierController;
  late final TextEditingController _batchController;

  DateTime? _expiryDate;
  String? _imageUrl;
  bool _isSaving = false;
  bool _isScanning = false;
  String? _errorText;
  XFile? _receiptImage;
  int _ocrFieldsFilled = 0;

  static final _imagePicker = ImagePicker();

  bool get _isEditing => widget.medicine != null;

  static const List<String> _categoryPresets = [
    'Antibiotic',
    'Analgesic',
    'Antipyretic',
    'Cardiovascular',
    'Antidiabetic',
    'Vitamins & Supplements',
    'Gastrointestinal',
    'Respiratory',
    'Dermatological',
    'Antihistamine',
    'Vaccine',
    'Consumable',
    'Dental Consumable',
    'Dental Restorative',
    'Dental Anesthetic',
    'Dental Endodontic',
    'Dental Surgical',
  ];

  static const List<String> _unitPresets = [
    'Tablets',
    'Capsules',
    'Syrup (ml)',
    'Injections',
    'Vials',
    'Strips',
    'Ointment',
    'Drops',
    'Bottles',
    'Sachets',
    'Pcs',
    'Cartridges',
    'Burs',
    'Pouches',
    'Syringes',
  ];

  final _currencyFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    final med = widget.medicine;
    _nameController = TextEditingController(text: med?.name ?? '');
    _categoryController = TextEditingController(text: med?.category ?? '');
    _unitController = TextEditingController(text: med?.unit ?? 'Tablets');
    _stockController = TextEditingController(
      text: med != null ? '${med.currentStock}' : '0',
    );
    _thresholdController = TextEditingController(
      text: med != null ? '${med.reorderThreshold}' : '10',
    );
    _priceController = TextEditingController(
      text: med?.unitPrice != null ? '${med!.unitPrice}' : '',
    );
    _supplierController = TextEditingController(
      text: med?.supplierName ?? '',
    );
    _batchController = TextEditingController(
      text: med?.batchNumber ?? '',
    );
    _expiryDate = med?.expiryDate;
    _imageUrl = med?.imageUrl;

    // Listen to stock and price changes for live valuation display
    _stockController.addListener(_onCalculationsChanged);
    _priceController.addListener(_onCalculationsChanged);
    _thresholdController.addListener(_onCalculationsChanged);
  }

  void _onCalculationsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stockController.removeListener(_onCalculationsChanged);
    _priceController.removeListener(_onCalculationsChanged);
    _thresholdController.removeListener(_onCalculationsChanged);

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
      initialDate: _expiryDate ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1F2937),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1F2937),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  Future<void> _pickReceiptImage(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 88,
      );
      if (image == null || !mounted) return;

      setState(() => _receiptImage = image);
      await _scanReceiptWithOcr(image);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Could not attach receipt: $e');
    }
  }

  Future<void> _scanReceiptWithOcr(XFile image) async {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _ocrFieldsFilled = 0;
      _errorText = null;
    });

    try {
      final result = await OcrService.instance.scanMedicineReceipt(image);

      if (!mounted) return;

      setState(() {
        _isScanning = false;
        _ocrFieldsFilled = result.filledFieldCount;

        if (result.name != null && result.name!.isNotEmpty) {
          _nameController.text = result.name!;
        }
        if (result.category != null && result.category!.isNotEmpty) {
          _categoryController.text = result.category!;
        }
        if (result.unitPrice != null) {
          _priceController.text = result.unitPrice!.toStringAsFixed(2);
        }
        if (result.supplierName != null && result.supplierName!.isNotEmpty) {
          _supplierController.text = result.supplierName!;
        }
        if (result.batchNumber != null && result.batchNumber!.isNotEmpty) {
          _batchController.text = result.batchNumber!;
        }
        if (result.expiryDate != null) {
          _expiryDate = result.expiryDate;
        }
        if (result.quantity != null && result.quantity! > 0) {
          _stockController.text = '${result.quantity}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _errorText = 'OCR scan failed: $e';
      });
    }
  }

  Future<void> _pickItemImage() async {
    if (_isSaving) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => _imageUrl = picked.path);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = 'Error selecting image: $e');
      }
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    final unit = _unitController.text.trim().isEmpty
        ? 'Units'
        : _unitController.text.trim();
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
          'imageUrl': _imageUrl,
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
            imageUrl: _imageUrl,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on MedicineValidationException catch (e) {
      setState(() {
        _isSaving = false;
        _errorText = e.message;
      });
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorText = 'Failed to save inventory item: $e';
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
                      // Left Column: Core medicine info & details
                      Expanded(
                        flex: 11,
                        child: _buildLeftColumn(),
                      ),
                      const SizedBox(width: 24),
                      // Vertical separator
                      Container(
                        width: 1,
                        height: 540,
                        color: const Color(0xFFF1F5F9),
                      ),
                      const SizedBox(width: 24),
                      // Right Column: Stock levels, live valuation, OCR & Image
                      Expanded(
                        flex: 9,
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

  // ===========================================================================
  // HEADER
  // ===========================================================================
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isEditing
                  ? Icons.edit_note_rounded
                  : Icons.inventory_2_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isEditing ? 'Edit Inventory Item' : 'Add Inventory Item',
                      style: const TextStyle(
                        fontFamily: AppColors.headingFontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _isEditing
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isEditing
                              ? const Color(0xFFBFDBFE)
                              : const Color(0xFFA7F3D0),
                        ),
                      ),
                      child: Text(
                        _isEditing ? 'EDIT MODE' : 'NEW ITEM',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _isEditing
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF059669),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _isEditing
                      ? 'Update medicine specifications, stock count, vendor details, and pricing.'
                      : 'Add a new medication to clinical inventory with stock tracking and auto-restock alerts.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
            tooltip: 'Close (Esc)',
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LEFT COLUMN: BASIC & CLINICAL DETAILS
  // ===========================================================================
  Widget _buildLeftColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.medication_liquid_rounded,
          title: 'Product Details',
          subtitle: 'Name, medical category, and dosage packaging',
        ),
        const SizedBox(height: 16),

        // Medicine Name
        _buildFieldLabel('Item / Medicine Name', isRequired: true),
        const SizedBox(height: 6),
        TextFormField(
          controller: _nameController,
          enabled: !_isSaving,
          autofocus: !_isEditing,
          style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
          decoration: _buildInputDecoration(
            hint: 'e.g. Amoxicillin 500mg Clavulanic Acid IP',
            prefixIcon: Icons.badge_outlined,
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Item name is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Category with quick pills
        _buildFieldLabel('Category / Therapeutic Class'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _categoryController,
          enabled: !_isSaving,
          style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
          decoration: _buildInputDecoration(
            hint: 'e.g. Antibiotic, Analgesic, Vitamins...',
            prefixIcon: Icons.category_outlined,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _categoryPresets.map((cat) {
            final isSelected = _categoryController.text.trim() == cat;
            return InkWell(
              onTap: _isSaving
                  ? null
                  : () {
                      setState(() {
                        _categoryController.text = cat;
                      });
                    },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF1F2937)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF1F2937)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Unit / Dosage Form with quick pills
        _buildFieldLabel('Unit / Dosage Form', isRequired: true),
        const SizedBox(height: 6),
        TextFormField(
          controller: _unitController,
          enabled: !_isSaving,
          style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
          decoration: _buildInputDecoration(
            hint: 'e.g. Tablets, Capsules, Syrup (ml)...',
            prefixIcon: Icons.view_in_ar_outlined,
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Unit is required (e.g. Tablets, Bottles)';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _unitPresets.map((unit) {
            final isSelected = _unitController.text.trim().toLowerCase() ==
                unit.toLowerCase();
            return InkWell(
              onTap: _isSaving
                  ? null
                  : () {
                      setState(() {
                        _unitController.text = unit;
                      });
                    },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        _buildSectionHeader(
          icon: Icons.local_shipping_outlined,
          title: 'Vendor & Batch Traceability',
          subtitle: 'Distributor information and expiry monitoring',
        ),
        const SizedBox(height: 16),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Supplier Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('Supplier / Distributor'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _supplierController,
                    enabled: !_isSaving,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                    decoration: _buildInputDecoration(
                      hint: 'e.g. Cipla, Sun Pharma, Apollo...',
                      prefixIcon: Icons.storefront_outlined,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Batch Number
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('Batch / Lot No.'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _batchController,
                    enabled: !_isSaving,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                    decoration: _buildInputDecoration(
                      hint: 'e.g. LOT-2024-88A',
                      prefixIcon: Icons.qr_code_2_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Expiry Date Picker Card
        _buildFieldLabel('Expiry Date'),
        const SizedBox(height: 6),
        InkWell(
          onTap: _isSaving ? null : _pickExpiryDate,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _expiryDate != null
                    ? (_expiryDate!.isBefore(DateTime.now())
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFFCBD5E1))
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: _expiryDate != null
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _expiryDate == null
                        ? 'Select expiry date...'
                        : DateFormat('dd MMM yyyy').format(_expiryDate!),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _expiryDate != null
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: _expiryDate == null
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                if (_expiryDate != null) ...[
                  _buildExpiryBadge(),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isSaving
                        ? null
                        : () => setState(() => _expiryDate = null),
                    child: const Icon(
                      Icons.cancel_rounded,
                      size: 18,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpiryBadge() {
    if (_expiryDate == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final diffDays = _expiryDate!.difference(now).inDays;

    if (diffDays < 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'EXPIRED',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFFDC2626),
          ),
        ),
      );
    } else if (diffDays <= 30) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '$diffDays d left',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFFD97706),
          ),
        ),
      );
    } else {
      final months = (diffDays / 30).floor();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          months > 0 ? '$months mo left' : '$diffDays d left',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF059669),
          ),
        ),
      );
    }
  }

  // ===========================================================================
  // RIGHT COLUMN: STOCK, LIVE VALUATION, OCR & MEDIA
  // ===========================================================================
  Widget _buildRightColumn() {
    final int currentStock = int.tryParse(_stockController.text.trim()) ?? 0;
    final int threshold = int.tryParse(_thresholdController.text.trim()) ?? 10;
    final double? unitPrice = _priceController.text.trim().isEmpty
        ? null
        : double.tryParse(_priceController.text.trim());
    final double totalEstimatedVal =
        unitPrice != null ? unitPrice * currentStock : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.query_stats_rounded,
          title: 'Stock Levels & Pricing',
          subtitle: 'Set inventory counts and reorder warnings',
        ),
        const SizedBox(height: 16),

        // Stock & Threshold Card Container
        Container(
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Initial / Current Stock
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('Current Stock', isRequired: true),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _stockController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                          decoration: _buildInputDecoration(
                            hint: '0',
                            prefixIcon: Icons.layers_outlined,
                          ),
                          validator: (v) {
                            final n = int.tryParse(v?.trim() ?? '');
                            if (n == null) return 'Enter number';
                            if (n < 0) return 'Cannot be < 0';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Reorder Threshold
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('Low-Stock Alert at'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _thresholdController,
                          enabled: !_isSaving,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                          decoration: _buildInputDecoration(
                            hint: '10',
                            prefixIcon: Icons.warning_amber_rounded,
                          ),
                          validator: (v) {
                            final n = int.tryParse(v?.trim() ?? '');
                            if (n == null) return 'Enter number';
                            if (n < 0) return 'Cannot be < 0';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Unit Price
              _buildFieldLabel('Unit Purchase Price (₹)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _priceController,
                enabled: !_isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
                decoration: _buildInputDecoration(
                  hint: '0.00',
                  prefixText: '₹ ',
                  prefixIcon: Icons.currency_rupee_rounded,
                ),
                validator: (v) {
                  final trimmed = v?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  final d = double.tryParse(trimmed);
                  if (d == null) return 'Enter valid price';
                  if (d < 0) return 'Cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Live Valuation Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Estimated Stock Value',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            unitPrice != null
                                ? _currencyFormatter.format(totalEstimatedVal)
                                : '—',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStockStatusIndicator(currentStock, threshold),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Receipt OCR Section
        _buildReceiptSection(),
        const SizedBox(height: 16),

        // Custom Item Image Section
        _buildImagePickerSection(),
      ],
    );
  }

  Widget _buildStockStatusIndicator(int stock, int threshold) {
    if (stock == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFDC2626)),
            SizedBox(width: 4),
            Text(
              'Out of Stock',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      );
    } else if (stock <= threshold) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFD97706)),
            SizedBox(width: 4),
            Text(
              'Low Stock Warning',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFD97706),
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 14, color: Color(0xFF059669)),
            SizedBox(width: 4),
            Text(
              'Stock Healthy',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF059669),
              ),
            ),
          ],
        ),
      );
    }
  }

  // ===========================================================================
  // RECEIPT OCR UPLOAD SECTION
  // ===========================================================================
  Widget _buildReceiptSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.document_scanner_rounded,
              size: 16,
              color: Color(0xFF2563EB),
            ),
            const SizedBox(width: 6),
            const Text(
              'Smart Receipt / Bill OCR',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const Spacer(),
            if (_ocrFieldsFilled > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_rounded,
                        size: 12, color: Color(0xFF059669)),
                    const SizedBox(width: 4),
                    Text(
                      '$_ocrFieldsFilled fields filled',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_receiptImage == null)
          InkWell(
            onTap: _isSaving ? null : () => _pickReceiptImage(ImageSource.gallery),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFCBD5E1),
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.upload_file_rounded,
                      size: 20,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Upload invoice or medicine strip',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          'AI automatically extracts name, batch, stock & price',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: kIsWeb
                        ? Image.network(_receiptImage!.path, fit: BoxFit.cover)
                        : Image.file(File(_receiptImage!.path), fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isScanning ? 'Scanning document...' : 'Receipt Attached',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        _isScanning
                            ? 'Processing with OCR...'
                            : '${_receiptImage!.name}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isScanning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF2563EB),
                    ),
                  )
                else ...[
                  IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => _pickReceiptImage(ImageSource.gallery),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    color: const Color(0xFF64748B),
                    tooltip: 'Replace receipt',
                  ),
                  IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => setState(() {
                              _receiptImage = null;
                              _ocrFieldsFilled = 0;
                            }),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: const Color(0xFF64748B),
                    tooltip: 'Remove receipt',
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // ITEM IMAGE PICKER
  // ===========================================================================
  Widget _buildImagePickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('Custom Item Image (optional)'),
        const SizedBox(height: 6),
        InkWell(
          onTap: _isSaving ? null : _pickItemImage,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                if (_imageUrl != null && _imageUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: kIsWeb || _imageUrl!.startsWith('http')
                          ? Image.network(_imageUrl!, fit: BoxFit.cover)
                          : Image.file(File(_imageUrl!), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Image selected',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => setState(() => _imageUrl = null),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: const Color(0xFFDC2626),
                    tooltip: 'Remove Image',
                  ),
                ] else ...[
                  const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 22,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Attach medicine box or pack photo',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.folder_open_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // ERROR BANNER
  // ===========================================================================
  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorText!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF991B1B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FOOTER ACTIONS
  // ===========================================================================
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F2937),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(
              _isSaving
                  ? 'Saving Item...'
                  : (_isEditing ? 'Save Changes' : 'Add Item to Inventory'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // REUSABLE HELPER WIDGETS
  // ===========================================================================
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF2563EB)),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label, {bool isRequired = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        if (isRequired)
          const Text(
            ' *',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFDC2626),
            ),
          ),
      ],
    );
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    IconData? prefixIcon,
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontSize: 13,
        color: Color(0xFF94A3B8),
        fontWeight: FontWeight.w400,
      ),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: const Color(0xFF64748B))
          : null,
      prefixText: prefixText,
      prefixStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F172A),
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      isDense: true,
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
    );
  }
}
