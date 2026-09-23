import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Revenue", the period subtitle, and Record expense / Record payment.
class RevenueHeader extends StatelessWidget {
  const RevenueHeader({
    super.key,
    required this.subtitle,
    required this.onRecordExpense,
    required this.onRecordPayment,
  });

  /// "September 2026 · 1 to 23 September", or null while loading.
  final String? subtitle;
  final VoidCallback onRecordExpense;
  final VoidCallback onRecordPayment;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text('Revenue', style: CruType.largeTitle.tint(c.label)),
              ),
              const SizedBox(height: CruSpace.s2),
              Text(
                subtitle ?? '',
                style: CruType.text.tabular.tint(c.label2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: CruSpace.s24),
        CruButton(
          label: 'Record expense',
          kind: CruButtonKind.secondary,
          icon: RevenueIcons.receipt,
          onPressed: onRecordExpense,
        ),
        const SizedBox(width: CruSpace.s10),
        CruButton(
          label: 'Record payment',
          icon: CruIcons.plus,
          onPressed: onRecordPayment,
        ),
      ],
    );
  }
}

/// Overview / Invoices on the left, the period on the right.
class RevenueControls extends StatelessWidget {
  const RevenueControls({
    super.key,
    required this.tab,
    required this.period,
    required this.onTab,
    required this.onPeriod,
  });

  final RevenueTab tab;
  final RevenuePeriod period;
  final ValueChanged<RevenueTab> onTab;
  final ValueChanged<RevenuePeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: CruSize.segmentHeight,
      child: Row(
        children: [
          CruSegmentedControl<RevenueTab>(
            semanticLabel: 'Revenue sections',
            segments: const [
              CruSegment(RevenueTab.overview, 'Overview'),
              CruSegment(RevenueTab.invoices, 'Invoices'),
            ],
            selected: tab,
            onChanged: onTab,
          ),
          const Spacer(),
          // The period drives the Overview only.
          if (tab == RevenueTab.overview)
            CruSegmentedControl<RevenuePeriod>(
              semanticLabel: 'Period',
              segments: const [
                CruSegment(RevenuePeriod.today, 'Today'),
                CruSegment(RevenuePeriod.week, 'Week'),
                CruSegment(RevenuePeriod.month, 'Month'),
                CruSegment(RevenuePeriod.year, 'Year'),
              ],
              selected: period,
              onChanged: onPeriod,
            ),
        ],
      ),
    );
  }
}
