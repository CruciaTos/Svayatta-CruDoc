import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:crudoc_shared/theme/cru_colors.dart';

/// Checkout for a month of paid modules, paid by UPI on CruDoc's own payment
/// gateway.
///
/// Opens the gateway's payment page (QR code and UPI app links) and follows
/// `plan_payments/{orderId}`, which only the server writes. Features unlock
/// when the bank confirms the payment, not when this sheet says so; closing
/// the sheet early loses nothing.
///
/// Pops `true` once the plan is active.
class PaymentCheckoutSheet extends StatefulWidget {
  final List<String> selectedModules;

  /// What the upgrade screen showed. The server's price is the one charged
  /// and replaces this once the checkout opens.
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

  static const _green = Color(0xFF16A34A);

  bool _opening = false;
  bool _cancelling = false;
  PlanCheckout? _checkout;
  PlanPayment? _payment;
  StreamSubscription<PlanPayment>? _watch;

  final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  double get _amountInr => _checkout != null
      ? _checkout!.amountPaise / 100
      : widget.totalAmount;

  PlanPaymentStatus? get _status =>
      _payment?.status ?? (_checkout != null ? PlanPaymentStatus.pending : null);

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _startCheckout() async {
    setState(() => _opening = true);
    try {
      final checkout = await _subscriptionService.startPlanCheckout(
        widget.selectedModules,
      );
      if (!mounted) return;
      _watch?.cancel();
      _watch = _subscriptionService
          .watchPlanPayment(checkout.orderId)
          .listen(_onPayment);
      setState(() {
        _checkout = checkout;
        _payment = null;
        _opening = false;
      });
      await _openPaymentPage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      _showError(e is StateError ? e.message : '$e');
    }
  }

  void _onPayment(PlanPayment payment) {
    if (!mounted) return;
    final wasPaid = _payment?.status == PlanPaymentStatus.paid;
    setState(() => _payment = payment);
    if (payment.status == PlanPaymentStatus.paid && !wasPaid) {
      _subscriptionService.stampPaidMonth();
    }
  }

