import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A sidebar page for a dental sub-specialty whose real screen hasn't
/// been built yet. Phase 1 of each sub-specialty wires the sub-login,
/// its sidebar entry and its dashboard card first, with an honest
/// "not built yet" screen behind them; a later phase replaces this
/// with the real one without touching the nav.
class DentalNotBuiltScreen extends StatelessWidget {
  const DentalNotBuiltScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final CruIconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final padding = MediaQuery.sizeOf(context).width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;
    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: CruCard(
            semanticLabel: '$title. Not built yet.',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CruIconTile(icon: icon, tone: CruTileTone.accent),
                const SizedBox(height: CruSpace.s14),
                Text(title, style: CruType.headline.tint(c.label)),
                const SizedBox(height: CruSpace.s6),
                Text(body, style: CruType.text.tint(c.label2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashboard card for a dental sub-specialty whose real screen hasn't
/// been built yet: opens [tab], which shows a matching
/// [DentalNotBuiltScreen].
class DentalNotBuiltCard extends StatelessWidget {
  const DentalNotBuiltCard({
    super.key,
    required this.icon,
    required this.title,
    required this.tab,
    required this.onNavigate,
  });

  final CruIconData icon;
  final String title;
  final int tab;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: '$title. Not built yet.',
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: DentalListRow(
        semanticLabel: '$title. Not built yet.',
        onTap: () => onNavigate(tab),
        minHeight: 60,
        child: Row(
          children: [
            CruIconTile(icon: icon, tone: CruTileTone.accent),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: CruType.callout.w600.tint(c.label)),
                  Text(
                    'Not built yet',
                    style: CruType.subhead.tabular.tint(c.label2),
                  ),
                ],
              ),
            ),
            CruIcon(CruIcons.chevronRight, size: 18, color: c.label3),
          ],
        ),
      ),
    );
  }
}
