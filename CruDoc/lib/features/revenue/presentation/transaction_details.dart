import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Read-only details screen for a single [RevenueEntry].
///
/// Pushed when a transaction row is tapped (desktop Revenue Overview and
/// the mobile revenue list). A back bar over a scrollable column of
/// on-token cards, with no edit affordances: a transaction record isn't
/// meant to be edited after the fact.
class TransactionDetailsPage extends StatelessWidget {
  final RevenueEntry entry;

  const TransactionDetailsPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ----- Top bar -----
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s16,
                CruSpace.s12,
                CruSpace.s16,
                CruSpace.s4,
              ),
              child: Row(
                children: [
                  CruSquareButton(
                    icon: CruIcons.chevronLeft,
                    semanticLabel: 'Back',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Transaction details',
                        style: CruType.title2.tint(c.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ----- Content -----
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      CruSpace.s16,
                      CruSpace.s12,
                      CruSpace.s16,
                      CruSpace.s24,
                    ),
                    physics: const ClampingScrollPhysics(),
                    children: [
                      _TransactionHeader(entry: entry),
                      const SizedBox(height: CruSpace.s20),
                      _TransactionInfoCard(entry: entry),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Amount with a Money in / Money out pill.
class _TransactionHeader extends StatelessWidget {
  final RevenueEntry entry;
  const _TransactionHeader({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final isExpense = entry.kind == TransactionKind.expense;
    final amount = DashFormat.rupees(entry.amount);

    return CruCard(
      semanticLabel: 'Transaction',
      padding: const EdgeInsets.all(CruSpace.s20),
      child: Row(
        children: [
          CruIconTile(
            icon: isExpense ? RevenueIcons.receipt : CruIcons.rupee,
            tone: CruTileTone.accent,
          ),
          const SizedBox(width: CruSpace.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isExpense ? '−$amount' : '+$amount',
                  style: CruType.amount
                      .tint(isExpense ? c.redText : c.greenText),
                ),
                const SizedBox(height: CruSpace.s8),
                CruPill(
                  text: isExpense ? 'Money out' : 'Money in',
                  background: isExpense ? c.redTint : c.greenTint,
                  foreground: isExpense ? c.redText : c.greenText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Who it was paid to (or received from), the date, the day of the
/// week, and the payment note.
class _TransactionInfoCard extends StatelessWidget {
  final RevenueEntry entry;
  const _TransactionInfoCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isExpense = entry.kind == TransactionKind.expense;
    final dateStr = DateFormat('d MMMM y').format(entry.date);
    final dayStr = DateFormat('EEEE').format(entry.date);
    final hasPayer = entry.payer?.trim().isNotEmpty ?? false;
    final hasNote = entry.description.trim().isNotEmpty;

    return CruCard(
      semanticLabel: 'Details',
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s20,
        vertical: CruSpace.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow(
            icon: CruIcons.patients,
            // "Paid to" for money going out, "Received from" for money
            // coming in: the same underlying `payer` field either way.
            label: isExpense ? 'Paid to' : 'Received from',
            value: hasPayer ? entry.payer! : 'Not specified',
            quiet: !hasPayer,
          ),
          const CruSeparator(indent: _infoTextInset),
          _InfoRow(
            icon: CruIcons.calendar,
            label: 'Date',
            value: dateStr,
          ),
          const CruSeparator(indent: _infoTextInset),
          _InfoRow(
            icon: CruIcons.clock,
            label: 'Day',
            value: dayStr,
          ),
          const CruSeparator(indent: _infoTextInset),
          _InfoRow(
            icon: CruIcons.pen,
            label: 'Payment note',
            value: hasNote ? entry.description : 'No note added',
            quiet: !hasNote,
          ),
        ],
      ),
    );
  }
}

/// Keeps the cards readable on a wide desktop window. Not a token yet;
/// see NEEDS.md (Builder 4).
const double _maxContentWidth = 640;

/// Icon 18 + gap 12.
const double _infoIcon = 18;
const double _infoTextInset = _infoIcon + CruSpace.s12;

class _InfoRow extends StatelessWidget {
  final CruIconData icon;
  final String label;
  final String value;
  final bool quiet;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.quiet = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: CruSpace.s2),
            child: CruIcon(icon, size: _infoIcon, color: c.label3),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: CruType.subhead.w500.tint(c.label2)),
                const SizedBox(height: CruSpace.s2),
                Text(
                  value,
                  style: (quiet ? CruType.text : CruType.callout)
                      .tabular
                      .tint(quiet ? c.label3 : c.label),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
