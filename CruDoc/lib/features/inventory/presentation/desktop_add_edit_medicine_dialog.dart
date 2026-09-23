import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/errors/inventory_exceptions.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';
import 'package:doctor_management_app/features/inventory/data/services/ocr_service.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_builder.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';

/// Opens the desktop Add/Edit Medicine form.
///
/// If [medicine] is provided, fields are pre-populated for editing.
/// If [medicine] is null, a blank form is presented to create a new item.
/// Returns true when the item was saved.
Future<bool?> showDesktopAddEditMedicineDialog(
  BuildContext context, {
  MedicineModel? medicine,
  InventoryRepository? repository,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DesktopAddEditMedicineDialog(
      medicine: medicine,
      repository: repository,
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
  static const _categoryPresets = [
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

  static const _unitPresets = [
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

  static final _imagePicker = ImagePicker();

  final _formKey = GlobalKey<FormState>();
  late final InventoryRepository _repository =
      widget.repository ?? InventoryRepository();

  late final TextEditingController _name;
  late final TextEditingController _category;

  /// Dentists see dental categories and units first.
  bool _dental = false;

  List<String> get _categories => _dental
      ? [
          ..._categoryPresets.where((c) => c.startsWith('Dental')),
          ..._categoryPresets.where((c) => !c.startsWith('Dental')),
        ]
      : _categoryPresets
          .where((c) => !c.startsWith('Dental'))
          .toList();

  static const _dentalUnits = ['Cartridges', 'Burs', 'Pouches', 'Syringes', 'Pcs'];

  List<String> get _units => _dental
      ? [..._dentalUnits, ..._unitPresets.where((u) => !_dentalUnits.contains(u))]
      : _unitPresets
          .where((u) => !const ['Cartridges', 'Burs', 'Pouches'].contains(u))
          .toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dental = ProviderScope.containerOf(context, listen: false)
        .read(isDentistProvider);
  }
  late final TextEditingController _unit;
  late final TextEditingController _stock;
  late final TextEditingController _threshold;
  late final TextEditingController _good;
  late final TextEditingController _price;
  late final TextEditingController _supplier;
  late final TextEditingController _batch;

  DateTime? _expiryDate;
  String? _imageUrl;
  XFile? _receiptImage;
  bool _scanning = false;
  int _ocrFieldsFilled = 0;

  /// A problem with the bill or photo, shown under the attachments.
  String? _attachError;

  bool _dirty = false;
  bool _saving = false;
  bool _submitted = false;
  String? _notice;

  bool get _isEditing => widget.medicine != null;

  @override
  void initState() {
    super.initState();
    final m = widget.medicine;
    _name = TextEditingController(text: m?.name ?? '');
    _category = TextEditingController(text: m?.category ?? '');
    _unit = TextEditingController(text: m?.unit ?? 'Tablets');
    _stock = TextEditingController(text: m != null ? '${m.currentStock}' : '0');
    _threshold =
        TextEditingController(text: m != null ? '${m.reorderThreshold}' : '10');
    _good = TextEditingController(
      text: m?.goodStockLevel == null ? '' : '${m!.goodStockLevel}',
    );
    _price = TextEditingController(
      text: m?.unitPrice == null
          ? ''
          : m!.unitPrice! == m.unitPrice!.roundToDouble()
              ? m.unitPrice!.toStringAsFixed(0)
              : m.unitPrice!.toStringAsFixed(2),
    );
    _supplier = TextEditingController(text: m?.supplierName ?? '');
    _batch = TextEditingController(text: m?.batchNumber ?? '');
    _expiryDate = m?.expiryDate;
    _imageUrl = m?.imageUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _unit.dispose();
    _stock.dispose();
    _threshold.dispose();
    _good.dispose();
    _price.dispose();
    _supplier.dispose();
    _batch.dispose();
    super.dispose();
  }

  void _edited([Object? _]) {
    setState(() {
      _dirty = true;
      _notice = null;
    });
  }

  void _pickPreset(TextEditingController controller, String value) {
    controller.text = value;
    _edited();
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
      helpText: 'Expiry date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dirty = true;
      _expiryDate = picked;
    });
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _attachError = "Couldn't open that file. Try another photo.");
    }
  }

  Future<void> _scanReceiptWithOcr(XFile image) async {
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _ocrFieldsFilled = 0;
      _attachError = null;
    });

    try {
      final result = await OcrService.instance.scanMedicineReceipt(image);
      if (!mounted) return;

      setState(() {
        _scanning = false;
        _ocrFieldsFilled = result.filledFieldCount;
        if (result.filledFieldCount > 0) _dirty = true;

        if (result.name != null && result.name!.isNotEmpty) {
          _name.text = result.name!;
        }
        if (result.category != null && result.category!.isNotEmpty) {
          _category.text = result.category!;
        }
        if (result.unitPrice != null) {
          _price.text = result.unitPrice!.toStringAsFixed(2);
        }
        if (result.supplierName != null && result.supplierName!.isNotEmpty) {
          _supplier.text = result.supplierName!;
        }
        if (result.batchNumber != null && result.batchNumber!.isNotEmpty) {
          _batch.text = result.batchNumber!;
        }
        if (result.expiryDate != null) {
          _expiryDate = result.expiryDate;
        }
        if (result.quantity != null && result.quantity! > 0) {
          _stock.text = '${result.quantity}';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _attachError = "Couldn't read that bill. Fill in the details by hand.";
      });
    }
  }

  Future<void> _pickItemImage() async {
    if (_saving) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() {
          _imageUrl = picked.path;
          _attachError = null;
          _dirty = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _attachError = "Couldn't open that photo. Try another one.",
        );
      }
    }
  }

  String? _required(String? v, String message) =>
      (v == null || v.trim().isEmpty) ? message : null;

  String? _validateCount(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null) return 'Enter a whole number.';
    if (n < 0) return "Can't be below 0.";
    return null;
  }

  String? _validatePrice(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final d = double.tryParse(t);
    if (d == null) return 'Enter a price like 12.50.';
    if (d < 0) return "Can't be below 0.";
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _notice = null;
    });

    final name = _name.text.trim();
    final category = _category.text.trim();
    final unit = _unit.text.trim().isEmpty ? 'Units' : _unit.text.trim();
    final stock = int.tryParse(_stock.text.trim()) ?? 0;
    final threshold = int.tryParse(_threshold.text.trim()) ?? 10;
    // Empty: the good level follows the alert level (twice it).
    final good = int.tryParse(_good.text.trim());
    final price =
        _price.text.trim().isEmpty ? null : double.tryParse(_price.text.trim());
    final supplier = _supplier.text.trim();
    final batch = _batch.text.trim();

    try {
      if (_isEditing) {
        await _repository.updateMedicine(widget.medicine!.id, {
          'name': name,
          'category': category,
          'unit': unit,
          'currentStock': stock,
          'reorderThreshold': threshold,
          'goodStockLevel': good,
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
            goodStockLevel: good,
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
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on MedicineValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = "Couldn't save ${_isEditing ? 'the changes' : 'this item'}. "
            'Try again.';
      });
    }
  }

  /// Calendar days from today to [_expiryDate].
  int? get _daysToExpiry {
    final e = _expiryDate;
    if (e == null) return null;
    final now = DateTime.now();
    final l = e.toLocal();
    return DateTime(l.year, l.month, l.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  CruIconData get _itemIcon {
    final u = _unit.text.trim().toLowerCase();
    const pills = ['tablet', 'capsule', 'strip', 'pill'];
    return pills.any(u.startsWith) ? InventoryIcons.pill : CruIcons.box;
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: _isEditing ? 'Edit item' : 'New item',
      subtitle:
          _isEditing ? widget.medicine!.name : 'Add it to your inventory',
      leading: CruIconTile(icon: _itemIcon, tone: CruTileTone.neutral),
      submitLabel: _isEditing ? 'Save changes' : 'Add item',
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
              title: 'Item',
              description: 'How it shows in your inventory.',
              children: [
                CruTextField(
                  label: 'Name',
                  controller: _name,
                  autofocus: !_isEditing,
                  hint: 'Amoxicillin 500 mg',
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => _required(v, 'Add a name.'),
                  onChanged: _edited,
                ),
                CruFieldRow(
                  children: [
                    _PresetField(
                      label: 'Category',
                      optional: true,
                      controller: _category,
                      hint: 'Antibiotic',
                      presets: _categories,
                      onChanged: _edited,
                      onPick: (v) => _pickPreset(_category, v),
                    ),
                    _PresetField(
                      label: 'Unit',
                      controller: _unit,
                      hint: 'Tablets',
                      presets: _units,
                      validator: (v) => _required(v, 'Add a unit, like Tablets.'),
                      onChanged: _edited,
                      onPick: (v) => _pickPreset(_unit, v),
                    ),
                  ],
                ),
              ],
            ),
            CruFormSection(
              title: 'Stock and price',
              description:
                  'Counted in the unit above. Green at the good level, '
                  'amber at the alert level, red at a fifth of it.',
              children: [
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'In stock',
                      controller: _stock,
                      hint: '0',
                      tabular: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validateCount,
                      onChanged: _edited,
                    ),
                    CruTextField(
                      label: 'Alert at',
                      controller: _threshold,
                      hint: '10',
                      tabular: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validateCount,
                      onChanged: _edited,
                    ),
                  ],
                ),
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Good at',
                      optional: true,
                      controller: _good,
                      hint: '${(int.tryParse(_threshold.text.trim()) ?? 10) * 2}',
                      help: 'Leave empty for twice the alert level.',
                      tabular: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: _edited,
                    ),
                    CruTextField(
                      label: 'Price per unit',
                      optional: true,
                      controller: _price,
                      prefix: '₹',
                      hint: '0.00',
                      tabular: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      validator: _validatePrice,
                      onChanged: _edited,
                    ),
                  ],
                ),
                ?_stockSummary(context),
              ],
            ),
            CruFormSection(
              title: 'Batch and expiry',
              description: 'For reordering and to catch stock before it '
                  'expires.',
              children: [
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Supplier',
                      optional: true,
                      controller: _supplier,
                      hint: 'Distributor name',
                      textCapitalization: TextCapitalization.words,
                      onChanged: _edited,
                    ),
                    CruTextField(
                      label: 'Batch number',
                      optional: true,
                      controller: _batch,
                      hint: 'As on the pack',
                      textCapitalization: TextCapitalization.characters,
                      onChanged: _edited,
                    ),
                  ],
                ),
                CruPickerField(
                  label: 'Expiry date',
                  optional: true,
                  icon: CruIcons.calendar,
                  value: _expiryDate == null
                      ? null
                      : DateFormat('d MMM yyyy').format(_expiryDate!),
                  placeholder: 'Pick a date',
                  onTap: _pickExpiryDate,
                  trailing: _expiryTrailing(context),
                ),
              ],
            ),
            CruFormSection(
              title: 'Bill and photo',
              description: 'A bill photo fills in what it can read. '
                  'Check the fields after.',
              children: [
                _billTile(context),
                _photoTile(context),
                if (_attachError != null) CruFieldError(_attachError!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget? _stockSummary(BuildContext context) {
    final c = context.cru;
    final stock = int.tryParse(_stock.text.trim());
    final threshold = int.tryParse(_threshold.text.trim()) ?? 10;
    final price = double.tryParse(_price.text.trim());
    // A blank new item starts at 0; don't flag it before anything is typed.
    final status = stock == null || (widget.medicine == null && !_dirty)
        ? null
        : stock == 0
            ? 'Out of stock'
            : stock <= threshold * kCriticalStockShare
                ? 'Critically low'
                : stock <= threshold
                    ? 'Low stock'
                    : null;
    final value = stock == null || price == null || price < 0
        ? null
        : InventoryFormat.rupees(price * stock);
    if (status == null && value == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s14,
        vertical: CruSpace.s12,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          if (value != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Stock value', style: CruType.caption.tint(c.label3)),
                  const SizedBox(height: CruSpace.s2),
                  Text(value, style: CruType.callout.tabular.tint(c.label)),
                ],
              ),
            )
          else
            const Spacer(),
          if (status != null) _WarnPill(status),
        ],
      ),
    );
  }

  Widget? _expiryTrailing(BuildContext context) {
    final days = _daysToExpiry;
    if (days == null) return null;
    final c = context.cru;
    final soon = days <= InventoryBuilder.expiringWithinDays;
    final when = InventoryFormat.inTime(days);
    final label = days < 0 ? 'Expired' : when[0].toUpperCase() + when.substring(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (soon)
          _WarnPill(label)
        else
          Text(label, style: CruType.caption.tint(c.label3)),
        const SizedBox(width: CruSpace.s4),
        CruPressable(
          onTap: () => setState(() {
            _expiryDate = null;
            _dirty = true;
          }),
          semanticLabel: 'Clear expiry date',
          tooltip: 'Clear',
          builder: (context, hovered) => Container(
            width: CruSize.formTagClose,
            height: CruSize.formTagClose,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: hovered ? c.surface : c.surface.withValues(alpha: 0),
              shape: cruShape(CruRadius.full),
            ),
            child: CruIcon(CruIcons.close, size: 12, strokeWidth: 2, color: c.label2),
          ),
        ),
      ],
    );
  }

  Widget _billTile(BuildContext context) {
    final receipt = _receiptImage;
    if (receipt == null) {
      return _AttachTile(
        leading: const CruIconTile(icon: _receiptIcon, tone: CruTileTone.neutral),
        title: 'Fill from a bill',
        subtitle: 'Supplier bill or a photo of the strip',
        onTap: _saving ? null : () => _pickReceiptImage(ImageSource.gallery),
        actions: [
          CruCapsuleButton(
            label: 'Choose…',
            kind: CruCapsuleKind.surface,
            onPressed:
                _saving ? null : () => _pickReceiptImage(ImageSource.gallery),
          ),
        ],
      );
    }
    final String subtitle;
    if (_scanning) {
      subtitle = 'Reading the bill…';
    } else if (_ocrFieldsFilled > 0) {
      subtitle = 'Filled ${InventoryFormat.plural(_ocrFieldsFilled, 'field')}';
    } else {
      subtitle = 'Nothing to fill in from this bill';
    }
    final c = context.cru;
    return _AttachTile(
      leading: _Thumb(path: receipt.path, fallback: _receiptIcon),
      title: receipt.name,
      subtitle: subtitle,
      actions: _scanning
          ? [
              SizedBox.square(
                dimension: CruSpace.s16,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.label3),
              ),
            ]
          : [
              CruCapsuleButton(
                label: 'Replace',
                kind: CruCapsuleKind.surface,
                onPressed: _saving
                    ? null
                    : () => _pickReceiptImage(ImageSource.gallery),
              ),
              CruIconButton(
                icon: CruIcons.close,
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _receiptImage = null;
                          _ocrFieldsFilled = 0;
                        }),
                semanticLabel: 'Remove bill',
                tooltip: 'Remove bill',
                size: CruSize.control,
                iconSize: 18,
              ),
            ],
    );
  }

  Widget _photoTile(BuildContext context) {
    final url = _imageUrl;
    final has = url != null && url.isNotEmpty;
    return _AttachTile(
      leading: has
          ? _Thumb(path: url, fallback: _imageIcon)
          : const CruIconTile(icon: _imageIcon, tone: CruTileTone.neutral),
      title: 'Item photo',
      subtitle: has ? 'Shown with the item' : 'The box or strip, to spot it faster',
      onTap: has || _saving ? null : _pickItemImage,
      actions: [
        CruCapsuleButton(
          label: has ? 'Replace' : 'Choose…',
          kind: CruCapsuleKind.surface,
          onPressed: _saving ? null : _pickItemImage,
        ),
        if (has)
          CruIconButton(
            icon: CruIcons.close,
            onPressed: _saving
                ? null
                : () => setState(() {
                      _imageUrl = null;
                      _dirty = true;
                    }),
            semanticLabel: 'Remove photo',
            tooltip: 'Remove photo',
            size: CruSize.control,
            iconSize: 18,
          ),
      ],
    );
  }
}

