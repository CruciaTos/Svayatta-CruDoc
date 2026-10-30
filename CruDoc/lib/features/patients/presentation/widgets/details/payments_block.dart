import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_billing_provider.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/pending_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The package panel (inset, radius 12): balance, what is due, and
/// Record payment. The amount paid and the package total are GAPs, so
/// the paid bar and "₹paid paid" are not shown.
class PackageBalancePanel extends StatelessWidget {
  const PackageBalancePanel({
    super.key,
    required this.summary,
    required this.onRecordPayment,
  });

  final PatientSummary summary;
  final VoidCallback onRecordPayment;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final balance = summary.balance;
    final due = summary.hasBalance;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s18,
        vertical: CruSpace.s16,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        'Package balance',
                        style: CruType.subhead.w500.tint(c.label2),
                      ),
                    ),
                    Text(
                      PatientFormat.rupees(balance),
                      style: CruType.row.tabular.tint(c.label),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s8),
                if (due)
                  Text(
                    '${PatientFormat.rupees(balance)} due',
                    style: CruType.subhead.w600.tabular.tint(c.amberText),
                  )
                else
                  const _NothingDue(),
              ],
            ),
          ),
          if (due) ...[
            const SizedBox(width: CruSpace.s20),
            CruCapsuleButton(
              label: 'Record payment',
              kind: CruCapsuleKind.surface,
              height: CruSize.panelCapsule,
              semanticLabel: 'Record a payment from ${summary.name}',
              onPressed: onRecordPayment,
            ),
          ],
        ],
      ),
    );
  }
}

/// Payments on the Overview: what is owed, one line per kind (package
/// balance, unpaid fees, open bills), Record payment while the package
/// has a balance, and the way to the Payments tab.
class PaymentsSummaryCard extends ConsumerWidget {
  const PaymentsSummaryCard({
    super.key,
    required this.summary,
    required this.onRecordPayment,
    required this.onSeeAll,
    this.showBills = true,
  });

  final PatientSummary summary;
  final VoidCallback onRecordPayment;
  final VoidCallback onSeeAll;

  /// Open bills (billing roles only).
  final bool showBills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final billing = ref.watch(patientBillingProvider(summary.id));
    final unpaid = billing.unpaid ?? const [];
    final open = showBills ? billing.openBills : const <PatientBill>[];
    final lines = <(String, double)>[
      if (summary.hasBalance) ('Package balance', summary.balance),
      if (unpaid.isNotEmpty)
        (DashFormat.plural(unpaid.length, 'unpaid fee'), billing.unpaidTotal),
      if (open.isNotEmpty)
        (
          '${DashFormat.plural(open.length, 'bill')} not fully paid',
          billing.openBillsTotal,
        ),
    ];
    return CruCard(
      semanticLabel: 'Payments',
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailsCardHeader(
            title: 'Payments',
            onTap: onSeeAll,
            morphId: 'title',
            trailing: summary.hasBalance
                ? CruCapsuleButton(
                    label: 'Record payment',
                    semanticLabel: 'Record a payment from ${summary.name}',
                    onPressed: onRecordPayment,
                  )
                : null,
          ),
          const SizedBox(height: CruSpace.s12),
          if (lines.isEmpty)
            const _NothingDue()
          else
            for (final (label, amount) in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label, style: CruType.text.tint(c.label2)),
                    ),
                    const SizedBox(width: CruSpace.s12),
                    Text(
                      '${PatientFormat.rupees(amount)} due',
                      style: CruType.text.w600.tabular.tint(c.amberText),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: CruSpace.s10),
          Align(
            alignment: Alignment.centerLeft,
            child: CruLink(label: 'See all payments', onPressed: onSeeAll),
          ),
        ],
      ),
    );
  }
}

