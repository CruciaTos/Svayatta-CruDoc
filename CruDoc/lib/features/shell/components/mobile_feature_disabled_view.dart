import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/features/subscription/presentation/feature_upgrade_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Shown in place of a page whose module isn't in the clinic's plan (or
/// whose plan has ended): what it is, and the one way to turn it on.
class MobileFeatureDisabledView extends StatelessWidget {
  final String featureTitle;
  final IconData icon;
  final VoidCallback? onBackToDashboard;

  const MobileFeatureDisabledView({
    super.key,
    required this.featureTitle,
    required this.icon,
    this.onBackToDashboard,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final subscriptionService = DoctorSubscriptionService();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CruSpace.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: CruCard(
            padding: const EdgeInsets.all(CruSpace.s32),
            child: StreamBuilder<DoctorSubscriptionInfo>(
              stream: subscriptionService.watchSubscriptionInfo(),
              builder: (context, snapshot) {
                final info = snapshot.data;
                final ended = info?.isExpired ?? false;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The feature's icon with a small lock.
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: ended ? c.amberTint : c.inset,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              icon,
                              size: 28,
                              color: ended ? c.amberText : c.label2,
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(CruSpace.s4),
                              decoration: BoxDecoration(
                                color: c.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.hairline),
                              ),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 14,
                                color: c.label2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: CruSpace.s20),
                    Text(
                      ended
                          ? 'Your plan has ended'
                          : '$featureTitle isn’t in your plan',
                      textAlign: TextAlign.center,
                      style: CruType.title2.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s8),
                    Text(
                      ended
                          ? 'Choose a plan to keep using $featureTitle and the '
                                'rest of CruDoc.'
                          : 'Add it to your plan to use it in this clinic.',
                      textAlign: TextAlign.center,
                      style: CruType.text.tint(c.label2),
                    ),
                    const SizedBox(height: CruSpace.s24),
                    if (info != null)
                      CruButton(
                        label: ended ? 'Choose a plan' : 'Upgrade plan',
                        expand: true,
                        onPressed: () => FeatureUpgradeSheet.show(
                          context,
                          subscriptionInfo: info,
                        ),
                      ),
                    if (onBackToDashboard != null) ...[
                      const SizedBox(height: CruSpace.s10),
                      CruButton(
                        label: 'Back to Dashboard',
                        kind: CruButtonKind.secondary,
                        expand: true,
                        onPressed: onBackToDashboard,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
