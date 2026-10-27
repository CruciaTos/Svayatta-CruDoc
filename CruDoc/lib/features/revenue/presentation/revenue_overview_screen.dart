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
import 'package:doctor_management_app/shared/widgets/swipe_pages.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';

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
    // Billing staff without revenue see invoices only: no totals or charts.
    final seesRevenue = ref.watch(clinicCanProvider(ClinicPermission.revenue));
    final tab = seesRevenue ? view.tab : RevenueTab.invoices;

    return Padding(
      padding: CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RevenueHeader(
            subtitle: tab == RevenueTab.invoices
                ? 'Invoices and bills'
                : subtitle,
            onRecordExpense: () => _record(TransactionKind.expense),
            onRecordPayment: () => _record(TransactionKind.income),
          ),
          const SizedBox(height: CruSpace.cardGap),
          if (seesRevenue) ...[
            RevenueControls(
              tab: view.tab,
              period: view.period,
              onTab: controller.setTab,
              onPeriod: controller.setPeriod,
            ),
            const SizedBox(height: CruSpace.cardGap),
          ],
          // Overview and Invoices side by side: drag sideways to switch.
          Expanded(
            child: SwipePages<RevenueTab>(
              values: seesRevenue
                  ? RevenueTab.values
                  : const [RevenueTab.invoices],
              value: tab,
              onChanged: controller.setTab,
              builder: (context, t) => t == RevenueTab.overview
                  ? const RevenueOverviewBody()
                  : const DesktopInvoicesScreen(isSubScreen: true),
            ),
          ),
        ],
      ),
    );
  }
}
