import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/services/paddle_ocr_service.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';

/// Opens the desktop-specific Create Invoice modal popup dialog.
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
}) {
  return showDialog<InvoiceModel>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 900,
          maxHeight: 780,
        ),
        child: DesktopCreateInvoiceDialog(
          repository: repository,
          onSave: onSave,
        ),
      ),
    ),
  );
}

class DesktopCreateInvoiceDialog extends StatefulWidget {
  const DesktopCreateInvoiceDialog({
    super.key,
    this.repository,
    this.onSave,
  });

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

class _DesktopCreateInvoiceDialogState
    extends State<DesktopCreateInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final InvoiceRepository _invoiceRepository =
      widget.repository ?? InvoiceRepository();
  final PatientRepository _patientRepository = PatientRepository();

  // Patient & Notes
  final _patientNameController = TextEditingController();
  final _clinicalNotesController = TextEditingController();

  // New Treatment Inputs
  final _treatmentNameController = TextEditingController();
  final _treatmentPriceController = TextEditingController();

  // New Medicine Inputs
  final _medicineNameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _medicinePriceController = TextEditingController();

  // Discount
  final _discountController = TextEditingController(text: '0');

  // Dates & Status
  DateTime _invoiceDate = DateTime.now();
  DateTime? _dueDate;
  String _selectedStatus = 'Paid'; // 'Paid', 'Pending', 'Overdue'

  // Patient Autocomplete
  Patient? _selectedPatient;
  String _patientSearchQuery = '';
  bool _showPatientSuggestions = false;

  // Lists & State
  final List<_TreatmentItem> _treatments = [];
  final List<_MedicineItem> _medicines = [];
  bool _isSubmitting = false;
  bool _isOcrLoading = false;
  String? _errorText;

  static final _imagePicker = ImagePicker();

