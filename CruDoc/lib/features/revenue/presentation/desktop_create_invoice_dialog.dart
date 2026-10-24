import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/clinic/clinic_doctors_provider.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/core/pdf/data/doc_settings_models.dart';
import 'package:doctor_management_app/core/pdf/presentation/medical_pdf_preview_screen.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context_builder.dart';
import 'package:doctor_management_app/core/pdf/render/pdf_text.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/revenue/data/invoice_pdf_mapper.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_bill.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/services/paddle_ocr_service.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_icons.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/features/voice/domain/name_matcher.dart';
import 'package:doctor_management_app/features/voice/presentation/voice_dialog_hook.dart';
import 'package:doctor_management_app/features/voice/services/voice_form_ai.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

class InvoiceDialogResult {
  const InvoiceDialogResult({
    required this.invoice,
    this.patient,
  });

  final InvoiceModel invoice;
  final Patient? patient;
}

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
  )?
  onSave,
  Patient? initialPatient,
  String? initialTreatmentName,
  double? initialTreatmentPrice,
  String? initialNotes,
  String? attendingDoctorUid,
  InvoiceModel? initialInvoice,
  bool openPreview = true,
}) async {
  final result = await showDialog<InvoiceDialogResult>(
    context: context,
    barrierDismissible: true,
    builder: (_) => DesktopCreateInvoiceDialog(
      repository: repository,
      onSave: onSave,
      initialPatient: initialPatient,
      initialTreatmentName: initialTreatmentName,
      initialTreatmentPrice: initialTreatmentPrice,
      initialNotes: initialNotes,
      attendingDoctorUid: attendingDoctorUid,
      initialInvoice: initialInvoice,
    ),
  );

  if (result == null) return null;

  if (openPreview && onSave == null && context.mounted) {
    await MedicalPdfPreviewScreen.open(
      context,
      documentData: invoicePdfData(result.invoice, patient: result.patient),
      invoice: result.invoice,
    );
  }

  return result.invoice;
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
    this.attendingDoctorUid,
    this.initialInvoice,
  });

  final Patient? initialPatient;
  final String? initialTreatmentName;
  final double? initialTreatmentPrice;
  final String? initialNotes;
  final String? attendingDoctorUid;
  final InvoiceModel? initialInvoice;

  final InvoiceRepository? repository;
  final Future<void> Function(
    String name,
    String service,
    double amount,
    String status,
    String notes,
    DateTime? dueDate,
    String? patientId,
  )?
  onSave;

  @override
  State<DesktopCreateInvoiceDialog> createState() =>
      _DesktopCreateInvoiceDialogState();
}

class _TreatmentItem {
  final String name;
  final int qty;
  final double price;
  final double taxPct;

  _TreatmentItem({
    required this.name,
    this.qty = 1,
    required this.price,
    this.taxPct = 0,
  });
}

class _MedicineItem {
  final String name;
  final int qty;
  final String dosage;
  final double price;
  final double taxPct;

  _MedicineItem({
    required this.name,
    this.qty = 1,
    required this.dosage,
    required this.price,
    this.taxPct = 0,
  });
}

final _moneyFormatter = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
final _qtyFormatter = [FilteringTextInputFormatter.digitsOnly];