/// The Payments tab: what is owed (package balance with Record payment,
/// unpaid fees with Mark paid), the patient's bills (New bill; a bill
/// opens on tap) and the payments received. Bills and payments received
/// are for billing roles ([showRecords]).
class PaymentsTab extends ConsumerWidget {
  const PaymentsTab({
    super.key,
    required this.summary,
    required this.wide,
    required this.onRecordPayment,
    required this.onNewBill,
    this.showRecords = true,
  });

  final PatientSummary summary;

  /// Two columns.
  final bool wide;
  final VoidCallback onRecordPayment;

  /// Null hides New bill.
  final VoidCallback? onNewBill;
  final bool showRecords;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billing = ref.watch(patientBillingProvider(summary.id));
    final due = _DueCard(
      summary: summary,
      billing: billing,
      onRecordPayment: onRecordPayment,
    );
    if (!showRecords) return due;
    final bills = _BillsCard(billing: billing, onNewBill: onNewBill);
    final received = _ReceivedCard(billing: billing);
    if (!wide) return DetailsStack([due, bills, received]);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: DetailsStack([due, bills])),
        const SizedBox(width: CruSpace.cardGap),
        SizedBox(width: CruSize.rightColumn, child: received),
      ],
    );
  }
}

/// "Nothing due" in green.
class _NothingDue extends StatelessWidget {
  const _NothingDue();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        CruIcon(CruIcons.check, size: 15, strokeWidth: 2.4, color: c.greenText),
        const SizedBox(width: CruSpace.s4),
        Text('Nothing due', style: CruType.subhead.w600.tint(c.greenText)),
      ],
    );
  }
}

/// What the patient owes: the package balance and fees not yet paid.
class _DueCard extends ConsumerWidget {
  const _DueCard({
    required this.summary,
    required this.billing,
    required this.onRecordPayment,
  });

  final PatientSummary summary;
  final PatientBilling billing;
  final VoidCallback onRecordPayment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unpaid = billing.unpaid ?? const [];
    final now = ref.watch(dashboardNowProvider);
    return CruCard(
      semanticLabel: 'Due',
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DetailsCardHeader(title: 'Due'),
          ),
          if (summary.hasBalance)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: PackageBalancePanel(
                summary: summary,
                onRecordPayment: onRecordPayment,
              ),
            ),
          if (unpaid.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  const Expanded(child: DetailsSectionLabel('Unpaid fees')),
                  CruCapsuleButton(
                    label: 'Mark paid',
                    semanticLabel:
                        'Mark ${PatientFormat.rupees(billing.unpaidTotal)} '
                        'as paid',
                    onPressed: () {
                      final group = RevenueBuilder.pendingGroups(unpaid, [
                        summary.patient,
                      ], now).firstOrNull;
                      if (group != null) {
                        PendingActions.markPaid(context, ref, group);
                      }
                    },
                  ),
                ],
              ),
            ),
            for (final p in unpaid)
              _MoneyRow(
                title: p.description.trim().isEmpty
                    ? 'Fee'
                    : p.description.trim(),
                subtitle: PatientFormat.weekdayDate(p.date),
                amount: p.amount,
                tone: _MoneyTone.due,
              ),
          ],
          if (!summary.hasBalance && unpaid.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _NothingDue(),
            ),
          if (billing.unpaid == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: SkeletonBox(width: 200, height: 12),
            ),
        ],
      ),
    );
  }
}

/// The patient's bills, newest first. A bill opens on tap.
class _BillsCard extends StatelessWidget {
  const _BillsCard({required this.billing, required this.onNewBill});

