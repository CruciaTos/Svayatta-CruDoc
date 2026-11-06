import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The plan card at the top of More, in the manner of Claude's "Want more
/// Claude?" card: a plain card like every other on More, a bold title, one
/// line under it and an ink pill (the card's colours flipped) that opens
/// Subscription & Billing. No brand colour: it's an offer, not an alert.
///
/// Everything it says comes from [info]: an expired plan offers a renewal,
/// a plan with modules still to buy offers an upgrade, and a plan that has
/// every module just shows itself.
class PlanUpgradeCard extends StatelessWidget {
  const PlanUpgradeCard({super.key, required this.info, required this.onOpen});

  final DoctorSubscriptionInfo info;
  final VoidCallback onOpen;

  (String title, String body, String button) get _copy {
    if (info.isExpired) {
      return (
        'Your plan has expired',
        info.expiresDate != null
            ? info.validityLine
            : 'Renew to switch your modules back on.',
        'Renew',
      );
    }
    final more = info.purchasableModules.length;
    if (more > 0) {
      return (
        'Want more CruDoc?',
        'Unlock $more more ${more == 1 ? 'module' : 'modules'} for your clinic.',
        'Upgrade',
      );
    }
    return ('All modules active', info.validityLine, 'Manage');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (title, body, button) = _copy;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
      child: Semantics(
        label: '$title. $body',
        child: MobileCard(
          onTap: () {
            MobileHaptics.tap();
            onOpen();
          },
          padding: const EdgeInsets.all(CruSpace.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: MobileType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s4),
              Text(body, style: MobileType.text.tint(c.label2)),
              const SizedBox(height: CruSpace.s16),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s20,
                  ),
                  decoration: ShapeDecoration(
                    color: c.label,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    button,
                    maxLines: 1,
                    style: MobileType.callout.w600.tint(c.surface),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
