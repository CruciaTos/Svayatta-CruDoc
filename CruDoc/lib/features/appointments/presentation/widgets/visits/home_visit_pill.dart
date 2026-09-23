import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Height of the pill: small enough to sit on a name line.
const double _kHeight = 18;

/// "⌂ Visit" after a patient's name: this is a home visit, not a clinic
/// appointment. In the house colour on its tint; muted once the visit is
/// seen or missed.
class HomeVisitPill extends StatelessWidget {
  const HomeVisitPill({super.key, this.quiet = false});

  /// Seen or missed: grey, so it doesn't compete with open visits.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fg = quiet ? c.label3 : c.homeVisit;
    return Container(
      height: _kHeight,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s6),
      decoration: ShapeDecoration(
        color: quiet ? c.inset : c.accentTint,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CruIcon(CruIcons.home, size: 11, strokeWidth: 2.4, color: fg),
          const SizedBox(width: CruSpace.s4),
          Text('Visit', style: CruType.micro.w600.tint(fg)),
        ],
      ),
    );
  }
}
