import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_add_transaction_dialog.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_invoices_screen.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_header.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_overview_body.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Revenue tab (design/clinic-redesign/screens/revenue.png).
///
/// Pads itself with [CruSpace.mainPadding]; the shell doesn't. The
/// Expenses section from the design has no screen behind it (GAP), so
/// only Overview and Invoices are offered.
class RevenueOverviewScreen extends ConsumerStatefulWidget {
  const RevenueOverviewScreen({super.key});

  @override
  ConsumerState<RevenueOverviewScreen> createState() =>
      _RevenueOverviewScreenState();
}

class _RevenueOverviewScreenState extends ConsumerState<RevenueOverviewScreen> {
  Future<void> _record(TransactionKind kind) async {
    await showDesktopAddTransactionDialog(context, initialKind: kind);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(revenueViewControllerProvider);
    final controller = ref.read(revenueViewControllerProvider.notifier);
    final subtitle = ref.watch(
      revenueOverviewProvider.select((o) => o?.subtitle),
    );

    return Padding(
      padding: CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RevenueHeader(
            subtitle: view.tab == RevenueTab.invoices
                ? 'Invoices and bills'
                : subtitle,
            onRecordExpense: () => _record(TransactionKind.expense),
            onRecordPayment: () => _record(TransactionKind.income),
          ),
          const SizedBox(height: CruSpace.cardGap),
          RevenueControls(
            tab: view.tab,
            period: view.period,
            onTab: controller.setTab,
            onPeriod: controller.setPeriod,
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: AnimatedSwitcher(
              duration: CruMotion.of(context, CruMotion.fast),
              switchInCurve: CruMotion.curve,
              switchOutCurve: CruMotion.curve,
              // Fill the space so the Overview stays top-aligned.
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: view.tab == RevenueTab.overview
                  ? const RevenueOverviewBody(key: ValueKey('overview'))
                  : const DesktopInvoicesScreen(
                      key: ValueKey('invoices'),
                      isSubScreen: true,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