const _receiptIcon = CruIconData(
  'M6 3.5h12v17l-2.5-1.5-2 1.5-1.5-1.5-1.5 1.5-2-1.5L6 20.5z'
  'M9 8h6M9 12h6M9 16h3',
);

const _imageIcon = CruIconData(
  'M20.5 15.5l-4.5-4.5-8.5 8.5',
  rects: [(3.5, 4.5, 17, 15, 3)],
  circles: [(9, 10, 1.6)],
);

/// A text field with preset values as capsules underneath. The current
/// value is left out; typing narrows the list.
class _PresetField extends StatelessWidget {
  const _PresetField({
    required this.label,
    required this.controller,
    required this.presets,
    required this.onChanged,
    required this.onPick,
    this.hint,
    this.optional = false,
    this.validator,
  });

  static const _shown = 5;

  final String label;
  final TextEditingController controller;
  final List<String> presets;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onPick;
  final String? hint;
  final bool optional;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final q = controller.text.trim().toLowerCase();
    final others = presets.where((p) => p.toLowerCase() != q).toList();
    var open = q.isEmpty
        ? others
        : others.where((p) => p.toLowerCase().contains(q)).toList();
    if (open.isEmpty) open = others;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CruTextField(
          label: label,
          optional: optional,
          controller: controller,
          hint: hint,
          textCapitalization: TextCapitalization.words,
          validator: validator,
          onChanged: onChanged,
        ),
        const SizedBox(height: CruSpace.s8),
        Wrap(
          spacing: CruSpace.s6,
          runSpacing: CruSpace.s6,
          children: [
            for (final p in open.take(_shown))
              IntrinsicWidth(
                child: CruCapsuleButton(
                  label: p,
                  height: CruSize.rowCapsule,
                  onPressed: () => onPick(p),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A 60 px inset row for an attachment: tile or thumbnail, two lines of
/// text and its actions.
class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    Widget tile(bool hovered) => Container(
          constraints: const BoxConstraints(minHeight: CruSize.actionTile),
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s12,
            vertical: CruSpace.s12,
          ),
          decoration: ShapeDecoration(
            color: hovered ? cruHoverShade(c.inset, c) : c.inset,
            shape: cruShape(CruRadius.control),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: CruType.subhead.w500.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      subtitle,
                      style: CruType.caption.tint(c.label3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              for (final a in actions) ...[
                const SizedBox(width: CruSpace.s8),
                a,
              ],
            ],
          ),
        );
    if (onTap == null) return tile(false);
    return CruPressable(
      onTap: onTap,
      semanticLabel: title,
      scaleOnPress: false,
      builder: (context, hovered) => tile(hovered),
    );
  }
}

/// A picked image at icon-tile size; the icon tile if it can't be shown.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, required this.fallback});

  final String path;
  final CruIconData fallback;

  @override
  Widget build(BuildContext context) {
    Widget fail(BuildContext _, Object _, StackTrace? _) =>
        CruIconTile(icon: fallback, tone: CruTileTone.neutral);
    return ClipRRect(
      borderRadius: BorderRadius.circular(CruRadius.iconTile),
      child: SizedBox.square(
        dimension: CruSize.iconTile,
        child: kIsWeb || path.startsWith('http')
            ? Image.network(path, fit: BoxFit.cover, errorBuilder: fail)
            : Image.file(File(path), fit: BoxFit.cover, errorBuilder: fail),
      ),
    );
  }
}

/// Amber pill for a stock or expiry warning.
class _WarnPill extends StatelessWidget {
  const _WarnPill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: CruSize.infoPill,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      decoration: ShapeDecoration(
        color: c.amberTint,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CruIcon(CruIcons.warning, size: 13, strokeWidth: 2.2, color: c.amberText),
          const SizedBox(width: CruSpace.s6),
          Text(text, style: CruType.caption.w500.tabular.tint(c.amberText)),
        ],
      ),
    );
  }
}
