import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A page someone in a clinic team can't open: not part of their role, or
/// not in the clinic's plan. Only the owner can upgrade, so no upgrade
/// button here.
class NotAvailableView extends StatelessWidget {
  const NotAvailableView({
    super.key,
    required this.featureTitle,
    required this.inPlan,
    this.onBackToDashboard,
  });

  final String featureTitle;

  /// True: the plan has it but the role doesn't. False: not in the plan.
  final bool inPlan;
  final VoidCallback? onBackToDashboard;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CruSpace.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                inPlan
                    ? '$featureTitle isn\'t part of your role'
                    : '$featureTitle isn\'t in your clinic\'s plan',
                style: CruType.title.tint(c.label),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: CruSpace.s8),
              Text(
                inPlan
                    ? 'Ask your clinic admin if you need it.'
                    : 'Ask the clinic owner to add it.',
                style: CruType.text.tint(c.label2),
                textAlign: TextAlign.center,
              ),
              if (onBackToDashboard != null) ...[
                const SizedBox(height: CruSpace.s20),
                CruButton(
                  label: 'Back to Dashboard',
                  kind: CruButtonKind.inset,
                  onPressed: onBackToDashboard,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
