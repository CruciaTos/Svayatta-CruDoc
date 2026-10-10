import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/features/subscription/presentation/payment_checkout_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Full-screen "Subscription & Billing" page a doctor can open any time —
/// not only when they hit a locked feature. It shows the current plan, lets
/// them pick the modules they want and pay to activate them for 30 days,
/// and lists their recent payments.
///
/// Built with the Calm Clinical design kit (see
/// design/dashboard-redesign/claude-rules/crudoc-ui.md): design tokens only,
/// Ink Blue reserved for the single primary action, green for an active
/// plan, amber for an expired one.
class SubscriptionBillingPage extends StatefulWidget {
  const SubscriptionBillingPage({super.key});

  @override
  State<SubscriptionBillingPage> createState() =>
      _SubscriptionBillingPageState();
}

class _SubscriptionBillingPageState extends State<SubscriptionBillingPage> {
  final DoctorSubscriptionService _service = DoctorSubscriptionService();
  final Set<String> _selected = {};
  bool _primed = false;

  final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// Pre-selects the modules already enabled the first time the plan loads.
  void _primeSelection(DoctorSubscriptionInfo info) {
    if (_primed) return;
    _primed = true;
    for (final item in DoctorSubscriptionService.availableFeatures) {
      if (item.isBaseModule || info.enabledModules.contains(item.moduleKey)) {
        _selected.add(item.moduleKey);
      }
    }
  }

  double get _total {
    double total = 0;
    for (final item in DoctorSubscriptionService.availableFeatures) {
      if (_selected.contains(item.moduleKey)) {
        total += item.monthlyPriceInr;
      }
    }
    return total;
  }

  /// Icon and quiet tint for each module. AI modules take violet, the one
  /// colour the rules reserve for AI; base modules stay slate so they read
  /// as plumbing, not something to buy.
  (CruIconData, MobileTone) _glyph(String iconName) {
    switch (iconName) {
      case 'dashboard':
        return (CruIcons.dashboard, MobileTone.slate);
      case 'groups':
        return (CruIcons.patients, MobileTone.slate);
      case 'calendar':
        return (CruIcons.calendar, MobileTone.slate);
      case 'inventory':
        return (CruIcons.box, MobileTone.slate);
      case 'payments':
        return (CruIcons.wallet, MobileTone.indigo);
      case 'home':
        return (CruIcons.home, MobileTone.teal);
      case 'chat':
        return (CruIcons.whatsapp, MobileTone.sky);
      case 'smart_toy':
        return (CruIcons.sparkle, MobileTone.violet);
      case 'phone':
        return (CruIcons.phone, MobileTone.violet);
      case 'devices':
        return (CruIcons.userPlus, MobileTone.indigo);
      default:
        return (CruIcons.sparkle, MobileTone.slate);
    }
  }

