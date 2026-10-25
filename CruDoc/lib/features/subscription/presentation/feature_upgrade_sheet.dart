import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/features/subscription/data/upgrade_request_model.dart';
import 'package:doctor_management_app/features/subscription/presentation/payment_checkout_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Modal bottom sheet that lets doctors view available features,
/// calculate monthly totals, and submit an upgrade request.
class FeatureUpgradeSheet extends StatefulWidget {
  final DoctorSubscriptionInfo subscriptionInfo;

  const FeatureUpgradeSheet({super.key, required this.subscriptionInfo});

  static Future<void> show(
    BuildContext context, {
    required DoctorSubscriptionInfo subscriptionInfo,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeatureUpgradeSheet(subscriptionInfo: subscriptionInfo),
    );
  }

  @override
  State<FeatureUpgradeSheet> createState() => _FeatureUpgradeSheetState();
}

class _FeatureUpgradeSheetState extends State<FeatureUpgradeSheet> {
  final DoctorSubscriptionService _subscriptionService =
      DoctorSubscriptionService();
  final Set<String> _selectedModuleKeys = {};

  @override
  void initState() {
    super.initState();
    // Pre-select modules that are currently enabled
    for (final item in DoctorSubscriptionService.availableFeatures) {
      if (item.isBaseModule ||
          widget.subscriptionInfo.enabledModules.contains(item.moduleKey)) {
        _selectedModuleKeys.add(item.moduleKey);
      }
    }
  }

  double get _calculatedTotal {
    double total = 0;
    for (final item in DoctorSubscriptionService.availableFeatures) {
      if (_selectedModuleKeys.contains(item.moduleKey)) {
        total += item.monthlyPriceInr;
      }
    }
    return total;
  }

  CruIconData _iconFor(String name) => switch (name) {
    'dashboard' => CruIcons.dashboard,
    'groups' => CruIcons.patients,
    'calendar' => CruIcons.calendar,
    'inventory' => CruIcons.box,
    'payments' => CruIcons.rupee,
    'home' => CruIcons.home,
    'chat' => CruIcons.whatsapp,
    'smart_toy' => CruIcons.sparkle,
    'phone' => CruIcons.phone,
    _ => CruIcons.plus,
  };