class _DesktopCreateInvoiceDialogState extends State<DesktopCreateInvoiceDialog>
    with VoiceDialogHook<DesktopCreateInvoiceDialog> {
  static const _statuses = ['Paid', 'Pending', 'Overdue'];
  static const _paymentModes = ['Cash', 'UPI', 'Card', 'Net banking', 'Other'];

  final _formKey = GlobalKey<FormState>();
  late final InvoiceRepository _invoiceRepository =
      widget.repository ?? InvoiceRepository();
  late final PatientRepository _patientRepository = PatientRepository();
  Future<List<Patient>>? _patients;

  final _patientNameController = TextEditingController();
  final _clinicalNotesController = TextEditingController();

  final _treatmentNameController = TextEditingController();
  final _treatmentQtyController = TextEditingController(text: '1');
  final _treatmentPriceController = TextEditingController();
  final _treatmentTaxController = TextEditingController(text: '0');
  final _treatmentNameFocus = FocusNode();

  final _medicineNameController = TextEditingController();
  final _medicineQtyController = TextEditingController(text: '1');
  final _dosageController = TextEditingController();
  final _medicinePriceController = TextEditingController();
  final _medicineTaxController = TextEditingController(text: '0');
  final _medicineNameFocus = FocusNode();

  final _discountController = TextEditingController();
  final _amountReceivedController = TextEditingController();
  final _invoiceNumberController = TextEditingController();

  DateTime _invoiceDate = DateTime.now();
  DateTime? _dueDate;
  String _selectedStatus = 'Paid';
  String _selectedPaymentMode = 'Cash';
  String? _attendingDoctorUid;
  bool _manualNumber = false;
  ClinicDocSettings? _docSettings;

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
    _attendingDoctorUid =
        widget.attendingDoctorUid ?? defaultIssuingDoctorUid();

    DocRepository.instance.clinicSettingsOnce().then((s) {
      if (mounted) setState(() => _docSettings = s);
    });

    final inv = widget.initialInvoice;
    if (inv != null) {
      _patientNameController.text = inv.patientName;
      _clinicalNotesController.text = inv.notes;
      _invoiceDate = inv.date;
      _dueDate = inv.dueDate;
      _selectedStatus = inv.status;
      _attendingDoctorUid = inv.attendingDoctorUid.isNotEmpty
          ? inv.attendingDoctorUid
          : _attendingDoctorUid;

      if (inv.invoiceNumber.isNotEmpty) {
        _manualNumber = true;
        _invoiceNumberController.text = inv.invoiceNumber;
      }

      final bill = inv.bill;
      if (bill.items.isNotEmpty) {
        for (final item in bill.items) {
          if (item.kind == 'medicine') {
            _medicines.add(_MedicineItem(
              name: item.name,
              qty: item.qty,
              dosage: item.note,
              price: item.ratePaise / 100.0,
              taxPct: item.taxPct,
            ));
          } else {
            _treatments.add(_TreatmentItem(
              name: item.name,
              qty: item.qty,
              price: item.ratePaise / 100.0,
              taxPct: item.taxPct,
            ));
          }
        }
        if (bill.discountPaise > 0) {
          _discountController.text = (bill.discountPaise / 100.0).toStringAsFixed(
            bill.discountPaise % 100 == 0 ? 0 : 2,
          );
        }
        _amountReceivedController.text = (bill.paidPaise / 100.0).toStringAsFixed(
          bill.paidPaise % 100 == 0 ? 0 : 2,
        );
        if (bill.paymentMode.isNotEmpty) {
          _selectedPaymentMode = bill.paymentMode;
        }
      } else {
        _treatments.add(_TreatmentItem(
          name: inv.service.isNotEmpty ? inv.service : 'Medical Consultation',
          price: inv.amount,
        ));
        _amountReceivedController.text = inv.isPaid ? inv.amount.toStringAsFixed(0) : '0';
      }
    } else {
      final p = widget.initialPatient;
      if (p != null) {
        _selectedPatient = p;
        _patientNameController.text = p.fullName;
      }
      final t = widget.initialTreatmentName;
      if (t != null) _treatmentNameController.text = t;
      final price = widget.initialTreatmentPrice;
      if (price != null) {
        _treatmentPriceController.text = price.toStringAsFixed(0);
      }
      final n = widget.initialNotes;
      if (n != null) _clinicalNotesController.text = n;
    }
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _clinicalNotesController.dispose();
    _treatmentNameController.dispose();
    _treatmentQtyController.dispose();
    _treatmentPriceController.dispose();
    _treatmentTaxController.dispose();
    _treatmentNameFocus.dispose();
    _medicineNameController.dispose();
    _medicineQtyController.dispose();
    _dosageController.dispose();
    _medicinePriceController.dispose();
    _medicineTaxController.dispose();
    _medicineNameFocus.dispose();
    _discountController.dispose();
    _amountReceivedController.dispose();
    _invoiceNumberController.dispose();
    super.dispose();
  }

  bool get _gstEnabled => _docSettings?.gstEnabled ?? false;

  InvoiceBill get _bill {
    final items = [
      for (final t in _treatments)
        InvoiceBillItem(
          name: t.name,
          qty: t.qty,
          ratePaise: toPaise(t.price),
          taxPct: t.taxPct,
          kind: 'treatment',
        ),
      for (final m in _medicines)
        InvoiceBillItem(
          name: m.name,
          qty: m.qty,
          ratePaise: toPaise(m.price),
          taxPct: m.taxPct,
          kind: 'medicine',
          note: m.dosage,
        ),
    ];
    final disc = double.tryParse(_discountController.text.trim()) ?? 0.0;
    final paid = double.tryParse(_amountReceivedController.text.trim()) ?? 0.0;
    return InvoiceBill(
      items: items,
      discountPaise: toPaise(disc),
      roundOff: _docSettings?.roundOff ?? true,
      paidPaise: toPaise(paid),
      paymentMode: _selectedPaymentMode,
      signedByUid: widget.initialInvoice?.bill.signedByUid ?? '',
      templateId: widget.initialInvoice?.bill.templateId ?? '',
    );
  }

  InvoiceTotals get _totals => InvoiceTotals.of(_bill);

  bool get _noItems => _treatments.isEmpty && _medicines.isEmpty;

  void _edited([Object? _]) {
    setState(() {
      _dirty = true;
      _notice = null;
    });
  }

  void _syncPaidAmountToTotal() {
    final total = _totals.grand / 100.0;
    _amountReceivedController.text =
        total % 1 == 0 ? total.toStringAsFixed(0) : total.toStringAsFixed(2);
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
          _treatments.add(
            _TreatmentItem(name: treatment.name, qty: 1, price: treatment.price),
          );
        }

        for (final med in result.medicines) {
          _medicines.add(
            _MedicineItem(
              name: med.name,
              qty: 1,
              dosage: med.dosage,
              price: med.price,
            ),
          );
        }

        if (_selectedStatus == 'Paid') {
          _syncPaidAmountToTotal();
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
        _notice =
            "Couldn't read that bill. Try a clearer photo, "
            'or add the items by hand.';
      });
    }
  }

  void _addTreatment() {
    final name = _treatmentNameController.text.trim();
    final qty = int.tryParse(_treatmentQtyController.text.trim()) ?? 1;
    final price = double.tryParse(_treatmentPriceController.text.trim()) ?? 0.0;
    final taxPct = _gstEnabled
        ? (double.tryParse(_treatmentTaxController.text.trim()) ?? 0.0)
        : 0.0;

    if (name.isEmpty || price <= 0 || qty <= 0) {
      setState(
        () => _treatmentError = name.isEmpty
            ? 'Add the treatment name.'
            : (qty <= 0 ? 'Qty must be at least 1.' : 'Add a fee above ₹0.'),
      );
      return;
    }

    setState(() {
      _dirty = true;
      _treatmentError = null;
      _treatments.add(
        _TreatmentItem(name: name, qty: qty, price: price, taxPct: taxPct),
      );
      _treatmentNameController.clear();
      _treatmentQtyController.text = '1';
      _treatmentPriceController.clear();
      _treatmentTaxController.text = '0';
      if (_selectedStatus == 'Paid') _syncPaidAmountToTotal();
    });
    _treatmentNameFocus.requestFocus();
  }

  void _addMedicine() {
    final name = _medicineNameController.text.trim();
    final qty = int.tryParse(_medicineQtyController.text.trim()) ?? 1;
    final dosage = _dosageController.text.trim();
    final price = double.tryParse(_medicinePriceController.text.trim()) ?? 0.0;
    final taxPct = _gstEnabled
        ? (double.tryParse(_medicineTaxController.text.trim()) ?? 0.0)
        : 0.0;

    if (name.isEmpty || price <= 0 || qty <= 0) {
      setState(
        () => _medicineError = name.isEmpty
            ? 'Add the medicine name.'
            : (qty <= 0 ? 'Qty must be at least 1.' : 'Add a price above ₹0.'),
      );
      return;
    }

    setState(() {
      _dirty = true;
      _medicineError = null;
      _medicines.add(
        _MedicineItem(
          name: name,
          qty: qty,
          dosage: dosage.isEmpty ? '1 unit' : dosage,
          price: price,
          taxPct: taxPct,
        ),
      );
      _medicineNameController.clear();
      _medicineQtyController.text = '1';
      _dosageController.clear();
      _medicinePriceController.clear();
      _medicineTaxController.text = '0';
      if (_selectedStatus == 'Paid') _syncPaidAmountToTotal();
    });
    _medicineNameFocus.requestFocus();
  }

  Future<void> _onDoctorSelected(
    String? uid,
    List<ClinicMember> doctors,
  ) async {
    setState(() {
      _attendingDoctorUid = (uid != null && uid.isNotEmpty) ? uid : null;
      _edited();
    });

    if (uid != null &&
        uid.isNotEmpty &&
        _treatments.isEmpty &&
        _medicines.isEmpty) {
      final prof = await DocRepository.instance.doctorProfileOnce(uid);
      if (prof != null &&
          prof.consultFeePaise > 0 &&
          _treatments.isEmpty &&
          _medicines.isEmpty &&
          mounted) {
        final doc = doctors.where((d) => d.uid == uid).firstOrNull;
        final docName = doc?.name ?? 'Doctor';
        setState(() {
          _treatments.add(_TreatmentItem(
            name: 'Consultation — $docName',
            qty: 1,
            price: prof.consultFeePaise / 100.0,
          ));
          if (_selectedStatus == 'Paid') _syncPaidAmountToTotal();
        });
      }
    }
  }

  // ── Voice ─────────────────────────────────────────────────────────────

  @override
  String get voiceKind => 'invoice';

  @override
  Map<String, Object?> voiceValues() => {
    'patientName': _patientNameController.text.trim(),
    'treatments': [
      for (final t in _treatments)
        {'name': t.name, 'qty': t.qty, 'price': t.price},
    ],
    'medicines': [
      for (final m in _medicines)
        {'name': m.name, 'qty': m.qty, 'dosage': m.dosage, 'price': m.price},
    ],
    'discount': double.tryParse(_discountController.text.trim()) ?? 0,
    'status': _selectedStatus,
    'dueDate': _dueDate,
    'notes': _clinicalNotesController.text.trim(),
  };

  @override
  void onVoiceFields(Map<String, dynamic> v) {
    String money(double p) =>
        p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
    bool listed(
      Iterable<({String name, double price})> items,
      String n,
      double p,
    ) => items.any(
      (i) => i.name.toLowerCase() == n.toLowerCase() && i.price == p,
    );
    final name = AiValue.str(v['patientName']);
    setState(() {
      if (name != null && name != _patientNameController.text.trim()) {
        _patientNameController.text = name;
        _selectedPatient = null;
        _showPatientSuggestions = false;
      }
      for (final t in AiValue.objects(v['treatments'])) {
        final n = AiValue.str(t['name']);
        final p = AiValue.number(t['price']);
        if (n == null || p == null || p <= 0) continue;
        if (listed(
          _treatments.map((e) => (name: e.name, price: e.price)),
          n,
          p,
        )) {
          continue;
        }
        _treatments.add(_TreatmentItem(name: n, qty: 1, price: p));
      }
      for (final m in AiValue.objects(v['medicines'])) {
        final n = AiValue.str(m['name']);
        final p = AiValue.number(m['price']);
        if (n == null || p == null || p <= 0) continue;
        if (listed(
          _medicines.map((e) => (name: e.name, price: e.price)),
          n,
          p,
        )) {
          continue;
        }
        _medicines.add(
          _MedicineItem(
            name: n,
            qty: 1,
            dosage: AiValue.str(m['dosage']) ?? '1 unit',
            price: p,
          ),
        );
      }
      if (AiValue.number(v['discount']) case final d? when d >= 0) {
        _discountController.text = money(d);
      }
      if (AiValue.str(v['status']) case final st? when _statuses.contains(st)) {
        _selectedStatus = st;
        if (st == 'Paid') _syncPaidAmountToTotal();
      }
      if (AiValue.date(v['dueDate']) case final d?) _dueDate = d;
      if (AiValue.str(v['notes']) case final n?) {
        _clinicalNotesController.text = n;
      }
      _treatmentError = null;
      _medicineError = null;
      _dirty = true;
      _notice = null;
    });
    if (name != null) unawaited(_matchSpokenPatient(name));
  }

  Future<void> _matchSpokenPatient(String name) async {
    try {
      final patients = await (_patients ??= _patientRepository
          .watchPatients()
          .first);
      if (!mounted) return;
      final m = matchPatient(name, patients);
      if (m.isSure && _patientNameController.text.trim() == name) {
        _pickPatient(m.best!);
      }
    } catch (_) {}
  }

  @override
  List<String> voiceMissing() => [
    if (_patientNameController.text.trim().isEmpty) 'patient',
    if (_noItems) 'a treatment or medicine with its price',
  ];

  @override
  void onVoiceConfirm() => _handleSave();

  Future<void> _handleSave() async {
    if (_isSubmitting) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    final patientName = _patientNameController.text.trim();
    if (patientName.isEmpty) return;

    if (_totals.grand <= 0 && _treatments.isEmpty && _medicines.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _notice = null;
    });

    try {
      final notes = _clinicalNotesController.text.trim();
      final manualNum =
          _manualNumber ? _invoiceNumberController.text.trim() : null;

      if (widget.onSave != null) {
        final List<String> servicesList = [];
        if (_treatments.isNotEmpty) {
          servicesList.add(
            'Treatments: ${_treatments.map((t) => t.name).join(", ")}',
          );
        }
        if (_medicines.isNotEmpty) {
          servicesList.add(
            'Medicines: ${_medicines.map((m) => m.name).join(", ")}',
          );
        }
        final serviceSummary = servicesList.isNotEmpty
            ? servicesList.join(' | ')
            : 'Consultation & Clinical Services';

        await widget.onSave!(
          patientName,
          serviceSummary,
          _totals.grand / 100.0,
          _selectedStatus,
          notes,
          _dueDate ?? _invoiceDate,
          _selectedPatient?.id,
        );

        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      final InvoiceModel savedInvoice;
      if (widget.initialInvoice != null) {
        savedInvoice = await _invoiceRepository.updateBilledInvoice(
          widget.initialInvoice!,
          patientName: patientName,
          patientId: _selectedPatient?.id,
          bill: _bill,
          date: _invoiceDate,
          dueDate: _dueDate,
          notes: notes,
          attendingDoctorUid: _attendingDoctorUid,
          invoiceNumber: manualNum,
        );
      } else {
        savedInvoice = await _invoiceRepository.createBilledInvoice(
          patientName: patientName,
          patientId: _selectedPatient?.id,
          bill: _bill,
          date: _invoiceDate,
          dueDate: _dueDate,
          notes: notes,
          attendingDoctorUid: _attendingDoctorUid,
          invoiceNumber: manualNum,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(InvoiceDialogResult(
        invoice: savedInvoice,
        patient: _selectedPatient,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _notice = e is StateError
            ? e.message
            : "Couldn't save the invoice. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _patientNameController.text.trim();
    final isEdit = widget.initialInvoice != null;

    return CruFormDialog(
      title: isEdit ? 'Edit invoice' : 'New invoice',
      subtitle: isEdit
          ? 'Update invoice details, items, or payments'
          : 'Bill a patient for treatments and medicines',
      leading: name.isEmpty
          ? const CruIconTile(
              icon: RevenueIcons.receipt,
              tone: CruTileTone.neutral,
            )
          : CruMonogram(name: name, size: CruSize.iconTile),
      submitLabel: 'Save & preview',
      onSubmit: _handleSave,
      busy: _isSubmitting,
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
              title: 'Patient',
              description: 'Who this bill is for.',
              children: [_buildPatientField()],
            ),
            CruFormSection(
              title: 'Billing',
              description: 'Invoice number, doctor, dates and payment.',
              children: [
                _buildNumberField(),
                _buildDoctorPicker(),
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
                        setState(() {
                          _selectedStatus = v;
                          if (v == 'Paid') {
                            _syncPaidAmountToTotal();
                          }
                          _edited();
                        });
                      },
                    ),
                  ),
                ),
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Amount received',
                      controller: _amountReceivedController,
                      hint: '0.00',
                      prefix: '₹',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: _moneyFormatter,
                      onChanged: (v) {
                        final rec = double.tryParse(v.trim()) ?? 0.0;
                        final total = _totals.grand / 100.0;
                        setState(() {
                          if (toPaise(rec) >= _totals.grand && total > 0) {
                            _selectedStatus = 'Paid';
                          } else {
                            _selectedStatus = 'Pending';
                          }
                          _edited();
                        });
                      },
                    ),
                    CruFieldFrame(
                      label: 'Payment mode',
                      child: Wrap(
                        spacing: CruSpace.s6,
                        runSpacing: CruSpace.s6,
                        children: [
                          for (final mode in _paymentModes)
                            CruCapsuleButton(
                              label: mode,
                              kind: _selectedPaymentMode == mode
                                  ? CruCapsuleKind.tinted
                                  : CruCapsuleKind.inset,
                              onPressed: () {
                                setState(() {
                                  _selectedPaymentMode = mode;
                                  _edited();
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
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
              children: [_buildTreatments(), _buildMedicines(), _buildTotals()],
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

  Widget _buildNumberField() {
    final c = context.cru;
    if (!_manualNumber) {
      return Padding(
        padding: const EdgeInsets.only(bottom: CruSpace.s12),
        child: Row(
          children: [
            Text(
              'Number: assigned when saved',
              style: CruType.caption.tint(c.label3),
            ),
            const SizedBox(width: CruSpace.s8),
            CruLink(
              label: 'Set number',
              style: CruType.caption.w600,
              onPressed: () {
                setState(() {
                  _manualNumber = true;
                  _edited();
                });
              },
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s12),
      child: CruTextField(
        label: 'Invoice number',
        controller: _invoiceNumberController,
        hint: 'e.g. INV-26-27/0042',
        trailing: CruLink(
          label: 'Auto',
          style: CruType.caption.w600,
          onPressed: () {
            setState(() {
              _manualNumber = false;
              _invoiceNumberController.clear();
              _edited();
            });
          },
        ),
        onChanged: _edited,
      ),
    );
  }

  Widget _buildDoctorPicker() {
    return Consumer(
      builder: (context, ref, _) {
        final doctors = ref.watch(clinicDoctorsProvider).value ?? const [];
        if (doctors.length < 2) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: CruSpace.s12),
          child: CruDropdownField<String>(
            label: 'Attending doctor',
            icon: CruIcons.user,
            value: _attendingDoctorUid ?? '',
            items: ['', for (final d in doctors) d.uid],
            itemLabel: (uid) => uid.isEmpty
                ? 'Clinic'
                : doctors
                    .firstWhere(
                      (d) => d.uid == uid,
                      orElse: () => doctors.first,
                    )
                    .name,
            onChanged: (v) => _onDoctorSelected(v, doctors),
          ),
        );
      },
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
            .where(
              (p) =>
                  p.fullName.toLowerCase().contains(_patientSearchQuery) ||
                  p.phone.contains(_patientSearchQuery),
            )
            .take(4)
            .toList();
        if (matches.isEmpty) return const SizedBox.shrink();

        final c = context.cru;
        return Container(
          margin: const EdgeInsets.only(top: CruSpace.s8),
          padding: const EdgeInsets.all(CruSpace.s4),
          decoration: ShapeDecoration(
            color: c.surface,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(color: c.hairline),
            ),
            shadows: const [],
          ),
          child: Column(
            children: [
              for (final p in matches)
                _PatientOption(patient: p, onTap: () => _pickPatient(p)),
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
            flex: [6, 2, if (_gstEnabled) 2, 2],
            cells: [
              _treatments[i].name,
              'Qty: ${_treatments[i].qty}',
              if (_gstEnabled) '${_treatments[i].taxPct}% tax',
            ],
            amount: _treatments[i].qty * _treatments[i].price,
            onRemove: () {
              _treatments.removeAt(i);
              if (_selectedStatus == 'Paid') _syncPaidAmountToTotal();
              _edited();
            },
          ),
      ],
      addRow: _AddRow(
        flex: [2, 6, if (_gstEnabled) 2, 3],
        inputs: [
          _LineInput(
            controller: _treatmentQtyController,
            hint: 'Qty',
            tabular: true,
            keyboardType: TextInputType.number,
            inputFormatters: _qtyFormatter,
            onChanged: _onTreatmentTyped,
          ),
          _LineInput(
            controller: _treatmentNameController,
            focusNode: _treatmentNameFocus,
            hint: 'Treatment or procedure',
            textCapitalization: TextCapitalization.sentences,
            onChanged: _onTreatmentTyped,
          ),
          if (_gstEnabled)
            _LineInput(
              controller: _treatmentTaxController,
              hint: 'Tax %',
              suffix: '%',
              tabular: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _moneyFormatter,
              onChanged: _onTreatmentTyped,
            ),
          _LineInput(
            controller: _treatmentPriceController,
            hint: 'Rate',
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
            flex: [5, 2, 2, if (_gstEnabled) 2, 2],
            cells: [
              _medicines[i].name,
              'Qty: ${_medicines[i].qty}',
              _medicines[i].dosage,
              if (_gstEnabled) '${_medicines[i].taxPct}% tax',
            ],
            amount: _medicines[i].qty * _medicines[i].price,
            onRemove: () {
              _medicines.removeAt(i);
              if (_selectedStatus == 'Paid') _syncPaidAmountToTotal();
              _edited();
            },
          ),
      ],
      addRow: _AddRow(
        flex: [2, 5, 2, if (_gstEnabled) 2, 3],
        inputs: [
          _LineInput(
            controller: _medicineQtyController,
            hint: 'Qty',
            tabular: true,
            keyboardType: TextInputType.number,
            inputFormatters: _qtyFormatter,
            onChanged: _onMedicineTyped,
          ),
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
          if (_gstEnabled)
            _LineInput(
              controller: _medicineTaxController,
              hint: 'Tax %',
              suffix: '%',
              tabular: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _moneyFormatter,
              onChanged: _onMedicineTyped,
            ),
          _LineInput(
            controller: _medicinePriceController,
            hint: 'Rate',
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
    final totals = _totals;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TotalLine(
                label: 'Subtotal',
                value: formatPaise(totals.subtotal),
              ),
              if (totals.tax > 0)
                _TotalLine(
                  label: 'Tax',
                  value: formatPaise(totals.tax),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Discount',
                        style: CruType.text.tint(c.label2),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _LineInput(
                        controller: _discountController,
                        hint: '0',
                        prefix: '−₹',
                        tabular: true,
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: _moneyFormatter,
                        onChanged: (v) {
                          if (_selectedStatus == 'Paid') {
                            _syncPaidAmountToTotal();
                          }
                          _edited();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (totals.roundOff != 0)
                _TotalLine(
                  label: 'Round off',
                  value: (totals.roundOff > 0 ? '+ ' : '') +
                      formatPaise(totals.roundOff),
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
                    formatPaise(totals.grand),
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
                        Text(
                          description,
                          style: CruType.caption.tint(c.label3),
                        ),
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
              shape: cruShape(
                CruRadius.control,
                side: BorderSide(color: c.hairline),
              ),
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

class _LineInput extends StatefulWidget {
  const _LineInput({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.prefix,
    this.suffix,
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
  final String? suffix;
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
          if (widget.suffix != null) ...[
            const SizedBox(width: CruSpace.s6),
            Text(widget.suffix!, style: CruType.input.w500.tint(c.label2)),
          ],
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

String _rupees(double v) => v == v.roundToDouble()
    ? DashFormat.rupees(v)
    : NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(v);