  final PatientBilling billing;
  final VoidCallback? onNewBill;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final bills = billing.bills;
    return CruCard(
      semanticLabel: 'Bills',
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: DetailsCardHeader(
              title: 'Bills',
              trailing: onNewBill == null
                  ? null
                  : CruCapsuleButton(label: 'New bill', onPressed: onNewBill),
            ),
          ),
          if (bills == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: SkeletonBox(width: 200, height: 12),
            )
          else if (bills.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Text('No bills yet.', style: CruType.text.tint(c.label2)),
            )
          else
            for (var i = 0; i < bills.length; i++) ...[
              if (i > 0)
                const CruSeparator(indent: CruSpace.s12, endIndent: CruSpace.s12),
              _BillRow(bill: bills[i]),
            ],
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.bill});

  final PatientBill bill;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final inv = bill.invoice;
    final number = inv.invoiceNumber.trim();
    final service = inv.service.trim();
    final (String status, Color color) = inv.isCancelled
        ? ('Cancelled', c.label3)
        : bill.balance <= 0
        ? ('Paid', c.greenText)
        : bill.partPaid
        ? ('${PatientFormat.rupees(bill.balance)} due', c.amberText)
        : (inv.isOverdue ? 'Overdue' : 'Not paid', c.amberText);
    return _MoneyRow(
      title: number.isEmpty ? 'Bill' : 'Bill $number',
      subtitle: [
        PatientFormat.weekdayDate(inv.date),
        if (service.isNotEmpty) service,
      ].join(' · '),
      amount: inv.amount,
      status: status,
      statusColor: color,
      onTap: () => showDesktopCreateInvoiceDialog(context, initialInvoice: inv),
    );
  }
}

/// Payments received, newest first.
class _ReceivedCard extends StatelessWidget {
  const _ReceivedCard({required this.billing});

  final PatientBilling billing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final received = billing.received;
    final total = (received ?? const <RevenueEntry>[]).fold<double>(
      0,
      (s, e) => s + e.amount,
    );
    return CruCard(
      semanticLabel: 'Received',
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: DetailsCardHeader(
              title: 'Received',
              trailing: total > 0
                  ? Text(
                      PatientFormat.rupees(total),
                      style: CruType.subhead.w600.tabular.tint(c.greenText),
                    )
                  : null,
            ),
          ),
          if (received == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: SkeletonBox(width: 200, height: 12),
            )
          else if (received.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Text(
                'No payments recorded yet.',
                style: CruType.text.tint(c.label2),
              ),
            )
          else
            for (var i = 0; i < received.length; i++) ...[
              if (i > 0)
                const CruSeparator(indent: CruSpace.s12, endIndent: CruSpace.s12),
              _MoneyRow(
                title: received[i].description.trim().isEmpty
                    ? 'Payment'
                    : received[i].description.trim(),
                subtitle: PatientFormat.weekdayDate(received[i].date),
                amount: received[i].amount,
                tone: _MoneyTone.received,
              ),
            ],
        ],
      ),
    );
  }
}

enum _MoneyTone { plain, due, received }

/// Title and date on the left; the amount (and a status) on the right.
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.title,
    required this.subtitle,
    required this.amount,
    this.tone = _MoneyTone.plain,
    this.status,
    this.statusColor,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final double amount;
  final _MoneyTone tone;
  final String? status;
  final Color? statusColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final amountColor = switch (tone) {
      _MoneyTone.plain => c.label,
      _MoneyTone.due => c.amberText,
      _MoneyTone.received => c.greenText,
    };
    Widget body(bool hovered) => AnimatedContainer(
      duration: CruMotion.of(context, CruMotion.fast),
      curve: CruMotion.curve,
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s12,
        vertical: CruSpace.s10,
      ),
      decoration: ShapeDecoration(
        color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: CruType.callout.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: CruType.subhead.tabular.tint(c.label2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                PatientFormat.rupees(amount),
                style: CruType.callout.w600.tabular.tint(amountColor),
              ),
              if (status != null)
                Text(
                  status!,
                  style: CruType.subhead.tabular.tint(statusColor ?? c.label2),
                ),
            ],
          ),
        ],
      ),
    );
    final tap = onTap;
    if (tap == null) return body(false);
    return CruPressable(
      onTap: tap,
      scaleOnPress: false,
      semanticLabel: '$title, ${PatientFormat.rupees(amount)}',
      builder: (context, hovered) => body(hovered),
    );
  }
}
