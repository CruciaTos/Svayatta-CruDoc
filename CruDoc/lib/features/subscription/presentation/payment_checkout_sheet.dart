import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

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
      SnackBar(content: Text(message)),
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
    final c = context.cru;
    final status = _status;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      child: status == PlanPaymentStatus.paid
          ? _receipt(c)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _handle(c),
                _header(c),
                Divider(height: 1, color: c.separator),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(
                      CruSpace.s20,
                      CruSpace.s16,
                      CruSpace.s20,
                      CruSpace.s24,
                    ),
                    children: [
                      _orderSummary(c),
                      const SizedBox(height: CruSpace.s16),
                      _statusPanel(c, status),
                    ],
                  ),
                ),
                _actionBar(c, status),
              ],
            ),
    );
  }

  Widget _handle(CruColors c) => Center(
    child: Container(
      width: CruSpace.s32 + CruSpace.s12,
      height: CruSpace.s4,
      margin: const EdgeInsets.only(top: CruSpace.s12, bottom: CruSpace.s8),
      decoration: BoxDecoration(
        color: c.track,
        borderRadius: BorderRadius.circular(CruRadius.full),
      ),
    ),
  );

  Widget _header(CruColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s8,
        CruSpace.s20,
        CruSpace.s12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pay by UPI', style: CruType.title2.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(
                  'Google Pay, PhonePe, Paytm, BHIM or any UPI app',
                  style: CruType.caption.tint(c.label2),
                ),
              ],
            ),
          ),
          CruIconButton(
            icon: CruIcons.close,
            onPressed: _opening ? null : () => Navigator.pop(context),
            semanticLabel: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _orderSummary(CruColors c) {
    return Container(
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CruRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your order', style: CruType.callout.w600.tint(c.label)),
              ),
              CruPill(text: '30 days', background: c.track, foreground: c.label2),
            ],
          ),
          const SizedBox(height: CruSpace.s10),
          for (final key in widget.selectedModules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _getModuleTitle(key),
                      style: CruType.text.tint(c.label),
                    ),
                  ),
                  if (_getModulePrice(key) case final price?)
                    Text(
                      _currency.format(price),
                      style: CruType.caption.tabular.tint(c.label2),
                    ),
                ],
              ),
            ),
          const SizedBox(height: CruSpace.s12),
          Divider(height: 1, color: c.separator),
          const SizedBox(height: CruSpace.s10),
          Row(
            children: [
              Expanded(
                child: Text('Total', style: CruType.callout.w600.tint(c.label)),
              ),
              Text(
                _currency.format(_amountInr),
                style: CruType.amount.tabular.tint(c.label),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// What is happening now, in a sentence or two. Amber while we wait on
  /// the bank or a manual check; everything else stays neutral.
  Widget _statusPanel(CruColors c, PlanPaymentStatus? status) {
    final (CruIconData icon, bool waiting, String title, String body) =
        switch (status) {
          null => (
            CruIcons.wallet,
            false,
            'How it works',
            "We open CruDoc's secure payment page. Scan the QR code or pick "
                'your UPI app there, and pay. Your features switch on by '
                'themselves as soon as your bank confirms, usually within a '
                'minute.',
          ),
          PlanPaymentStatus.starting || PlanPaymentStatus.pending => (
            CruIcons.clock,
            true,
            'Waiting for your payment',
            [
              if ((_checkout?.queuePosition ?? 0) > 0)
                "Someone else is paying right now. You're number "
                    '${_checkout!.queuePosition} in line on the payment page.',
              'Finish paying on the payment page. This updates by itself once '
                  'your bank confirms. You can close it; your features still '
                  'switch on.',
            ].join('\n\n'),
          ),
          PlanPaymentStatus.expired => (
            CruIcons.clock,
            false,
            'The payment page timed out',
            'Nothing was charged. If money did leave your account, it will be '
                'matched and your features switched on; otherwise try again.',
          ),
          PlanPaymentStatus.failed => (
            CruIcons.warning,
            false,
            "We couldn't confirm a payment",
            'If money left your account, contact CruDoc support with your UPI '
                "reference number and we'll sort it out.",
          ),
          PlanPaymentStatus.cancelled => (
            CruIcons.close,
            false,
            'Payment cancelled',
            'If you had already paid, your features will still switch on.',
          ),
          PlanPaymentStatus.review => (
            CruIcons.search,
            true,
            "We're checking your payment",
            'A payment arrived that we need to check by hand before switching '
                'your features on. This usually takes under a working day. '
                'Your reference: '
                '${_checkout?.orderId ?? _payment?.orderId ?? ''}',
          ),
          PlanPaymentStatus.paid => (CruIcons.check, false, '', ''),
        };

    return Container(
      padding: const EdgeInsets.all(CruSpace.s14),
      decoration: BoxDecoration(
        color: waiting ? c.amberTint : c.inset,
        borderRadius: BorderRadius.circular(CruRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CruIcon(icon, color: waiting ? c.amberText : c.label2),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: CruType.callout.w600.tint(
                    waiting ? c.amberText : c.label,
                  ),
                ),
                const SizedBox(height: CruSpace.s4),
                Text(body, style: CruType.caption.tint(c.label2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar(CruColors c, PlanPaymentStatus? status) {
    final List<Widget> buttons = switch (status) {
      null => [
        CruButton(
          label: _opening
              ? 'Opening the payment page…'
              : 'Pay ${_currency.format(_amountInr)} by UPI',
          expand: true,
          large: true,
          onPressed: _opening ? null : _startCheckout,
        ),
      ],
      PlanPaymentStatus.starting || PlanPaymentStatus.pending => [
        CruButton(
          label: 'Open the payment page again',
          icon: CruIcons.arrowUpRight,
          expand: true,
          large: true,
          onPressed: _openPaymentPage,
        ),
        const SizedBox(height: CruSpace.s8),
        CruLink(
          label: _cancelling ? 'Cancelling…' : 'Cancel payment',
          onPressed: _cancelling ? null : _cancel,
        ),
      ],
      PlanPaymentStatus.expired ||
      PlanPaymentStatus.failed ||
      PlanPaymentStatus.cancelled => [
        CruButton(
          label: 'Try again',
          expand: true,
          large: true,
          onPressed: _tryAgain,
        ),
      ],
      PlanPaymentStatus.review || PlanPaymentStatus.paid => [
        CruButton(
          label: 'Close',
          expand: true,
          large: true,
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s14,
        CruSpace.s20,
        CruSpace.s24,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: buttons),
      ),
    );
  }

  Widget _receipt(CruColors c) {
    final payment = _payment;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(CruSpace.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: CruSpace.s32 * 2,
            height: CruSpace.s32 * 2,
            decoration: BoxDecoration(
              color: c.greenTint,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: CruIcon(
                CruIcons.check,
                size: CruSpace.s32,
                color: c.greenText,
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s20),
          Text('Payment received', style: CruType.title2.tint(c.label)),
          const SizedBox(height: CruSpace.s6),
          Text(
            'Your bank confirmed the payment. Your modules are on now.',
            textAlign: TextAlign.center,
            style: CruType.text.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(CruSpace.s16),
            decoration: BoxDecoration(
              color: c.inset,
              borderRadius: BorderRadius.circular(CruRadius.control),
            ),
            child: Column(
              children: [
                _receiptRow(
                  c,
                  'Amount paid',
                  _currency.format((payment?.amountPaise ?? 0) / 100),
                  strong: true,
                ),
                const SizedBox(height: CruSpace.s6),
                _receiptRow(c, 'UPI reference (UTR)', payment?.utr ?? '—'),
                const SizedBox(height: CruSpace.s6),
                _receiptRow(
                  c,
                  'Transaction ID',
                  payment?.transactionId ?? '—',
                ),
                const SizedBox(height: CruSpace.s6),
                _receiptRow(
                  c,
                  'Modules',
                  '${widget.selectedModules.length}',
                ),
                const SizedBox(height: CruSpace.s6),
                _receiptRow(
                  c,
                  'Valid until',
                  payment?.validUntil != null
                      ? DateFormat('d MMM yyyy').format(payment!.validUntil!)
                      : '30 days',
                  strong: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s24),
          CruButton(
            label: 'Start using them',
            expand: true,
            large: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(
    CruColors c,
    String label,
    String value, {
    bool strong = false,
  }) {
    return Row(
      children: [
        Text(label, style: CruType.caption.tint(c.label2)),
        const SizedBox(width: CruSpace.s12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: (strong ? CruType.callout.w600 : CruType.caption).tabular
                .tint(strong ? c.label : c.label2),
          ),
        ),
      ],
    );
  }
}
