import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/services/paddle_ocr_service.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_icons.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens the desktop Create invoice form.
Future<InvoiceModel?> showDesktopCreateInvoiceDialog(
  BuildContext context, {
  InvoiceRepository? repository,
  Future<void> Function(
    String name,
    String service,
    double amount,
    String status,
    String notes,
    DateTime? dueDate,
    String? patientId,
  )? onSave,
  Patient? initialPatient,
  String? initialTreatmentName,
  double? initialTreatmentPrice,
  String? initialNotes,
}) {
  return showDialog<InvoiceModel>(
    context: context,
    barrierDismissible: true,
    builder: (_) => DesktopCreateInvoiceDialog(
      repository: repository,
      onSave: onSave,
      initialPatient: initialPatient,
      initialTreatmentName: initialTreatmentName,
      initialTreatmentPrice: initialTreatmentPrice,
      initialNotes: initialNotes,
    ),
  );
}

class DesktopCreateInvoiceDialog extends StatefulWidget {
  const DesktopCreateInvoiceDialog({
    super.key,
    this.repository,
    this.onSave,
    this.initialPatient,
    this.initialTreatmentName,
    this.initialTreatmentPrice,
    this.initialNotes,
  });

  /// Prefill (e.g. "Bill together" for patients seen together): the payer,
  /// a treatment line waiting for its price, and a note.
  final Patient? initialPatient;
  final String? initialTreatmentName;

  /// The treatment line's price, when the caller knows it (a radiology
  /// reading fee).
  final double? initialTreatmentPrice;
  final String? initialNotes;

  final InvoiceRepository? repository;
  final Future<void> Function(
    String name,
    String service,
    double amount,
    String status,
    String notes,
    DateTime? dueDate,
    String? patientId,
  )? onSave;

  @override
  State<DesktopCreateInvoiceDialog> createState() =>
      _DesktopCreateInvoiceDialogState();
}

class _TreatmentItem {
  final String name;
  final double price;
  _TreatmentItem({required this.name, required this.price});
}

class _MedicineItem {
  final String name;
  final String dosage;
  final double price;
  _MedicineItem({required this.name, required this.dosage, required this.price});
}

final _moneyFormatter = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

/// "₹1,200" for whole rupees, "₹1,200.50" when there are paise.
String _rupees(double v) => v == v.roundToDouble()
    ? DashFormat.rupees(v)
    : NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)
        .format(v);