  @override
  void dispose() {
    _patientNameController.dispose();
    _clinicalNotesController.dispose();
    _treatmentNameController.dispose();
    _treatmentPriceController.dispose();
    _medicineNameController.dispose();
    _dosageController.dispose();
    _medicinePriceController.dispose();
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

  Future<void> _scanMedicalBill() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;

      setState(() => _isOcrLoading = true);

      final result = await PaddleOcrService.instance.scanInvoice(image);
      if (!mounted) return;

      setState(() {
        _isOcrLoading = false;

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
            'OCR parsed ${result.treatments.length} treatments and ${result.medicines.length} medicines successfully!',
          ),
          backgroundColor: const Color(0xFF059669),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isOcrLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _addTreatment() {
    final name = _treatmentNameController.text.trim();
    final price = double.tryParse(_treatmentPriceController.text.trim()) ?? 0.0;
    if (name.isEmpty || price <= 0) return;

    setState(() {
      _treatments.add(_TreatmentItem(name: name, price: price));
      _treatmentNameController.clear();
      _treatmentPriceController.clear();
    });
  }

  void _addMedicine() {
    final name = _medicineNameController.text.trim();
    final dosage = _dosageController.text.trim();
    final price = double.tryParse(_medicinePriceController.text.trim()) ?? 0.0;
    if (name.isEmpty || price <= 0) return;

    setState(() {
      _medicines.add(_MedicineItem(
        name: name,
        dosage: dosage.isEmpty ? '1 unit' : dosage,
        price: price,
      ));
      _medicineNameController.clear();
      _dosageController.clear();
      _medicinePriceController.clear();
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final patientName = _patientNameController.text.trim();
    if (patientName.isEmpty) {
      setState(() => _errorText = 'Please enter or select a patient name');
      return;
    }

    if (_totalPayable <= 0 && _treatments.isEmpty && _medicines.isEmpty) {
      setState(() => _errorText = 'Please add at least one treatment or medicine item');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = 'Failed to generate invoice: $e';
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
                      // Left Column: Patient, Dates, Status, Notes
                      Expanded(
                        flex: 10,
                        child: _buildLeftColumn(),
                      ),
                      const SizedBox(width: 24),
                      // Vertical separator
                      Container(
                        width: 1,
                        height: 560,
                        color: const Color(0xFFF1F5F9),
                      ),
                      const SizedBox(width: 24),
                      // Right Column: Treatments, Prescriptions, Summary
                      Expanded(
                        flex: 11,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New Patient Invoice',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Generate itemized medical invoice with treatments, medicines, and billing breakdown',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _isOcrLoading ? null : _scanMedicalBill,
            icon: _isOcrLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner_rounded, size: 16),
            label: Text(_isOcrLoading ? 'Scanning Bill...' : 'Scan Bill (OCR)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFF93C5FD)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 8),
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
          'PATIENT INFORMATION *',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        // Patient Search / Name Autocomplete
        TextFormField(
          controller: _patientNameController,
          onChanged: (val) {
            setState(() {
              _patientSearchQuery = val.trim().toLowerCase();
              _showPatientSuggestions = _patientSearchQuery.isNotEmpty;
            });
          },
          style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            hintText: 'Search or enter patient name...',
            prefixIcon: const Icon(Icons.person_outline_rounded, size: 18, color: Color(0xFF64748B)),
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
              (val == null || val.trim().isEmpty) ? 'Please enter a patient name' : null,
        ),
        if (_showPatientSuggestions) _buildPatientSuggestionsList(),
        if (_selectedPatient != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, size: 14, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Linked: ${_selectedPatient!.fullName} (${_selectedPatient!.phone})',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF)),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _selectedPatient = null),
                  child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF1E40AF)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'INVOICE DATE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _invoiceDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _invoiceDate = picked);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF2563EB)),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('dd MMM yyyy').format(_invoiceDate),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DUE DATE (OPTIONAL)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dueDate ?? _invoiceDate.add(const Duration(days: 7)),
                        firstDate: _invoiceDate,
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _dueDate = picked);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_available_rounded, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Text(
                            _dueDate != null
                                ? DateFormat('dd MMM yyyy').format(_dueDate!)
                                : 'Same Day',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _dueDate != null ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'PAYMENT STATUS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: ['Paid', 'Pending', 'Overdue'].map((status) {
            final isSelected = _selectedStatus == status;
            Color statusColor;
            Color statusBg;
            switch (status) {
              case 'Paid':
                statusColor = const Color(0xFF059669);
                statusBg = const Color(0xFFECFDF5);
                break;
              case 'Pending':
                statusColor = const Color(0xFFD97706);
                statusBg = const Color(0xFFFFFBEB);
                break;
              default:
                statusColor = const Color(0xFFDC2626);
                statusBg = const Color(0xFFFEF2F2);
            }

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => setState(() => _selectedStatus = status),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? statusBg : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? statusColor : const Color(0xFFE2E8F0),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? statusColor : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text(
          'CLINICAL NOTES & DIAGNOSIS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _clinicalNotesController,
          maxLines: 4,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            hintText: 'Add clinical impressions, procedure notes, follow-up advice, or prescriptions details...',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.all(14),
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
      ],
    );
  }

  Widget _buildPatientSuggestionsList() {
    return FutureBuilder<List<Patient>>(
      future: _patientRepository.watchPatients().first,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final matches = snapshot.data!
            .where((p) =>
                p.fullName.toLowerCase().contains(_patientSearchQuery) ||
                p.phone.contains(_patientSearchQuery))
            .take(4)
            .toList();

        if (matches.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCBD5E1)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: matches.map((p) {
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedPatient = p;
                    _patientNameController.text = p.fullName;
                    _showPatientSuggestions = false;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.person_rounded, size: 16, color: Color(0xFF2563EB)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.fullName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        p.phone,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildRightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Treatments Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'TREATMENTS & PROCEDURES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.8,
              ),
            ),
            Text(
              '${_treatments.length} items',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 12,
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _treatmentNameController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Treatment name (e.g. Scaling)',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 7,
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _treatmentPriceController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Fee (₹)',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _addTreatment,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(0, 38),
              ),
              child: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_treatments.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: _treatments.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF059669)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(item.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                      Text('₹${item.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() => _treatments.removeAt(idx)),
                        child: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Medicines Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'PRESCRIBED MEDICINES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.8,
              ),
            ),
            Text(
              '${_medicines.length} items',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 10,
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _medicineNameController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Medicine (e.g. Paracetamol)',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 6,
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _dosageController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Dosage (1-0-1)',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 6,
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _medicinePriceController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Price (₹)',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _addMedicine,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(0, 38),
              ),
              child: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_medicines.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: _medicines.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.medication_liquid_rounded, size: 14, color: Color(0xFF2563EB)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${item.name} (${item.dosage})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                      Text('₹${item.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() => _medicines.removeAt(idx)),
                        child: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Live Financial Summary
        _buildBillingSummaryCard(),
      ],
    );
  }

  Widget _buildBillingSummaryCard() {
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
          const Text(
            'INVOICE TOTAL BREAKDOWN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Treatments Total:', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
              Text('₹${_treatmentSubtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Medicines Total:', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
              Text('₹${_medicineSubtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text('Discount Applied:', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
              ),
              SizedBox(
                width: 80,
                height: 28,
                child: TextField(
                  controller: _discountController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixText: '- ₹',
                    prefixStyle: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFCBD5E1)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Grand Total Payable:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
              ),
              Text(
                '₹${NumberFormat('#,##0.00').format(_totalPayable)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2563EB),
                ),
              ),
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
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
            onPressed: _isSubmitting ? null : _handleSave,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Generate Invoice',
                        style: TextStyle(
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