  Future<void> _launchPaymentCheckout() async {
    if (_selectedModuleKeys.isEmpty) return;

    final selectedList = _selectedModuleKeys.toList();
    final result = await PaymentCheckoutSheet.show(
      context,
      selectedModules: selectedList,
      totalAmount: _calculatedTotal,
    );

    if (result == true && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Features unlocked and active for 30 days.'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  static final _rupees = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
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
      child: Column(
        children: [
          Center(
            child: Container(
              width: CruSpace.s32 + CruSpace.s12,
              height: CruSpace.s4,
              margin: const EdgeInsets.only(
                top: CruSpace.s12,
                bottom: CruSpace.s8,
              ),
              decoration: BoxDecoration(
                color: c.track,
                borderRadius: BorderRadius.circular(CruRadius.full),
              ),
            ),
          ),
          Padding(
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
                      Text(
                        'Choose your features',
                        style: CruType.title2.tint(c.label),
                      ),
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        'Pick the modules your practice needs.',
                        style: CruType.caption.tint(c.label2),
                      ),
                    ],
                  ),
                ),
                CruIconButton(
                  icon: CruIcons.close,
                  onPressed: () => Navigator.pop(context),
                  semanticLabel: 'Close',
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.separator),
          Expanded(
            child: StreamBuilder<List<UpgradeRequest>>(
              stream: _subscriptionService.watchMyUpgradeRequests(),
              builder: (context, snapshot) {
                final requests = snapshot.data ?? [];
                final pendingRequest = requests
                    .cast<UpgradeRequest?>()
                    .firstWhere(
                      (r) => r?.status == UpgradeRequestStatus.pending,
                      orElse: () => null,
                    );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    CruSpace.s20,
                    CruSpace.s16,
                    CruSpace.s20,
                    CruSpace.s24,
                  ),
                  children: [
                    if (pendingRequest != null) _pendingBanner(c, pendingRequest),
                    _currentPlan(c),
                    const SizedBox(height: CruSpace.s20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'MODULES',
                            style: CruType.groupLabel.tint(c.label3),
                          ),
                        ),
                        Text(
                          '${_selectedModuleKeys.length} selected',
                          style: CruType.caption.w600.tabular.tint(c.label2),
                        ),
                      ],
                    ),
                    const SizedBox(height: CruSpace.s10),
                    for (final item in DoctorSubscriptionService.availableFeatures)
                      _moduleRow(c, item),
                    const SizedBox(height: CruSpace.s16),
                    _howItWorks(c),
                  ],
                );
              },
            ),
          ),
          _bottomBar(c),
        ],
      ),
    );
  }

  Widget _currentPlan(CruColors c) {
    final info = widget.subscriptionInfo;
    final expired = info.isExpired;
    final date = info.expiresDate == null
        ? null
        : DateFormat('d MMM yyyy').format(info.expiresDate!);
    return Container(
      padding: const EdgeInsets.all(CruSpace.s14),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CruRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current plan: ${info.planName}',
                  style: CruType.callout.w600.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  date == null
                      ? 'Standard account'
                      : expired
                      ? 'Ended on $date'
                      : 'Valid until $date · ${info.daysRemaining ?? 0} days left',
                  style: CruType.caption.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
          CruPill(
            text: expired ? 'Ended' : 'Active',
            background: expired ? c.track : c.greenTint,
            foreground: expired ? c.label2 : c.greenText,
          ),
        ],
      ),
    );
  }

  /// Amber: a request still waiting on the team.
  Widget _pendingBanner(CruColors c, UpgradeRequest request) {
    return Container(
      margin: const EdgeInsets.only(bottom: CruSpace.s16),
      padding: const EdgeInsets.all(CruSpace.s14),
      decoration: BoxDecoration(
        color: c.amberTint,
        borderRadius: BorderRadius.circular(CruRadius.control),
      ),
      child: Row(
        children: [
          CruIcon(CruIcons.clock, color: c.amberText),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upgrade request waiting',
                  style: CruType.callout.w600.tint(c.amberText),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  '${_rupees.format(request.totalMonthlyPrice)}/month for '
                  '${request.requestedModules.length} features. We turn them '
                  'on once the payment is checked.',
                  style: CruType.caption.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleRow(CruColors c, FeaturePricingItem item) {
    final selected = _selectedModuleKeys.contains(item.moduleKey);
    final included = item.isBaseModule;
    void toggle() => setState(() {
      if (selected) {
        _selectedModuleKeys.remove(item.moduleKey);
      } else {
        _selectedModuleKeys.add(item.moduleKey);
      }
    });

    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s8),
      child: CruPressable(
        onTap: included ? null : toggle,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s14,
            vertical: CruSpace.s12,
          ),
          decoration: BoxDecoration(
            color: hovered && !included ? c.hoverFill : c.surface,
            borderRadius: BorderRadius.circular(CruRadius.control),
            border: Border.all(color: selected ? c.inkBorder : c.cardBorder),
          ),
          child: Row(
            children: [
              CruIconTile(icon: _iconFor(item.iconName), tone: CruTileTone.neutral),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: CruType.callout.w600.tint(c.label)),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      item.description,
                      style: CruType.caption.tint(c.label2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s8),
              Text(
                included
                    ? 'Included'
                    : '${_rupees.format(item.monthlyPriceInr)}/mo',
                style: CruType.callout.w600.tabular.tint(
                  included ? c.label2 : c.label,
                ),
              ),
              Checkbox(
                value: included || selected,
                onChanged: included ? null : (_) => toggle(),
                activeColor: c.accent,
                checkColor: c.onAccent,
                side: BorderSide(color: c.separator, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CruSpace.s4),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _howItWorks(CruColors c) {
    return Container(
      padding: const EdgeInsets.all(CruSpace.s14),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CruRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How it works', style: CruType.caption.w600.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Text(
            'Pick your modules, then pay by UPI. They turn on as soon as the '
            'payment is confirmed and stay on for 30 days.',
            style: CruType.caption.tint(c.label2),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(CruColors c) {
    final count = _selectedModuleKeys.length;
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
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('PER MONTH', style: CruType.groupLabel.tint(c.label3)),
                const SizedBox(height: CruSpace.s2),
                Text(
                  _rupees.format(_calculatedTotal),
                  style: CruType.amount.tabular.tint(c.label),
                ),
              ],
            ),
            const SizedBox(width: CruSpace.s20),
            Expanded(
              child: CruButton(
                label: count == 0 ? 'Pick a module' : 'Pay and turn on ($count)',
                expand: true,
                large: true,
                onPressed: count == 0 ? null : _launchPaymentCheckout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
