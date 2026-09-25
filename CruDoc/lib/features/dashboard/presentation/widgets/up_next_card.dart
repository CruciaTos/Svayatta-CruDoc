import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The earliest waiting patient on the ink surface.
///
/// The "Alerts and vitals" block from the design is not shown: patients
/// have no allergy field and no pre-consultation vitals are recorded
/// (GAPs, see IMPLEMENTATION_REPORT.md).
class UpNextCard extends ConsumerWidget {
  const UpNextCard({super.key, required this.data, required this.navigate});

  final UpNextData data;
  final ValueChanged<int> navigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CruInkCard(
      semanticLabel: 'Up next',
      child: Builder(builder: (context) {
        final c = context.cru; // on-ink colours
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Up next', style: CruType.subhead.w600.tint(c.accentText)),
                if (data.tokenNumber != null) ...[
                  const SizedBox(width: CruSpace.s8),
                  Text('·', style: CruType.subhead.tint(c.label3)),
                  const SizedBox(width: CruSpace.s8),
                  Text(
                    'Token ${data.tokenNumber}',
                    style: CruType.subhead.w500.tabular.tint(c.label2),
                  ),
                ],
                const Spacer(),
                CruPill(
                  text: 'Waiting ${DashFormat.minutes(data.waitMinutes)}',
                  icon: CruIcons.clock,
                  background: c.amberTint,
                  foreground: c.amberText,
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s18),
            Row(
              children: [
                CruMonogram(
                  name: data.name,
                  size: CruSize.monogramUpNext,
                  foreground: c.label,
                ),
                const SizedBox(width: CruSpace.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.name,
                        style: CruType.title.tint(c.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        data.details,
                        style: CruType.text.tabular.tint(c.label2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (data.reason != null) ...[
              const SizedBox(height: CruSpace.s18),
              Text('Reason for visit', style: CruType.subhead.w500.tint(c.label2)),
              const SizedBox(height: CruSpace.s4),
              Text(
                data.reason!,
                style: CruType.body.tint(c.label),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: CruSpace.s18 + CruSpace.s2),
            Row(
              children: [
                CruButton(
                  label: 'Start consultation',
                  large: true,
                  onPressed: () => DashboardActions.startConsultation(
                    context,
                    ref,
                    data,
                    navigate: navigate,
                  ),
                ),
                if (data.patient != null) ...[
                  const SizedBox(width: CruSpace.s10),
                  CruButton(
                    label: 'View history',
                    kind: CruButtonKind.inset,
                    large: true,
                    onPressed: () =>
                        DashboardActions.openPatient(context, data.patient!),
                  ),
                ],
                const Spacer(),
                _MoreMenu(data: data, navigate: navigate),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.data, required this.navigate});

  final UpNextData data;
  final ValueChanged<int> navigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CruIconButton(
      icon: CruIcons.more,
      semanticLabel: 'More actions for ${data.name}',
      tooltip: 'More actions',
      onPressed: () async {
        final box = context.findRenderObject()! as RenderBox;
        final overlay =
            Overlay.of(context).context.findRenderObject()! as RenderBox;
        final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
        final choice = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            origin.dx,
            origin.dy + box.size.height,
            overlay.size.width - origin.dx - box.size.width,
            0,
          ),
          items: const [
            PopupMenuItem(value: 'skip', child: Text('Not here yet · skip')),
            PopupMenuItem(value: 'cancel', child: Text('Cancel token')),
            PopupMenuItem(value: 'queue', child: Text('Open queue')),
          ],
        );
        if (!context.mounted) return;
        switch (choice) {
          case 'skip':
            await DashboardActions.skip(context, ref, data);
          case 'cancel':
            await DashboardActions.cancel(context, ref, data);
          case 'queue':
            navigate(DesktopTab.queue);
        }
      },
    );
  }
}

/// Shown instead of an empty ink card when nobody is waiting.
class NoOneWaitingCard extends StatelessWidget {
  const NoOneWaitingCard({super.key, required this.nextBooking});

  final DateTime? nextBooking;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Up next',
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No one waiting', style: CruType.headline.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(
                  nextBooking == null
                      ? 'No more bookings today'
                      : 'Next booking at ${DashFormat.time(nextBooking!)}',
                  style: CruType.subhead.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
          CruButton(
            label: 'New visit',
            kind: CruButtonKind.inset,
            icon: CruIcons.plus,
            onPressed: () => DashboardActions.newVisit(context),
          ),
        ],
      ),
    );
  }
}