class _DesktopCreateInvoiceDialogState
    extends State<DesktopCreateInvoiceDialog> {
  static const _statuses = ['Paid', 'Pending', 'Overdue'];

  final _formKey = GlobalKey<FormState>();
  late final InvoiceRepository _invoiceRepository =
      widget.repository ?? InvoiceRepository();
  late final PatientRepository _patientRepository = PatientRepository();
  Future<List<Patient>>? _patients;

  final _patientNameController = TextEditingController();
  final _clinicalNotesController = TextEditingController();

  final _treatmentNameController = TextEditingController();
  final _treatmentPriceController = TextEditingController();
  final _treatmentNameFocus = FocusNode();

  final _medicineNameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _medicinePriceController = TextEditingController();
  final _medicineNameFocus = FocusNode();

  final _discountController = TextEditingController();

  DateTime _invoiceDate = DateTime.now();
  DateTime? _dueDate;
  String _selectedStatus = 'Paid';

  Patient? _selectedPatient;
  String _patientSearchQuery = '';
  bool _showPatientSuggestions = false;

  final List<_TreatmentItem> _treatments = [];
  final List<_MedicineItem> _medicines = [];
  bool _isSubmitting = false;
  bool _isOcrLoading = false;
  bool _dirty = false;
  bool _submitted = false;
  String? _notice;
  String? _treatmentError;
  String? _medicineError;

  static final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final p = widget.initialPatient;
    if (p != null) {
      _selectedPatient = p;
      _patientNameController.text = p.fullName;
    }
    final t = widget.initialTreatmentName;
    if (t != null) _treatmentNameController.text = t;
    final price = widget.initialTreatmentPrice;
    if (price != null) _treatmentPriceController.text = price.toStringAsFixed(0);
    final n = widget.initialNotes;
    if (n != null) _clinicalNotesController.text = n;
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _clinicalNotesController.dispose();
    _treatmentNameController.dispose();
    _treatmentPriceController.dispose();
    _treatmentNameFocus.dispose();
    _medicineNameController.dispose();
    _dosageController.dispose();
    _medicinePriceController.dispose();
    _medicineNameFocus.dispose();
    _discountController.dispose();
    super.dispose();
  }

  double get _treatmentSubtotal =>
      _treatments.fold(0.0, (sum, t) => sum + t.price);

  double get _medicineSubtotal =>
      _medicines.fold(0.0, (sum, m) => sum + m.price);

  double get _discount =>
      double.tryParse(_discountController.text.trim()) ?? 0.0;

  double get _totalPayable =>
      ((_treatmentSubtotal + _medicineSubtotal) - _discount)
          .clamp(0.0, double.infinity);

  bool get _noItems => _treatments.isEmpty && _medicines.isEmpty;

  void _edited([Object? _]) {
    setState(() {
      _dirty = true;
      _notice = null;
    });
  }

  void _onPatientChanged(String val) {
    setState(() {
      _dirty = true;
      _notice = null;
      _patientSearchQuery = val.trim().toLowerCase();
      _showPatientSuggestions = _patientSearchQuery.isNotEmpty;
    });
  }

  void _pickPatient(Patient p) {
    setState(() {
      _dirty = true;
      _selectedPatient = p;
      _patientNameController.text = p.fullName;
      _showPatientSuggestions = false;
    });
  }

  Future<void> _pickInvoiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Invoice date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dirty = true;
      _invoiceDate = picked;
    });
  }

  Future<void> _pickDueDate() async {
    final fallback = _invoiceDate.add(const Duration(days: 7));
    final due = _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: due == null || due.isBefore(_invoiceDate) ? fallback : due,
      firstDate: _invoiceDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Due date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dirty = true;
      _dueDate = picked;
    });
  }

  Future<void> _scanMedicalBill() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;

      setState(() {
        _isOcrLoading = true;
        _notice = null;
      });

      final result = await PaddleOcrService.instance.scanInvoice(image);
      if (!mounted) return;

      setState(() {
        _isOcrLoading = false;
        _dirty = true;

        if (result.patientName != null && result.patientName!.isNotEmpty) {
          _patientNameController.text = result.patientName!;
        }

        if (result.clinicalNotes != null && result.clinicalNotes!.isNotEmpty) {
          _clinicalNotesController.text = result.clinicalNotes!;
        }

        for (final treatment in result.treatments) {
          _treatments.add(_TreatmentItem(
            name: treatment.name,
            price: treatment.price,
          ));
        }

        for (final med in result.medicines) {
          _medicines.add(_MedicineItem(
            name: med.name,
            dosage: med.dosage,
            price: med.price,
          ));
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${DashFormat.plural(result.treatments.length, 'treatment')} '
            'and ${DashFormat.plural(result.medicines.length, 'medicine')} '
            'from the bill.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isOcrLoading = false;
        _notice = "Couldn't read that bill. Try a clearer photo, "
            'or add the items by hand.';
      });
    }
  }

  void _addTreatment() {
    final name = _treatmentNameController.text.trim();
    final price = double.tryParse(_treatmentPriceController.text.trim()) ?? 0.0;
    if (name.isEmpty || price <= 0) {
      setState(() => _treatmentError = name.isEmpty
          ? 'Add the treatment name.'
          : 'Add a fee above ₹0.');
      return;
    }

    setState(() {
      _dirty = true;
      _treatmentError = null;
      _treatments.add(_TreatmentItem(name: name, price: price));
      _treatmentNameController.clear();
      _treatmentPriceController.clear();
    });
    _treatmentNameFocus.requestFocus();
  }

  void _addMedicine() {
    final name = _medicineNameController.text.trim();
    final dosage = _dosageController.text.trim();
    final price = double.tryParse(_medicinePriceController.text.trim()) ?? 0.0;
    if (name.isEmpty || price <= 0) {
      setState(() => _medicineError = name.isEmpty
          ? 'Add the medicine name.'
          : 'Add a price above ₹0.');
      return;
    }

    setState(() {
      _dirty = true;
      _medicineError = null;
      _medicines.add(_MedicineItem(
        name: name,
        dosage: dosage.isEmpty ? '1 unit' : dosage,
        price: price,
      ));
      _medicineNameController.clear();
      _dosageController.clear();
      _medicinePriceController.clear();
    });
    _medicineNameFocus.requestFocus();
  }

  Future<void> _handleSave() async {
    if (_isSubmitting) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    final patientName = _patientNameController.text.trim();
    if (patientName.isEmpty) return;

    if (_totalPayable <= 0 && _treatments.isEmpty && _medicines.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _notice = null;
    });

    try {
      final List<String> servicesList = [];
      if (_treatments.isNotEmpty) {
        servicesList.add('Treatments: ${_treatments.map((t) => t.name).join(", ")}');
      }
      if (_medicines.isNotEmpty) {
        servicesList.add('Medicines: ${_medicines.map((m) => m.name).join(", ")}');
      }
      final serviceSummary = servicesList.isNotEmpty
          ? servicesList.join(' | ')
          : 'Consultation & Clinical Services';

      final notes = _clinicalNotesController.text.trim();

      if (widget.onSave != null) {
        await widget.onSave!(
          patientName,
          serviceSummary,
          _totalPayable,
          _selectedStatus,
          notes,
          _dueDate ?? _invoiceDate,
          _selectedPatient?.id,
        );
      } else {
        await _invoiceRepository.createInvoice(
          patientName: patientName,
          service: serviceSummary,
          amount: _totalPayable,
          status: _selectedStatus,
          notes: notes,
          dueDate: _dueDate ?? _invoiceDate,
          patientId: _selectedPatient?.id,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _notice = "Couldn't create the invoice. "
            'Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _patientNameController.text.trim();
    return CruFormDialog(
      title: 'New invoice',
      subtitle: 'Bill a patient for treatments and medicines',
      leading: name.isEmpty
          ? const CruIconTile(
              icon: RevenueIcons.receipt,
              tone: CruTileTone.neutral,
            )
          : CruMonogram(name: name, size: CruSize.iconTile),
      submitLabel: 'Create invoice',
      onSubmit: _handleSave,
      busy: _isSubmitting,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to create',
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
              title: 'Patient',
              description: 'Who this bill is for.',
              children: [_buildPatientField()],
            ),
            CruFormSection(
              title: 'Billing',
              description: 'When it was issued and whether it has been paid.',
              children: [
                CruFieldRow(
                  children: [
                    CruPickerField(
                      label: 'Invoice date',
                      icon: CruIcons.calendar,
                      value: DateFormat('d MMM yyyy').format(_invoiceDate),
                      placeholder: 'Pick a date',
                      onTap: _pickInvoiceDate,
                    ),
                    CruPickerField(
                      label: 'Due date',
                      optional: true,
                      icon: CruIcons.clock,
                      value: _dueDate == null
                          ? null
                          : DateFormat('d MMM yyyy').format(_dueDate!),
                      placeholder: 'Same day',
                      onTap: _pickDueDate,
                    ),
                  ],
                ),
                CruFieldFrame(
                  label: 'Status',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CruSegmentedControl<String>(
                      semanticLabel: 'Payment status',
                      segments: [for (final s in _statuses) CruSegment(s, s)],
                      selected: _selectedStatus,
                      onChanged: (v) {
                        _selectedStatus = v;
                        _edited();
                      },
                    ),
                  ),
                ),
              ],
            ),
            _WideSection(
              title: 'Items',
              description: 'Treatments and medicines on this bill.',
              action: IntrinsicWidth(
                child: CruCapsuleButton(
                  label: _isOcrLoading ? 'Reading bill…' : 'Scan a bill',
                  onPressed: _isOcrLoading ? null : _scanMedicalBill,
                ),
              ),
              error: _submitted && _noItems
                  ? 'Add at least one treatment or medicine.'
                  : null,
              children: [
                _buildTreatments(),
                _buildMedicines(),
                _buildTotals(),
              ],
            ),
            CruFormSection(
              title: 'Notes',
              description: 'Saved with the invoice.',
              children: [
                CruTextField(
                  label: 'Clinical notes',
                  optional: true,
                  controller: _clinicalNotesController,
                  maxLines: 4,
                  hint: 'Diagnosis, procedure notes, follow-up advice…',
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

  Widget _buildPatientField() {
    final linked = _selectedPatient;
    final phone = linked?.phone.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruTextField(
          label: 'Patient name',
          controller: _patientNameController,
          icon: CruIcons.search,
          hint: 'Search your patients or type a name',
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          help: linked == null
              ? 'Pick someone from your list to link the bill to their record.'
              : phone.isEmpty
                  ? 'Linked to ${linked.fullName}'
                  : 'Linked to ${linked.fullName} · $phone',
          trailing: linked == null
              ? null
              : CruLink(
                  label: 'Unlink',
                  style: CruType.caption.w600,
                  onPressed: () {
                    _selectedPatient = null;
                    _edited();
                  },
                ),
          validator: (val) => (val == null || val.trim().isEmpty)
              ? "Add the patient's name."
              : null,
          onChanged: _onPatientChanged,
        ),
        if (_showPatientSuggestions) _buildPatientSuggestions(),
      ],
    );
  }

  Widget _buildPatientSuggestions() {
    _patients ??= _patientRepository.watchPatients().first;
    return FutureBuilder<List<Patient>>(
      future: _patients,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final matches = snapshot.data!
            .where((p) =>
                p.fullName.toLowerCase().contains(_patientSearchQuery) ||
                p.phone.contains(_patientSearchQuery))
            .take(4)
            .toList();
        if (matches.isEmpty) return const SizedBox.shrink();

        final c = context.cru;
        return Container(
          margin: const EdgeInsets.only(top: CruSpace.s8),
          padding: const EdgeInsets.all(CruSpace.s4),
          decoration: ShapeDecoration(
            color: c.surface,
            shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
            shadows: c.cardShadow,
          ),
          child: Column(
            children: [
              for (final p in matches) _PatientOption(patient: p, onTap: () => _pickPatient(p)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTreatments() {
    return _LineGroup(
      title: 'Treatments',
      count: _treatments.length,
      rows: [
        for (var i = 0; i < _treatments.length; i++)
          _LineRow(
            flex: const [7, 2],
            cells: [_treatments[i].name],
            amount: _treatments[i].price,
            onRemove: () {
              _treatments.removeAt(i);
              _edited();
            },
          ),
      ],
      addRow: _AddRow(
        flex: const [7, 2],
        inputs: [
          _LineInput(
            controller: _treatmentNameController,
            focusNode: _treatmentNameFocus,
            hint: 'Treatment or procedure',
            textCapitalization: TextCapitalization.sentences,
            onChanged: _onTreatmentTyped,
          ),
          _LineInput(
            controller: _treatmentPriceController,
            hint: 'Fee',
            prefix: '₹',
            tabular: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _moneyFormatter,
            textInputAction: TextInputAction.done,
            onChanged: _onTreatmentTyped,
            onSubmitted: (_) => _addTreatment(),
          ),
        ],
        addLabel: 'Add treatment',
        onAdd: _addTreatment,
      ),
      error: _treatmentError,
    );
  }

  Widget _buildMedicines() {
    return _LineGroup(
      title: 'Medicines',
      count: _medicines.length,
      rows: [
        for (var i = 0; i < _medicines.length; i++)
          _LineRow(
            flex: const [5, 2, 2],
            cells: [_medicines[i].name, _medicines[i].dosage],
            amount: _medicines[i].price,
            onRemove: () {
              _medicines.removeAt(i);
              _edited();
            },
          ),
      ],
      addRow: _AddRow(
        flex: const [5, 2, 2],
        inputs: [
          _LineInput(
            controller: _medicineNameController,
            focusNode: _medicineNameFocus,
            hint: 'Medicine',
            textCapitalization: TextCapitalization.sentences,
            onChanged: _onMedicineTyped,
          ),
          _LineInput(
            controller: _dosageController,
            hint: '1-0-1',
            onChanged: _onMedicineTyped,
          ),
          _LineInput(
            controller: _medicinePriceController,
            hint: 'Price',
            prefix: '₹',
            tabular: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _moneyFormatter,
            textInputAction: TextInputAction.done,
            onChanged: _onMedicineTyped,
            onSubmitted: (_) => _addMedicine(),
          ),
        ],
        addLabel: 'Add medicine',
        onAdd: _addMedicine,
      ),
      error: _medicineError,
    );
  }

  void _onTreatmentTyped(String _) => setState(() {
        _dirty = true;
        _treatmentError = null;
      });

  void _onMedicineTyped(String _) => setState(() {
        _dirty = true;
        _medicineError = null;
      });

  Widget _buildTotals() {
    final c = context.cru;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_treatments.isNotEmpty)
                _TotalLine(label: 'Treatments', value: _rupees(_treatmentSubtotal)),
              if (_medicines.isNotEmpty)
                _TotalLine(label: 'Medicines', value: _rupees(_medicineSubtotal)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text('Discount', style: CruType.text.tint(c.label2)),
                    ),
                    Expanded(
                      flex: 2,
                      child: _LineInput(
                        controller: _discountController,
                        hint: '0',
                        prefix: '−₹',
                        tabular: true,
                        textAlign: TextAlign.right,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: _moneyFormatter,
                        onChanged: _edited,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CruSpace.s6),
              const CruSeparator(),
              const SizedBox(height: CruSpace.s12),
              Row(
                children: [
                  Expanded(
                    child: Text('Total', style: CruType.callout.tint(c.label)),
                  ),
                  Text(
                    _rupees(_totalPayable),
                    style: CruType.title2.tabular.tint(c.label),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A section that uses the full dialog width: title and description on
/// top with an optional action, then its children.
class _WideSection extends StatelessWidget {
  const _WideSection({
    required this.title,
    required this.description,
    required this.children,
    this.action,
    this.error,
  });

  final String title;
  final String description;
  final List<Widget> children;
  final Widget? action;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CruSeparator(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: CruType.callout.tint(c.label)),
                        const SizedBox(height: CruSpace.s4),
                        Text(description, style: CruType.caption.tint(c.label3)),
                      ],
                    ),
                  ),
                  ?action,
                ],
              ),
              if (error != null) CruFieldError(error!),
              for (final child in children) ...[
                const SizedBox(height: CruSpace.s20),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A labelled group of line items: the added rows in a hairline panel,
/// then an add row.
class _LineGroup extends StatelessWidget {
  const _LineGroup({
    required this.title,
    required this.count,
    required this.rows,
    required this.addRow,
    this.error,
  });

  final String title;
  final int count;
  final List<Widget> rows;
  final Widget addRow;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: CruType.subhead.w500.tint(c.label2)),
            if (count > 0) ...[
              const SizedBox(width: CruSpace.s6),
              Text(
                DashFormat.plural(count, 'item'),
                style: CruType.caption.tabular.tint(c.label3),
              ),
            ],
          ],
        ),
        const SizedBox(height: CruSpace.s8),
        if (rows.isNotEmpty) ...[
          DecoratedBox(
            decoration: ShapeDecoration(
              color: c.surface,
              shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const CruSeparator(indent: CruSpace.s14),
                  rows[i],
                ],
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s8),
        ],
        addRow,
        if (error != null) CruFieldError(error!),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.flex,
    required this.cells,
    required this.amount,
    required this.onRemove,
  });

  /// Flex for each cell, then the amount.
  final List<int> flex;
  final List<String> cells;
  final double amount;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(
        left: CruSpace.s14,
        right: CruSpace.s6,
        top: CruSpace.s6,
        bottom: CruSpace.s6,
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: flex[i],
              child: Padding(
                padding: const EdgeInsets.only(right: CruSpace.s12),
                child: Text(
                  cells[i],
                  style: i == 0
                      ? CruType.text.w500.tint(c.label)
                      : CruType.subhead.tint(c.label2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          Expanded(
            flex: flex.last,
            child: Text(
              _rupees(amount),
              textAlign: TextAlign.right,
              style: CruType.text.w500.tabular.tint(c.label),
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          CruIconButton(
            icon: CruIcons.close,
            onPressed: onRemove,
            semanticLabel: 'Remove ${cells.first}',
            tooltip: 'Remove',
            size: CruSize.rowCapsule,
            iconSize: 14,
          ),
        ],
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.flex,
    required this.inputs,
    required this.addLabel,
    required this.onAdd,
  });

  final List<int> flex;
  final List<Widget> inputs;
  final String addLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < inputs.length; i++) ...[
          if (i > 0) const SizedBox(width: CruSpace.s8),
          Expanded(flex: flex[i], child: inputs[i]),
        ],
        const SizedBox(width: CruSpace.s8),
        CruCapsuleButton(
          label: 'Add',
          semanticLabel: addLabel,
          icon: CruIcons.plus,
          height: CruSize.control,
          onPressed: onAdd,
        ),
      ],
    );
  }
}

/// A 40 px inset input without a label, for line items and the discount.
class _LineInput extends StatefulWidget {
  const _LineInput({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.prefix,
    this.tabular = false,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final String? prefix;
  final bool tabular;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_LineInput> createState() => _LineInputState();
}

class _LineInputState extends State<_LineInput> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final focused = _focus.hasFocus;
    final base = CruType.input.tint(c.label);
    return AnimatedContainer(
      duration: CruMotion.of(context, CruMotion.fast),
      curve: CruMotion.curve,
      height: CruSize.control,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
      decoration: ShapeDecoration(
        color: focused ? c.surface : c.inset,
        shape: cruShape(
          CruRadius.control,
          side: BorderSide(
            color: focused ? c.accent : c.inset.withValues(alpha: 0),
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (widget.prefix != null) ...[
            Text(widget.prefix!, style: CruType.input.w500.tint(c.label2)),
            const SizedBox(width: CruSpace.s6),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              textCapitalization: widget.textCapitalization,
              inputFormatters: widget.inputFormatters,
              textAlign: widget.textAlign,
              cursorColor: c.accent,
              style: widget.tabular ? base.tabular : base,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              decoration: InputDecoration.collapsed(
                hintText: widget.hint,
                hintStyle: CruType.input.tint(c.label3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: CruType.text.tint(c.label2))),
          Text(value, style: CruType.text.w500.tabular.tint(c.label)),
        ],
      ),
    );
  }
}

class _PatientOption extends StatelessWidget {
  const _PatientOption({required this.patient, required this.onTap});

  final Patient patient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final phone = patient.phone.trim();
    return CruPressable(
      onTap: onTap,
      semanticLabel: patient.fullName,
      scaleOnPress: false,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s10,
          vertical: CruSpace.s6,
        ),
        decoration: ShapeDecoration(
          color: hovered ? c.inset : c.inset.withValues(alpha: 0),
          shape: cruShape(CruRadius.segmentInner),
        ),
        child: Row(
          children: [
            CruMonogram(name: patient.fullName, size: CruSize.rowCapsule),
            const SizedBox(width: CruSpace.s10),
            Expanded(
              child: Text(
                patient.fullName,
                style: CruType.text.w500.tint(c.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (phone.isNotEmpty)
              Text(phone, style: CruType.subhead.tabular.tint(c.label3)),
          ],
        ),
      ),
    );
  }
}