  Future<void> _openPaymentPage() async {
    final url = _checkout?.checkoutUrl;
    if (url == null) return;
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showError('Could not open the payment page. Check your browser.');
    }
  }

  Future<void> _cancel() async {
    final orderId = _checkout?.orderId;
    if (orderId == null) return;
    setState(() => _cancelling = true);
    try {
      await _subscriptionService.cancelPlanCheckout(orderId);
    } catch (e) {
      if (mounted) _showError(e is StateError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _tryAgain() {
    _watch?.cancel();
    setState(() {
      _checkout = null;
      _payment = null;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  String _getModuleTitle(String moduleKey) {
    for (final item in DoctorSubscriptionService.availableFeatures) {
      if (item.moduleKey == moduleKey) return item.title;
    }
    return moduleKey;
  }

  double? _getModulePrice(String moduleKey) {
    for (final item in DoctorSubscriptionService.availableFeatures) {
      if (item.moduleKey == moduleKey) return item.monthlyPriceInr;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: _c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: status == PlanPaymentStatus.paid
          ? _buildSuccessReceipt()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHandle(),
                _buildHeader(),
                Divider(height: 1, color: _c.separator),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      _buildOrderSummaryBox(),
                      const SizedBox(height: 16),
                      _buildStatusPanel(status),
                    ],
                  ),
                ),
                _buildActionBar(status),
              ],
            ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(
          color: _c.separator,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.qr_code_2_rounded, color: _green, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pay by UPI',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _c.label,
                    fontFamily: AppColors.headingFontFamily,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Google Pay, PhonePe, Paytm, BHIM or any UPI app',
                  style: TextStyle(fontSize: 12, color: _c.label2),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _opening ? null : () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: _c.label2),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummaryBox() {
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
                  color: _green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '30 DAYS PLAN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...widget.selectedModules.map((modKey) {
            final price = _getModulePrice(modKey);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: _green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getModuleTitle(modKey),
                      style: TextStyle(fontSize: 12.5, color: _c.label),
                    ),
                  ),
                  if (price != null)
                    Text(
                      _currency.format(price),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _c.label2,
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
                _currency.format(_amountInr),
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

  /// What is happening now, in a sentence or two.
  Widget _buildStatusPanel(PlanPaymentStatus? status) {
    final (IconData icon, Color tone, String title, String body) = switch (status) {
      null => (
        Icons.lock_outline_rounded,
        _c.accent,
        'How it works',
        'We open CruDoc\'s secure payment page. Scan the QR code or pick your '
            'UPI app there, and pay. Your features switch on by themselves as '
            'soon as your bank confirms, usually within a minute.',
      ),
      PlanPaymentStatus.starting || PlanPaymentStatus.pending => (
        Icons.hourglass_top_rounded,
        _c.accent,
        'Waiting for your payment',
        [
          if ((_checkout?.queuePosition ?? 0) > 0)
            'Someone else is paying right now. You\'re number '
                '${_checkout!.queuePosition} in line on the payment page.',
          'Finish paying on the payment page. This updates by itself once '
              'your bank confirms. You can close it; your features still '
              'switch on.',
        ].join('\n\n'),
      ),
      PlanPaymentStatus.expired => (
        Icons.timer_off_rounded,
        Colors.orange,
        'The payment page timed out',
        'Nothing was charged. If money did leave your account, it will be '
            'matched and your features switched on; otherwise try again.',
      ),
      PlanPaymentStatus.failed => (
        Icons.error_outline_rounded,
        Colors.redAccent,
        'We couldn\'t confirm a payment',
        'If money left your account, contact CruDoc support with your UPI '
            'reference number and we\'ll sort it out.',
      ),
      PlanPaymentStatus.cancelled => (
        Icons.cancel_outlined,
        _c.label2,
        'Payment cancelled',
        'If you had already paid, your features will still switch on.',
      ),
      PlanPaymentStatus.review => (
        Icons.manage_search_rounded,
        Colors.orange,
        'We\'re checking your payment',
        'A payment arrived that we need to check by hand before switching your '
            'features on. This usually takes under a working day. Your '
            'reference: ${_checkout?.orderId ?? _payment?.orderId ?? ''}',
      ),
      PlanPaymentStatus.paid => (Icons.check_rounded, _green, '', ''),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tone),
          const SizedBox(width: 10),
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
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: _c.label2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(PlanPaymentStatus? status) {
    final List<Widget> buttons = switch (status) {
      null => [
        _primaryButton(
          label: _opening
              ? 'Opening payment page...'
              : 'Pay ${_currency.format(_amountInr)} by UPI',
          icon: Icons.lock_rounded,
          busy: _opening,
          onPressed: _opening ? null : _startCheckout,
        ),
      ],
      PlanPaymentStatus.starting || PlanPaymentStatus.pending => [
        _primaryButton(
          label: 'Open payment page again',
          icon: Icons.open_in_new_rounded,
          onPressed: _openPaymentPage,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _cancelling ? null : _cancel,
          child: Text(
            _cancelling ? 'Cancelling...' : 'Cancel payment',
            style: TextStyle(color: _c.label2),
          ),
        ),
      ],
      PlanPaymentStatus.expired ||
      PlanPaymentStatus.failed ||
      PlanPaymentStatus.cancelled => [
        _primaryButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: _tryAgain,
        ),
      ],
      PlanPaymentStatus.review || PlanPaymentStatus.paid => [
        _primaryButton(
          label: 'Close',
          icon: Icons.check_rounded,
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: BoxDecoration(
        color: _c.surface,
        border: Border(top: BorderSide(color: _c.separator)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: buttons),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool busy = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E78FF),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildSuccessReceipt() {
    final payment = _payment;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
              color: _green,
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
            'Your bank confirmed the payment. Your selected modules are now active.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: _c.label2),
          ),
          const SizedBox(height: 20),
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
                  _currency.format((payment?.amountPaise ?? 0) / 100),
                  isBold: true,
                ),
                const SizedBox(height: 6),
                _buildReceiptRow('UPI Reference (UTR):', payment?.utr ?? '—'),
                const SizedBox(height: 6),
                _buildReceiptRow(
                  'Transaction ID:',
                  payment?.transactionId ?? '—',
                ),
                const SizedBox(height: 6),
                _buildReceiptRow(
                  'Activated Features:',
                  '${widget.selectedModules.length} Modules',
                ),
                const SizedBox(height: 6),
                _buildReceiptRow(
                  'Plan Valid Until:',
                  payment?.validUntil != null
                      ? DateFormat('dd MMM yyyy').format(payment!.validUntil!)
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
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
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
        Text(label, style: TextStyle(fontSize: 12, color: _c.label2)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: isBold ? _c.label : _c.label2,
            ),
          ),
        ),
      ],
    );
  }
}