  Future<void> _checkout() async {
    if (_selected.isEmpty) return;
    final ok = await PaymentCheckoutSheet.show(
      context,
      selectedModules: _selected.toList(),
      totalAmount: _total,
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Features unlocked and active for 30 days.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.cru.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return StreamBuilder<DoctorSubscriptionInfo>(
      stream: _service.watchSubscriptionInfo(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final Widget body = info == null
            ? const Center(child: MobileLoading('Loading your plan'))
            : _content(info);

        if (wide) {
          return Scaffold(
            backgroundColor: c.canvas,
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CruSpace.s10,
                      CruSpace.s8,
                      CruSpace.s10,
                      0,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: CruLink(
                        label: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: MobileType.row.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        leading: const CruIcon(
                          CruIcons.chevronLeft,
                          size: 22,
                          strokeWidth: 2.2,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          );
        }

        return MobileHostPage(backLabel: 'More', child: body);
      },
    );
  }

  Widget _content(DoctorSubscriptionInfo info) {
    _primeSelection(info);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: CruSpace.s24),
            children: [
              const MobileHeader(
                title: 'Subscription & Billing',
                subtitle: 'Unlock features and manage your plan',
                pushed: true,
              ),
              const SizedBox(height: CruSpace.s16),
              _planCard(info),
              const SizedBox(height: CruSpace.s20),
              MobileRowGroup(
                title: 'Modules',
                children: [
                  for (final item in DoctorSubscriptionService.availableFeatures)
                    _moduleRow(item),
                ],
              ),
              const SizedBox(height: CruSpace.s20),
              _billingHistory(),
            ],
          ),
        ),
        _payBar(),
      ],
    );
  }

  Widget _planCard(DoctorSubscriptionInfo info) {
    final c = context.cru;
    final expired = info.isExpired;
    final tone = expired ? MobileTone.amber : MobileTone.green;
    final when = info.expiresDate != null
        ? (expired
              ? 'Expired on ${DateFormat('dd MMM yyyy').format(info.expiresDate!)}'
              : 'Valid until ${DateFormat('dd MMM yyyy').format(info.expiresDate!)} · ${info.daysRemaining ?? 0} days left')
        : 'Standard account configuration';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
      child: MobileCard(
        padding: const EdgeInsets.all(CruSpace.s16),
        child: Row(
          children: [
            MobileIconTile(
              icon: expired ? CruIcons.warning : CruIcons.check,
              tone: tone,
              size: 44,
              iconSize: 20,
            ),
            const SizedBox(width: CruSpace.s14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${info.planName} plan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MobileType.title2.tint(c.label),
                        ),
                      ),
                      const SizedBox(width: CruSpace.s8),
                      MobilePill(
                        expired ? 'Expired' : 'Active',
                        tone: tone,
                      ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.s4),
                  Text(when, style: MobileType.subhead.tint(c.label2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moduleRow(FeaturePricingItem item) {
    final c = context.cru;
    final selected = _selected.contains(item.moduleKey);
    final base = item.isBaseModule;
    final (icon, tone) = _glyph(item.iconName);

    final Widget trailing = base
        ? MobilePill('Included', tone: MobileTone.green)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_inr.format(item.monthlyPriceInr)}/mo',
                style: MobileType.callout.tabular.tint(
                  selected ? c.accent : c.label,
                ),
              ),
              const SizedBox(width: CruSpace.s10),
              _selectDot(selected),
            ],
          );

    return MobileRow(
      leading: MobileIconTile(icon: icon, tone: tone),
      title: item.title,
      subtitle: item.description,
      trailing: trailing,
      onTap: base
          ? null
          : () => setState(() {
              if (selected) {
                _selected.remove(item.moduleKey);
              } else {
                _selected.add(item.moduleKey);
              }
            }),
    );
  }

  /// A tap target that reads as a checkbox without a Material checkbox: an
  /// Ink-Blue disc with a tick when on (the app's selected-state colour,
  /// as used by the filter chips), a hairline ring when off.
  Widget _selectDot(bool selected) {
    final c = context.cru;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.accent : Colors.transparent,
        border: selected ? null : Border.all(color: c.separator, width: 1.5),
      ),
      child: selected
          ? const CruIcon(
              CruIcons.check,
              size: 14,
              strokeWidth: 2.4,
              color: Colors.white,
            )
          : null,
    );
  }

  Widget _billingHistory() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('payment_transactions')
          .where('doctorId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = (snapshot.data?.docs ?? []).toList()
          ..sort((a, b) {
            final ta = a.data()['timestamp'];
            final tb = b.data()['timestamp'];
            final da = ta is Timestamp ? ta.toDate() : DateTime(0);
            final db = tb is Timestamp ? tb.toDate() : DateTime(0);
            return db.compareTo(da);
          });

        if (docs.isEmpty) {
          return const MobileEmpty(
            icon: CruIcons.wallet,
            title: 'No payments yet',
            body: 'Your receipts will appear here once you activate a module.',
          );
        }

        return MobileRowGroup(
          title: 'Billing history',
          indent: 60,
          children: [for (final d in docs) _historyRow(d.data())],
        );
      },
    );
  }

  Widget _historyRow(Map<String, dynamic> data) {
    final c = context.cru;
    final ts = data['timestamp'];
    final when = ts is Timestamp ? ts.toDate() : null;
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final method = (data['paymentMethod'] as String?) ?? '—';
    final count = (data['activatedModules'] as List?)?.length ?? 0;

    return MobileRow(
      leading: const MobileIconTile(icon: CruIcons.check, tone: MobileTone.green),
      title: when != null
          ? DateFormat('dd MMM yyyy, h:mm a').format(when)
          : 'Payment',
      subtitle: '$method · $count modules',
      trailing: Text(
        _inr.format(amount),
        style: MobileType.callout.w600.tabular.tint(c.label),
      ),
    );
  }

  Widget _payBar() {
    final c = context.cru;
    final empty = _selected.isEmpty;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.separator)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MobileMetrics.gutter,
            CruSpace.s12,
            MobileMetrics.gutter,
            CruSpace.s12,
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('TOTAL', style: MobileType.micro.tint(c.label2)),
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    '${_inr.format(_total)}/mo',
                    style: MobileType.metric.tint(c.label),
                  ),
                ],
              ),
              const SizedBox(width: CruSpace.s16),
              Expanded(
                child: MobilePrimaryButton(
                  label: empty
                      ? 'Select a module'
                      : 'Pay ${_inr.format(_total)}',
                  icon: CruIcons.wallet,
                  onPressed: empty ? null : _checkout,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
