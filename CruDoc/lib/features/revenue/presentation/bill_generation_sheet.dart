import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/pdf/models/pdf_document_models.dart';
import 'package:doctor_management_app/core/pdf/presentation/medical_pdf_preview_screen.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

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
    BillItemRow(description: 'Clinical Consultation Fee', quantity: 1, unitPrice: 500.0),
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
    final invoiceSeq = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    _billNumberCtrl = TextEditingController(text: 'INV-$invoiceSeq');
    _discountCtrl = TextEditingController(text: '0');
    _taxPercentCtrl = TextEditingController(text: '0');
    _paidAmountCtrl = TextEditingController(text: '500');
    _notesCtrl = TextEditingController(text: 'Thank you for choosing our clinic!');
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
  double get _taxAmount => (_subtotal - _discount > 0) ? (_subtotal - _discount) * (_taxPercent / 100.0) : 0.0;
  double get _grandTotal => (_subtotal - _discount + _taxAmount > 0) ? (_subtotal - _discount + _taxAmount) : 0.0;
  double get _paidAmount => double.tryParse(_paidAmountCtrl.text) ?? 0.0;
  double get _balanceDue => (_grandTotal - _paidAmount > 0) ? (_grandTotal - _paidAmount) : 0.0;

  @override
  Widget build(BuildContext context) {
    final cfg = widget.letterheadConfig;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ---- Drag Handle & Top Bar ----
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF0D9488), size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Generate Invoice / Bill',
                          style: TextStyle(
                            fontFamily: AppColors.headingFontFamily,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
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
              padding: const EdgeInsets.all(20),
              children: [
                // ---- Letterhead Branding Banner ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 3)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (cfg.logoUrl != null && cfg.logoUrl!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  imageUrl: cfg.logoUrl!,
                                  width: 54,
                                  height: 54,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Icon(Icons.local_hospital_rounded, size: 36, color: Color(0xFF1E78FF)),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 54,
                              height: 54,
                              margin: const EdgeInsets.only(right: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E78FF).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.local_hospital_rounded, size: 30, color: Color(0xFF1E78FF)),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cfg.clinicName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${cfg.doctorName} • ${cfg.qualifications}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E78FF),
                                  ),
                                ),
                                Text(
                                  '${cfg.specialty} | Reg: ${cfg.registrationNumber}',
                                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '📍 ${cfg.clinicAddress} • 📞 ${cfg.clinicPhone}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        height: 2,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1E78FF), Color(0xFF0D9488)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Patient & Bill Metadata ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Invoice Details & Patient Info',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(_billNumberCtrl, 'Invoice #', Icons.tag_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _billDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (d != null) setState(() => _billDate = d);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF0D9488)),
                                    const SizedBox(width: 8),
                                    Text(
                                      DateFormat('dd MMM yyyy').format(_billDate),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(_patientNameCtrl, 'Patient Full Name', Icons.person_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInput(_patientPhoneCtrl, 'WhatsApp / Phone', Icons.phone_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Billing Line Items Table ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Bill Items & Services',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF334155)),
                          ),
                          TextButton.icon(
                            onPressed: _addNewItem,
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 16, color: Color(0xFF0D9488)),
                            label: const Text('Add Item', style: TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.w700, fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._items.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  initialValue: item.description,
                                  decoration: const InputDecoration(
                                    labelText: 'Service / Procedure',
                                    isDense: true,
                                    border: InputBorder.none,
                                  ),
                                  onChanged: (v) => setState(() => item.description = v),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  initialValue: item.quantity.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Qty',
                                    isDense: true,
                                    border: InputBorder.none,
                                  ),
                                  onChanged: (v) => setState(() => item.quantity = int.tryParse(v) ?? 1),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: item.unitPrice.toStringAsFixed(0),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Rate (₹)',
                                    isDense: true,
                                    border: InputBorder.none,
                                  ),
                                  onChanged: (v) => setState(() => item.unitPrice = double.tryParse(v) ?? 0.0),
                                ),
                              ),
                              Text(
                                '₹${item.total.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              if (_items.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                  onPressed: () => setState(() => _items.removeAt(idx)),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Calculations & Payment Mode ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total & Payment Breakdown',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 12),
                      _buildSummaryRow('Subtotal', '₹${_subtotal.toStringAsFixed(2)}'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(_discountCtrl, 'Discount (₹)', Icons.discount_rounded, isNumber: true, onChanged: (_) => setState(() {})),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInput(_taxPercentCtrl, 'Tax / GST (%)', Icons.percent_rounded, isNumber: true, onChanged: (_) => setState(() {})),
                          ),
                        ],
                      ),
                      const Divider(height: 24, color: Color(0xFFE2E8F0)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Grand Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                          Text('₹${_grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0D9488))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(_paidAmountCtrl, 'Amount Paid (₹)', Icons.payments_rounded, isNumber: true, onChanged: (_) => setState(() {})),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _balanceDue > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _balanceDue > 0 ? const Color(0xFFFCA5A5) : const Color(0xFFBBF7D0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Balance Due', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  Text('₹${_balanceDue.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _balanceDue > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Payment Mode selector
                      const Text('Payment Mode', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['UPI / Online', 'Cash', 'Card / POS', 'Net Banking'].map((mode) {
                          final isSelected = _selectedPaymentMode == mode;
                          return ChoiceChip(
                            label: Text(mode, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? Colors.white : const Color(0xFF334155))),
                            selected: isSelected,
                            selectedColor: const Color(0xFF0D9488),
                            backgroundColor: const Color(0xFFF1F5F9),
                            onSelected: (_) => setState(() => _selectedPaymentMode = mode),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // ---- Bottom Action Toolbar ----
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareBillWhatsApp,
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('WhatsApp Receipt'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF16A34A),
                      side: const BorderSide(color: Color(0xFF86EFAC)),
                      backgroundColor: const Color(0xFFF0FDF4),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _generateAndSaveBill,
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text('Save & Print Bill'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
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
      _items.add(BillItemRow(description: 'Pharmacy / Procedure', quantity: 1, unitPrice: 200.0));
    });
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
      ],
    );
  }

  Widget _buildInput(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool isNumber = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 16, color: const Color(0xFF0D9488)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
        ),
      ),
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
          ? (patient?.fullName.trim().isNotEmpty == true ? patient!.fullName : 'Patient')
          : _patientNameCtrl.text.trim(),
      phone: _patientPhoneCtrl.text.trim().isEmpty
          ? (patient?.phone.trim().isEmpty == true ? null : patient?.phone.trim())
          : _patientPhoneCtrl.text.trim(),
      ageGender: typedAgeGender,
      email: patient?.email.trim().isEmpty == true ? null : patient?.email.trim(),
      patientId: patient?.id.trim().isEmpty == true ? null : patient?.id.trim(),
    );
  }

  Future<void> _shareBillWhatsApp() async {
    final phone = _patientPhoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final patientName = _patientNameCtrl.text.isNotEmpty ? _patientNameCtrl.text : 'Patient';

    final text = '''
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

    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
