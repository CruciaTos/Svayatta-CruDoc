import 'package:doctor_management_app/core/utils/app_notice.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/utils/store_policy.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/features/subscription/presentation/apple_checkout_list.dart';
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

  final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// The modules on offer that are ticked. Going through the plan's own list
  /// of what can still be bought means a module that has just switched on
  /// (its payment landed) is never counted or charged a second time.
  List<FeaturePricingItem> _picked(DoctorSubscriptionInfo info) => [
    for (final item in info.purchasableModules)
      if (_selected.contains(item.moduleKey)) item,
  ];

  /// What a payment buys: the ticked modules plus the paid modules already
  /// on. Every payment rewrites the doctor's whole module list on the
  /// server (see [DoctorSubscriptionInfo.ownedPaidModules]), so leaving the
  /// owned ones out would switch them off. They are charged and renewed
  /// with it, so [_total] counts them too and the pay bar says so.
  List<FeaturePricingItem> _order(DoctorSubscriptionInfo info) => [
    ...info.ownedPaidModules,
    ..._picked(info),
  ];

  double _sum(Iterable<FeaturePricingItem> items) =>
      items.fold(0.0, (total, item) => total + item.monthlyPriceInr);

  /// What the server will charge: nothing until a new module is ticked.
  double _total(DoctorSubscriptionInfo info) =>
      _picked(info).isEmpty ? 0 : _sum(_order(info));

  /// Icon and quiet tint for each module. AI modules take violet, the one
  /// colour the rules reserve for AI.
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

  Future<void> _checkout(DoctorSubscriptionInfo info) async {
    if (_picked(info).isEmpty) return;
    final order = _order(info);
    final ok = await PaymentCheckoutSheet.show(
      context,
      selectedModules: [for (final item in order) item.moduleKey],
      totalAmount: _sum(order),
    );
    if (ok == true && mounted) {
      setState(_selected.clear);
      ScaffoldMessenger.of(context).showIsland(
        const SnackBar(
          content: Text('Features unlocked and active for 30 days.'),
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
    if (!storePurchasesAllowed) {
      return ListView(
        padding: const EdgeInsets.only(bottom: CruSpace.s24),
        children: [
          const MobileHeader(
            title: 'Subscription & Billing',
            subtitle: 'Manage your plan',
            pushed: true,
          ),
          const SizedBox(height: CruSpace.s16),
          _planCard(info),
          const SizedBox(height: CruSpace.s20),
          const AppleCheckoutList(),
        ],
      );
    }

    // Only what the doctor doesn't have: owned and base modules aren't
    // for sale.
    final offers = info.purchasableModules;
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
              if (offers.isEmpty)
                const MobileEmpty(
                  icon: CruIcons.check,
                  title: 'You have every module',
                  body:
                      'Everything CruDoc offers is switched on for your clinic.',
                )
              else
                MobileRowGroup(
                  title: 'Modules',
                  children: [for (final item in offers) _moduleRow(item)],
                ),
              const SizedBox(height: CruSpace.s20),
              _billingHistory(),
            ],
          ),
        ),
        if (offers.isNotEmpty) _payBar(info),
      ],
    );
  }

  Widget _planCard(DoctorSubscriptionInfo info) {
    final c = context.cru;
    final expired = info.isExpired;
    final tone = expired ? MobileTone.amber : MobileTone.green;
    final when = info.validityLine;

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
                      MobilePill(expired ? 'Expired' : 'Active', tone: tone),
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
    final (icon, tone) = _glyph(item.iconName);

    return MobileRow(
      leading: MobileIconTile(icon: icon, tone: tone),
      title: item.title,
      subtitle: item.description,
      trailing: Row(
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
      ),
      onTap: () => setState(() {
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
      leading: const MobileIconTile(
        icon: CruIcons.check,
        tone: MobileTone.green,
      ),
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

  Widget _payBar(DoctorSubscriptionInfo info) {
    final c = context.cru;
    final empty = _picked(info).isEmpty;
    final total = _total(info);
    // The owned modules ride along in every payment (see [_order]); say so
    // rather than let the total look bigger than what was ticked.
    final kept = _sum(info.ownedPaidModules);
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!empty && kept > 0) ...[
                Text(
                  'Includes ${_inr.format(kept)} to keep the modules you '
                  'already have on.',
                  style: MobileType.caption.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s10),
              ],
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('TOTAL', style: MobileType.micro.tint(c.label2)),
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        '${_inr.format(total)}/mo',
                        style: MobileType.metric.tint(c.label),
                      ),
                    ],
                  ),
                  const SizedBox(width: CruSpace.s16),
                  Expanded(
                    child: MobilePrimaryButton(
                      label: empty
                          ? 'Select a module'
                          : 'Pay ${_inr.format(total)}',
                      icon: CruIcons.wallet,
                      onPressed: empty ? null : () => _checkout(info),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
