import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/transaction_row.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The period's transactions with an All / Money in / Money out filter.
class TransactionsCard extends StatelessWidget {
  const TransactionsCard({
    super.key,
    required this.rows,
    required this.filter,
    required this.expanded,
    required this.todayIn,
    required this.todayOut,
    required this.onFilter,
    required this.onToggleExpanded,
    required this.onOpen,
  });

  final List<TxnRow> rows;
  final TxnFilter filter;
  final bool expanded;
  final double todayIn;
  final double todayOut;
  final ValueChanged<TxnFilter> onFilter;
  final VoidCallback onToggleExpanded;
  final ValueChanged<RevenueEntry> onOpen;

  String get _emptyText => switch (filter) {
        TxnFilter.all => 'No transactions in this period',
        TxnFilter.moneyIn => 'No money in during this period',
        TxnFilter.moneyOut => 'No money out during this period',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final canExpand = rows.length > RevenueBuilder.collapsedRows;
    final shown = expanded || !canExpand
        ? rows
        : rows.take(RevenueBuilder.collapsedRows).toList();

    return CruCard(
      semanticLabel: 'Transactions',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s18,
        CruSpace.s12,
        CruSpace.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s12,
              0,
              CruSpace.s12,
              CruSpace.s10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Transactions',
                      style: CruType.headline.tint(c.label),
                    ),
                  ),
                ),
                CruSegmentedControl<TxnFilter>(
                  semanticLabel: 'Transaction type',
                  segments: const [
                    CruSegment(TxnFilter.all, 'All'),
                    CruSegment(TxnFilter.moneyIn, 'Money in'),
                    CruSegment(TxnFilter.moneyOut, 'Money out'),
                  ],
                  selected: filter,
                  onChanged: onFilter,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: CruMotion.of(context),
            curve: CruMotion.curve,
            alignment: Alignment.topCenter,
            child: shown.isEmpty
                ? SizedBox(
                    height: kTxnRowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CruSpace.s12,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _emptyText,
                          style: CruType.text.tint(c.label2),
                        ),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0)
                          const CruSeparator(
                            indent: kTxnTextInset,
                            endIndent: CruSpace.s12,
                          ),
                        TransactionRow(
                          row: shown[i],
                          onTap: () => onOpen(shown[i].entry),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: CruSpace.s4),
          const CruSeparator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s12,
              CruSpace.s12,
              CruSpace.s12,
              CruSpace.s2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Today · ${DashFormat.rupees(todayIn)} in'
                    ' · ${DashFormat.rupees(todayOut)} out',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.subhead.tabular.tint(c.label2),
                  ),
                ),
                if (canExpand)
                  CruLink(
                    label: expanded ? 'Show fewer' : 'See all transactions',
                    onPressed: onToggleExpanded,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder: six fixed-height rows.
class TransactionsSkeleton extends StatelessWidget {
  const TransactionsSkeleton({super.key});

  @override
  Widget build(BuildContext context) =>
      const SkeletonCard(rows: RevenueBuilder.collapsedRows, rowHeight: kTxnRowHeight);
}
