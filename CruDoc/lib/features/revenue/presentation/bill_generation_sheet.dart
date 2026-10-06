import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/pdf/models/pdf_document_models.dart';
import 'package:doctor_management_app/core/pdf/presentation/medical_pdf_preview_screen.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Item row model for dynamic invoice billing.
class BillItemRow {
  BillItemRow({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  String description;
  int quantity;
  double unitPrice;

  double get total => quantity * unitPrice;
}

/// Rich, production-grade Bill & Receipt Generation Interface with Letterhead Branding.
class BillGenerationSheet extends StatefulWidget {
  const BillGenerationSheet({
    super.key,
    required this.letterheadConfig,
    this.initialVisit,
    this.initialPatient,
  });

  final DoctorLetterheadConfig letterheadConfig;
  final Visit? initialVisit;
  final Patient? initialPatient;

  @override
  State<BillGenerationSheet> createState() => _BillGenerationSheetState();
}

class _BillGenerationSheetState extends State<BillGenerationSheet> {
  late final TextEditingController _patientNameCtrl;
  late final TextEditingController _patientPhoneCtrl;
  late final TextEditingController _billNumberCtrl;
  late final TextEditingController _discountCtrl;
  late final TextEditingController _taxPercentCtrl;
  late final TextEditingController _paidAmountCtrl;
  late final TextEditingController _notesCtrl;

  late DateTime _billDate;
  String _selectedPaymentMode = 'UPI / Online';

  final List<BillItemRow> _items = [
    BillItemRow(
      description: 'Clinical Consultation Fee',
      quantity: 1,
      unitPrice: 500.0,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _billDate = widget.initialVisit?.scheduledStart ?? DateTime.now();
    _patientNameCtrl = TextEditingController(
      text: widget.initialPatient?.fullName ?? '',
    );
    _patientPhoneCtrl = TextEditingController(
      text: widget.initialPatient?.phone ?? '',
    );
    final invoiceSeq = DateTime.now().millisecondsSinceEpoch
        .toString()
        .substring(7);
    _billNumberCtrl = TextEditingController(text: 'INV-$invoiceSeq');
    _discountCtrl = TextEditingController(text: '0');
    _taxPercentCtrl = TextEditingController(text: '0');
    _paidAmountCtrl = TextEditingController(text: '500');
    _notesCtrl = TextEditingController(
      text: 'Thank you for choosing our clinic!',
    );
  }

  @override
  void dispose() {
    _patientNameCtrl.dispose();
    _patientPhoneCtrl.dispose();
    _billNumberCtrl.dispose();
    _discountCtrl.dispose();
    _taxPercentCtrl.dispose();
    _paidAmountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _subtotal => _items.fold(0.0, (acc, item) => acc + item.total);
  double get _discount => double.tryParse(_discountCtrl.text) ?? 0.0;
  double get _taxPercent => double.tryParse(_taxPercentCtrl.text) ?? 0.0;
  double get _taxAmount => (_subtotal - _discount > 0)
      ? (_subtotal - _discount) * (_taxPercent / 100.0)
      : 0.0;
  double get _grandTotal => (_subtotal - _discount + _taxAmount > 0)
      ? (_subtotal - _discount + _taxAmount)
      : 0.0;
  double get _paidAmount => double.tryParse(_paidAmountCtrl.text) ?? 0.0;
  double get _balanceDue =>
      (_grandTotal - _paidAmount > 0) ? (_grandTotal - _paidAmount) : 0.0;

  static const _paymentModes = [
    'UPI / Online',
    'Cash',
    'Card / POS',
    'Net Banking',
  ];

  @override
  Widget build(BuildContext context) {
    final cfg = widget.letterheadConfig;
    final c = context.cru;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: c.canvas,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      child: Column(
        children: [
          // ---- Drag Handle & Top Bar ----
          Container(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s20,
              CruSpace.s12,
              CruSpace.s16,
              CruSpace.s12,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(CruRadius.card),
              ),
              border: Border(bottom: BorderSide(color: c.separator)),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: ShapeDecoration(
                      color: c.track,
                      shape: cruShape(CruRadius.full),
                    ),
                  ),
                ),
                const SizedBox(height: CruSpace.s10),
                Row(
                  children: [
                    Container(
                      width: CruSize.iconTile,
                      height: CruSize.iconTile,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: c.inset,
                        shape: cruShape(CruRadius.iconTile),
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: c.label2,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: CruSpace.s10),
                    Expanded(
                      child: Text(
                        'Generate invoice / bill',
                        style: CruType.headline.tint(c.label),
                      ),
                    ),
                    CruIconButton(
                      icon: CruIcons.close,
                      semanticLabel: 'Close',
                      size: CruSize.control,
                      iconSize: 18,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ---- Main Bill Form & Live Letterhead Preview ----
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CruSpace.s20),
              children: [
                // ---- Letterhead Branding Banner ----
                _section(
                  c,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (cfg.logoUrl != null &&
                            cfg.logoUrl!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: CruSpace.s14,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                CruRadius.control,
                              ),
                              child: CachedNetworkImage(
                                imageUrl: cfg.logoUrl!,
                                width: 54,
                                height: 54,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => Icon(
                                  Icons.local_hospital_rounded,
                                  size: 36,
                                  color: c.label3,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 54,
                            height: 54,
                            margin: const EdgeInsets.only(right: CruSpace.s14),
                            decoration: ShapeDecoration(
                              color: c.inset,
                              shape: cruShape(CruRadius.control),
                            ),
                            child: Icon(
                              Icons.local_hospital_rounded,
                              size: 30,
                              color: c.label3,
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cfg.clinicName,
                                style: CruType.headline.tint(c.label),
                              ),
                              const SizedBox(height: CruSpace.s2),
                              Text(
                                '${cfg.doctorName} • ${cfg.qualifications}',
                                style: CruType.subhead.w600.tint(c.label2),
                              ),
                              Text(
                                '${cfg.specialty} | Reg: ${cfg.registrationNumber}',
                                style: CruType.caption.tint(c.label3),
                              ),
                              const SizedBox(height: CruSpace.s2),
                              Text(
                                '📍 ${cfg.clinicAddress} • 📞 ${cfg.clinicPhone}',
                                style: CruType.caption.tabular.tint(c.label3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s16),

                // ---- Patient & Bill Metadata ----
                _section(
                  c,
                  title: 'Invoice details & patient info',
                  children: [
                    CruFieldRow(
                      children: [
                        CruTextField(
                          label: 'Invoice #',
                          controller: _billNumberCtrl,
                          tabular: true,
                        ),
                        CruPickerField(
                          label: 'Date',
                          icon: CruIcons.calendar,
                          value: DateFormat('dd MMM yyyy').format(_billDate),
                          placeholder: 'Pick a date',
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _billDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) setState(() => _billDate = d);
                          },
                        ),
                      ],
                    ),
                    CruFieldRow(
                      children: [
                        CruTextField(
                          label: 'Patient full name',
                          controller: _patientNameCtrl,
                          icon: CruIcons.user,
                          textCapitalization: TextCapitalization.words,
                        ),
                        CruTextField(
                          label: 'WhatsApp / phone',
                          controller: _patientPhoneCtrl,
                          icon: CruIcons.phone,
                          keyboardType: TextInputType.phone,
                          tabular: true,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s16),

                // ---- Billing Line Items Table ----
                _section(
                  c,
                  title: 'Bill items & services',
                  action: CruCapsuleButton(
                    label: 'Add item',
                    icon: CruIcons.plus,
                    onPressed: _addNewItem,
                  ),
                  gap: CruSpace.s10,
                  children: [
                    for (final entry in _items.asMap().entries)
                      _buildItemRow(c, entry.key, entry.value),
                  ],
                ),
                const SizedBox(height: CruSpace.s16),

                // ---- Calculations & Payment Mode ----
                _section(
                  c,
                  title: 'Total & payment breakdown',
                  children: [
                    _buildSummaryRow(c, 'Subtotal', '₹${_subtotal.toStringAsFixed(2)}'),
                    CruFieldRow(
                      children: [
                        CruTextField(
                          label: 'Discount',
                          controller: _discountCtrl,
                          prefix: '₹',
                          keyboardType: TextInputType.number,
                          tabular: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        CruTextField(
                          label: 'Tax / GST (%)',
                          controller: _taxPercentCtrl,
                          keyboardType: TextInputType.number,
                          tabular: true,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                    const CruSeparator(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Grand total',
                          style: CruType.headline.tint(c.label),
                        ),
                        Text(
                          '₹${_grandTotal.toStringAsFixed(2)}',
                          style: CruType.title2.tabular.tint(c.label),
                        ),
                      ],
                    ),
                    CruFieldRow(
                      children: [
                        CruTextField(
                          label: 'Amount paid',
                          controller: _paidAmountCtrl,
                          prefix: '₹',
                          keyboardType: TextInputType.number,
                          tabular: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        _buildBalanceDue(c),
                      ],
                    ),
                    CruFieldFrame(
                      label: 'Payment mode',
                      child: Wrap(
                        spacing: CruSpace.s8,
                        runSpacing: CruSpace.s8,
                        children: [
                          for (final mode in _paymentModes)
                            _PaymentModeChip(
                              label: mode,
                              selected: _selectedPaymentMode == mode,
                              onTap: () =>
                                  setState(() => _selectedPaymentMode = mode),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s24),
              ],
            ),
          ),

          // ---- Bottom Action Toolbar ----
          Container(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s20,
              CruSpace.s14,
              CruSpace.s20,
              CruSpace.s24,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.separator)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: CruButton(
                    label: 'WhatsApp receipt',
                    icon: CruIcons.whatsapp,
                    kind: CruButtonKind.secondary,
                    large: true,
                    expand: true,
                    onPressed: _shareBillWhatsApp,
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: CruButton(
                    label: 'Save & print bill',
                    icon: CruIcons.fileText,
                    large: true,
                    expand: true,
                    onPressed: _generateAndSaveBill,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNewItem() {
    setState(() {
      _items.add(
        BillItemRow(
          description: 'Pharmacy / Procedure',
          quantity: 1,
          unitPrice: 200.0,
        ),
      );
    });
  }

  /// A surface card (radius 24) with an optional title row.
  Widget _section(
    CruColors c, {
    String? title,
    Widget? action,
    double gap = CruSpace.s16,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.card, side: BorderSide(color: c.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(title, style: CruType.callout.tint(c.label)),
                ),
                ?action,
              ],
            ),
            SizedBox(height: gap),
          ],
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      ),
    );
  }

  /// One line item: an inset row (radius 12) of borderless fields.
  Widget _buildItemRow(CruColors c, int idx, BillItemRow item) {
    final input = CruType.input.tint(c.label);
    InputDecoration cell(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      filled: false,
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
    );
    return Container(
      key: ObjectKey(item),
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s8,
        CruSpace.s4,
        CruSpace.s8,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: item.description,
              style: input,
              decoration: cell('Service / procedure'),
              onChanged: (v) => setState(() => item.description = v),
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          Expanded(
            flex: 1,
            child: TextFormField(
              initialValue: item.quantity.toString(),
              keyboardType: TextInputType.number,
              style: input.tabular,
              decoration: cell('Qty'),
              onChanged: (v) =>
                  setState(() => item.quantity = int.tryParse(v) ?? 1),
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: item.unitPrice.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              style: input.tabular,
              decoration: cell('Rate (₹)'),
              onChanged: (v) =>
                  setState(() => item.unitPrice = double.tryParse(v) ?? 0.0),
            ),
          ),
          Text(
            '₹${item.total.toStringAsFixed(0)}',
            style: CruType.subhead.w600.tabular.tint(c.label),
          ),
          if (_items.length > 1)
            IconButton(
              tooltip: 'Remove item',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: c.label3,
                size: 18,
              ),
              onPressed: () => setState(() => _items.removeAt(idx)),
            )
          else
            const SizedBox(width: CruSpace.s8),
        ],
      ),
    );
  }

  /// Amber while money is outstanding (waiting), green once settled.
  Widget _buildBalanceDue(CruColors c) {
    final due = _balanceDue > 0;
    return CruFieldFrame(
      label: 'Balance due',
      child: Container(
        height: CruSize.actionButton,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
        alignment: Alignment.centerLeft,
        decoration: ShapeDecoration(
          color: due ? c.amberTint : c.greenTint,
          shape: cruShape(CruRadius.control),
        ),
        child: Text(
          '₹${_balanceDue.toStringAsFixed(2)}',
          style: CruType.input.w600.tabular.tint(
            due ? c.amberText : c.greenText,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildSummaryRow(CruColors c, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: CruType.subhead.tint(c.label2)),
        Text(value, style: CruType.subhead.w600.tabular.tint(c.label)),
      ],
    );
  }

  Future<void> _generateAndSaveBill() async {
    final documentData = PdfInvoiceDocumentData(
      letterheadConfig: widget.letterheadConfig,
      patient: _buildPatientSnapshot(),
      documentNumber: _billNumberCtrl.text.trim().isEmpty
          ? 'INV-${DateTime.now().millisecondsSinceEpoch}'
          : _billNumberCtrl.text.trim(),
      documentDate: _billDate,
      items: _items
          .map(
            (item) => PdfInvoiceLineItem(
              description: item.description.trim(),
              quantity: item.quantity <= 0 ? 1 : item.quantity,
              unitPrice: item.unitPrice < 0 ? 0 : item.unitPrice,
            ),
          )
          .toList(),
      totals: PdfMoneyTotals(
        subtotal: _subtotal,
        discountAmount: _discount,
        taxPercent: _taxPercent,
        taxAmount: _taxAmount,
        grandTotal: _grandTotal,
        paidAmount: _paidAmount,
        balanceDue: _balanceDue,
        paymentMode: _selectedPaymentMode,
      ),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    await MedicalPdfPreviewScreen.open(context, documentData: documentData);
  }

  PdfPatientSnapshot _buildPatientSnapshot() {
    final patient = widget.initialPatient;
    final typedAgeGender = patient == null
        ? null
        : '${patient.age} Y / ${patient.gender.trim().isEmpty ? 'N/A' : patient.gender.trim()}';

    return PdfPatientSnapshot(
      fullName: _patientNameCtrl.text.trim().isEmpty
          ? (patient?.fullName.trim().isNotEmpty == true
                ? patient!.fullName
                : 'Patient')
          : _patientNameCtrl.text.trim(),
      phone: _patientPhoneCtrl.text.trim().isEmpty
          ? (patient?.phone.trim().isEmpty == true
                ? null
                : patient?.phone.trim())
          : _patientPhoneCtrl.text.trim(),
      ageGender: typedAgeGender,
      email: patient?.email.trim().isEmpty == true
          ? null
          : patient?.email.trim(),
      patientId: patient?.id.trim().isEmpty == true ? null : patient?.id.trim(),
    );
  }

  Future<void> _shareBillWhatsApp() async {
    final phone = _patientPhoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final patientName = _patientNameCtrl.text.isNotEmpty
        ? _patientNameCtrl.text
        : 'Patient';

    final text =
        '''
🏥 *${widget.letterheadConfig.clinicName}*
🧾 *Medical Invoice / Bill Receipt*

Patient: *$patientName*
Invoice No: *${_billNumberCtrl.text}*
Date: *${DateFormat('dd MMM yyyy').format(_billDate)}*
Doctor: *${widget.letterheadConfig.doctorName}*

*Total Amount:* ₹${_grandTotal.toStringAsFixed(2)}
*Amount Paid:* ₹${_paidAmount.toStringAsFixed(2)} (${_selectedPaymentMode})
*Balance Due:* ₹${_balanceDue.toStringAsFixed(2)}

Thank you for visiting! Contact: ${widget.letterheadConfig.clinicPhone}
''';

    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(text)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

/// A payment-mode choice: inset at rest, accent tint when selected (the
/// patients filter-chip pattern).
class _PaymentModeChip extends StatelessWidget {
  const _PaymentModeChip({
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
          height: CruSize.filterChip,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected
                ? c.accentTint
                : (hovered ? cruHoverShade(c.inset, c) : c.inset),
            shape: const StadiumBorder(),
          ),
          child: Text(
            label,
            style: (selected ? CruType.chip.w600 : CruType.chip).tint(
              selected ? c.accentText : c.label,
            ),
          ),
        ),
      ),
    );
  }
}
