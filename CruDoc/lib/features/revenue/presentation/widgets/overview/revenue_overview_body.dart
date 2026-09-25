import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/features/revenue/presentation/transaction_details.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/collections_by_day_card.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/pending_actions.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/pending_payments_card.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_glance.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/transactions_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Glance strip, then Collections by day and Transactions on the left
/// with Pending payments in the 384 px right column. "By service" is a
/// GAP (entries carry no service or category), so Pending payments
/// sits at the top of the right column. Below 1200 px the right column
/// stacks under the left.
class RevenueOverviewBody extends ConsumerWidget {
  const RevenueOverviewBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(revenueOverviewProvider);
    final pending = ref.watch(revenuePendingProvider);
    final view = ref.watch(revenueViewControllerProvider);
    final controller = ref.read(revenueViewControllerProvider.notifier);

    void openEntry(RevenueEntry entry) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TransactionDetailsPage(entry: entry),
        ),
      );
    }

    final collections = overview == null
        ? const CollectionsByDaySkeleton()
        : CollectionsByDayCard(chart: overview.chart);

    final transactions = overview == null
        ? const TransactionsSkeleton()
        : TransactionsCard(
            rows: overview.transactions,
            filter: view.filter,
            expanded: view.expanded,
            todayIn: overview.todayIn,
            todayOut: overview.todayOut,
            onFilter: controller.setFilter,
            onToggleExpanded: controller.toggleExpanded,
            onOpen: openEntry,
          );

    final pendingCard = pending == null
        ? const PendingPaymentsSkeleton()
        : PendingPaymentsCard(
            groups: pending,
            onMarkPaid: (g) => PendingActions.markPaid(context, ref, g),
            onSendReminders: () => PendingActions.sendReminders(context, pending),
          );

    final wide = MediaQuery.sizeOf(context).width >= CruBreakpoint.splitPane;

    final Widget columns = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    collections,
                    const SizedBox(height: CruSpace.cardGap),
                    transactions,
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.cardGap),
              SizedBox(width: CruSize.rightColumn, child: pendingCard),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              collections,
              const SizedBox(height: CruSpace.cardGap),
              transactions,
              const SizedBox(height: CruSpace.cardGap),
              pendingCard,
            ],
          );

    return SingleChildScrollView(
      primary: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RevenueGlance(overview: overview, pending: pending),
          const SizedBox(height: CruSpace.cardGap),
          columns,
        ],
      ),
    );
  }
}
