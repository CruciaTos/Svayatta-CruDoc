import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:crudoc_shared/theme/cru_colors.dart';

/// Interactive in-app checkout modal that processes doctor payment and
/// immediately unlocks and activates the selected features for 1 month (30 days).
class PaymentCheckoutSheet extends StatefulWidget {
  final List<String> selectedModules;
  final double totalAmount;

  const PaymentCheckoutSheet({
    super.key,
    required this.selectedModules,
    required this.totalAmount,
  });

  static Future<bool?> show(
    BuildContext context, {
    required List<String> selectedModules,
    required double totalAmount,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentCheckoutSheet(
        selectedModules: selectedModules,
        totalAmount: totalAmount,
      ),
    );
  }

  @override
  State<PaymentCheckoutSheet> createState() => _PaymentCheckoutSheetState();
}

class _PaymentCheckoutSheetState extends State<PaymentCheckoutSheet> {
  final DoctorSubscriptionService _subscriptionService =
      DoctorSubscriptionService();

  CruColors get _c =>
      Theme.of(context).extension<CruColors>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? CruColors.evening
          : CruColors.day);

  String _selectedMethod = 'upi'; // 'upi', 'card', 'netbanking'
  String _selectedUpiApp = 'gpay'; // 'gpay', 'phonepe', 'paytm', 'bhim'
  final TextEditingController _upiIdController = TextEditingController(
    text: 'doctor@okaxis',
  );
  final TextEditingController _cardNumberController = TextEditingController(
    text: '4532 •••• •••• 8821',
  );

  bool _isProcessing = false;
  bool _isSuccess = false;
  String? _transactionId;
  DateTime? _newExpiryDate;

  Future<void> _handlePayment() async {
    setState(() => _isProcessing = true);

    // Realistic payment processing delay
    await Future.delayed(const Duration(seconds: 2));

    try {
      final methodLabel = _selectedMethod == 'upi'
          ? 'UPI (${_selectedUpiApp.toUpperCase()})'
          : (_selectedMethod == 'card' ? 'Credit/Debit Card' : 'Net Banking');

      final result = await _subscriptionService
          .processPaymentAndActivateFeatures(
            selectedModules: widget.selectedModules,
            amountPaid: widget.totalAmount,
            paymentMethod: methodLabel,
            transactionReference: _selectedMethod == 'upi'
                ? _upiIdController.text.trim()
                : 'CARD_PAYMENT',
          );

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isSuccess = true;
          _transactionId = result.transactionId;
          _newExpiryDate = result.newExpiryDate;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment activation failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _getModuleTitle(String moduleKey) {
    for (final item in DoctorSubscriptionService.availableFeatures) {
      if (item.moduleKey == moduleKey) return item.title;
    }
    return moduleKey;
  }

  @override
  void dispose() {
    _upiIdController.dispose();
    _cardNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: _c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: _isSuccess
          ? _buildSuccessReceipt(currencyFormatter)
          : Column(
              children: [
                // Top drag handle
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: _c.separator,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.lock_open_rounded,
                          color: Color(0xFF16A34A),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Secure Checkout & Activation',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: _c.label,
                                fontFamily: AppColors.headingFontFamily,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Instant 1-month clinical feature activation',
                              style: TextStyle(
                                fontSize: 12,
                                color: _c.label2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _isProcessing
                            ? null
                            : () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close_rounded,
                          color: _c.label2,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: _c.separator),

                // Body content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: [
                      // Order Summary Box
                      _buildOrderSummaryBox(currencyFormatter),
                      const SizedBox(height: 20),

                      Text(
                        'SELECT PAYMENT METHOD',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: _c.label2,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Method 1: UPI Fast Pay
                      _buildPaymentOption(
                        id: 'upi',
                        title: 'UPI Fast Pay',
                        subtitle: 'Google Pay, PhonePe, Paytm, BHIM',
                        icon: Icons.qr_code_2_rounded,
                        child: _buildUpiSection(),
                      ),
                      const SizedBox(height: 10),

                      // Method 2: Cards
                      _buildPaymentOption(
                        id: 'card',
                        title: 'Credit / Debit Card',
                        subtitle: 'Visa, MasterCard, RuPay',
                        icon: Icons.credit_card_rounded,
                        child: _buildCardSection(),
                      ),
                      const SizedBox(height: 10),

                      // Method 3: Net Banking
                      _buildPaymentOption(
                        id: 'netbanking',
                        title: 'Net Banking',
                        subtitle: 'HDFC, ICICI, SBI, Axis, Kotak',
                        icon: Icons.account_balance_rounded,
                        child: const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 16),

                      // Trust & Security Badge
                      _buildSecurityBadge(),
                    ],
                  ),
                ),

                // Pay Button Bar
                _buildPayButtonBar(currencyFormatter),
              ],
            ),
    );
  }

  Widget _buildOrderSummaryBox(NumberFormat currencyFormatter) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _c.inset,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _c.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order Summary',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _c.label,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '30 DAYS PLAN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...widget.selectedModules.map((modKey) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getModuleTitle(modKey),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _c.label,
                      ),
                    ),
                  ),
                  Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _c.accent,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          Divider(height: 1, color: _c.separator),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Payable Amount:',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _c.label,
                ),
              ),
              Text(
                currencyFormatter.format(widget.totalAmount),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _c.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    final isSelected = _selectedMethod == id;

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? _c.accent.withValues(alpha: 0.1) : _c.inset,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? _c.accent : _c.separator,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _selectedMethod = id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _c.accent
                          : _c.separator.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: isSelected ? _c.onAccent : _c.label2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _c.label,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: _c.label2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Radio<String>(
                    value: id,
                    groupValue: _selectedMethod,
                    onChanged: (val) => setState(() => _selectedMethod = val!),
                    activeColor: _c.accent,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          if (isSelected) child,
        ],
      ),
    );
  }

  Widget _buildUpiSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: _c.separator),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildUpiAppPill('gpay', 'Google Pay'),
              _buildUpiAppPill('phonepe', 'PhonePe'),
              _buildUpiAppPill('paytm', 'Paytm'),
              _buildUpiAppPill('bhim', 'BHIM UPI'),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _upiIdController,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'UPI ID / VPA',
              hintText: 'e.g. yourname@oksbi',
              labelStyle: TextStyle(color: _c.label2),
              hintStyle: TextStyle(color: _c.label2),
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 18, color: _c.label2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _c.separator),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _c.separator),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _c.accent, width: 1.5),
              ),
              filled: true,
              fillColor: _c.surface,
            ),
            style: TextStyle(fontSize: 13, color: _c.label),
          ),
        ],
      ),
    );
  }

  Widget _buildUpiAppPill(String id, String label) {
    final isSelected = _selectedUpiApp == id;
    return InkWell(
      onTap: () => setState(() => _selectedUpiApp = id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _c.accent : _c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? _c.accent : _c.separator,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isSelected ? _c.onAccent : _c.label,
          ),
        ),
      ),
    );
  }

  Widget _buildCardSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        children: [
          Divider(height: 1, color: _c.separator),
          const SizedBox(height: 10),
          TextField(
            controller: _cardNumberController,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Card Number',
              labelStyle: TextStyle(color: _c.label2),
              prefixIcon: Icon(Icons.credit_card, size: 18, color: _c.label2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _c.separator),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _c.separator),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _c.accent, width: 1.5),
              ),
              filled: true,
              fillColor: _c.surface,
            ),
            style: TextStyle(fontSize: 13, color: _c.label),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'MM / YY',
                    labelStyle: TextStyle(color: _c.label2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _c.separator),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _c.separator),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _c.accent, width: 1.5),
                    ),
                    filled: true,
                    fillColor: _c.surface,
                  ),
                  style: TextStyle(fontSize: 13, color: _c.label),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'CVV',
                    labelStyle: TextStyle(color: _c.label2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _c.separator),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _c.separator),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _c.accent, width: 1.5),
                    ),
                    filled: true,
                    fillColor: _c.surface,
                  ),
                  obscureText: true,
                  style: TextStyle(fontSize: 13, color: _c.label),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _c.inset,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield_rounded, size: 16, color: Color(0xFF16A34A)),
          const SizedBox(width: 8),
          Text(
            '256-Bit Encrypted Healthcare Payment Gateway',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _c.label2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayButtonBar(NumberFormat currencyFormatter) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: BoxDecoration(
        color: _c.surface,
        border: Border(top: BorderSide(color: _c.separator)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _handlePayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E78FF),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_rounded, size: 18),
            label: Text(
              _isProcessing
                  ? 'Processing Payment & Unlocking Features...'
                  : 'Pay ${currencyFormatter.format(widget.totalAmount)} & Activate Now',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessReceipt(NumberFormat currencyFormatter) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF16A34A),
              size: 48,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Payment Successful!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _c.label,
              fontFamily: AppColors.headingFontFamily,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your selected clinical modules are now unlocked and active.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: _c.label2),
          ),
          const SizedBox(height: 20),

          // Receipt Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _c.inset,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _c.separator),
            ),
            child: Column(
              children: [
                _buildReceiptRow(
                  'Amount Paid:',
                  currencyFormatter.format(widget.totalAmount),
                  isBold: true,
                ),
                const SizedBox(height: 6),
                _buildReceiptRow('Transaction ID:', _transactionId ?? '—'),
                const SizedBox(height: 6),
                _buildReceiptRow(
                  'Activated Features:',
                  '${widget.selectedModules.length} Modules',
                ),
                const SizedBox(height: 6),
                _buildReceiptRow(
                  'Plan Valid Until:',
                  _newExpiryDate != null
                      ? DateFormat('dd MMM yyyy').format(_newExpiryDate!)
                      : '30 Days',
                  isBold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context, true); // Close checkout
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.rocket_launch_rounded, size: 18),
              label: const Text(
                'Start Using Unlocked Features',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: _c.label2),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: isBold ? _c.label : _c.label2,
          ),
        ),
      ],
    );
  }
}
