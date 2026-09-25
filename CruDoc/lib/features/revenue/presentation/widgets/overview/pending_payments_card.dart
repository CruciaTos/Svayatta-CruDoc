import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Separators start after the monogram: 36 + gap 12.
const double _textInset = CruSize.monogramList + CruSpace.s12;

/// One row per patient with a balance, oldest first.
class PendingPaymentsCard extends StatelessWidget {
  const PendingPaymentsCard({
    super.key,
    required this.groups,
    required this.onMarkPaid,
    required this.onSendReminders,
  });

  final List<PendingGroup> groups;
  final ValueChanged<PendingGroup> onMarkPaid;
  final VoidCallback onSendReminders;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final total = groups.fold<double>(0, (s, g) => s + g.total);
    final canRemind = groups.any((g) => g.canRemind);
    return CruCard(
      semanticLabel: 'Pending payments',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s24,
        CruSpace.s20,
        CruSpace.s24,
        CruSpace.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Pending payments',
                    style: CruType.headline.tint(c.label),
                  ),
                ),
              ),
              Text(
                DashFormat.rupees(total),
                style: CruType.row.tabular.tint(c.label),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s6),
          Text(
            groups.isEmpty
                ? 'Nothing is owed right now'
                : '${DashFormat.plural(groups.length, 'patient')} · oldest first',
            style: CruType.subhead.tint(c.label2),
          ),
          if (groups.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s4),
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const CruSeparator(indent: _textInset),
              _PendingRow(
                group: groups[i],
                onMarkPaid: () => onMarkPaid(groups[i]),
              ),
            ],
          ],
          if (canRemind) ...[
            const SizedBox(height: CruSpace.s14),
            CruButton(
              label: 'Send reminders on WhatsApp',
              kind: CruButtonKind.tinted,
              icon: RevenueIcons.chat,
              expand: true,
              onPressed: onSendReminders,
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.group, required this.onMarkPaid});

  final PendingGroup group;
  final VoidCallback onMarkPaid;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final g = group;
    return Semantics(
      container: true,
      label: '${g.name}, ${DashFormat.rupees(g.total)} due, ${g.detail}',
      child: SizedBox(
        height: CruSize.scheduleRow,
        child: Row(
          children: [
            CruMonogram(
              name: g.name,
              size: CruSize.monogramList,
              background: c.inset,
            ),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: g.name,
                          style: CruType.callout.tint(c.label),
                        ),
                        TextSpan(
                          text: ' ${DashFormat.rupees(g.total)}',
                          style: CruType.callout.tabular.tint(c.amberText),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      g.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.caption.tabular
                          .tint(g.overdue ? c.amberText : c.label2),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            CruCapsuleButton(
              label: 'Mark paid',
              semanticLabel: 'Mark ${g.name} paid',
              onPressed: onMarkPaid,
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder: three fixed-height rows.
class PendingPaymentsSkeleton extends StatelessWidget {
  const PendingPaymentsSkeleton({super.key});

  @override
  Widget build(BuildContext context) =>
      const SkeletonCard(rows: 3, rowHeight: CruSize.scheduleRow);
}
