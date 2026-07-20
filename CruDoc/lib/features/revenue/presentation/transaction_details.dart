import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';

// ---------- Accent colours ----------
// Matches the red/green used for expense vs income everywhere else in
// the Revenue screen (TransactionTile, the inline list, etc).
const Color _accentRed = Color(0xFFEF5350);
const Color _accentGreen = Color(0xFF2E7D32);

/// Read-only details screen for a single [RevenueEntry].
///
/// Pushed when a row in the "Recent transactions" list is tapped —
/// mirrors [VisitDetailsPage]/[PatientDetailsPage]'s layout (a back
/// bar + a scrollable column of info cards over the shared
/// [ShellBackground]), just without any edit affordances since a
/// transaction record isn't meant to be edited after the fact.
class TransactionDetailsPage extends StatelessWidget {
  final RevenueEntry entry;

  const TransactionDetailsPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ----- Top bar -----
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        'Transaction Details',
                        style: AppColors.pageHeading.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ----- Content -----
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  physics: const ClampingScrollPhysics(),
                  children: [
                    _TransactionHeader(entry: entry),
                    const SizedBox(height: 24),
                    const _SectionLabel(text: 'DETAILS'),
                    const SizedBox(height: 12),
                    _TransactionInfoCard(entry: entry),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppColors.bodySmall.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: AppColors.textSecondary.withValues(alpha: 0.85),
      ),
    );
  }
}

/// Big amount + income/expense badge at the top of the page.
class _TransactionHeader extends StatelessWidget {
  final RevenueEntry entry;
  const _TransactionHeader({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isExpense = entry.kind == TransactionKind.expense;
    final amountColor = isExpense ? _accentRed : _accentGreen;
    final amountPrefix = isExpense ? '−' : '+';

    final IconData icon;
    final Color avatarBackground;
    final Color iconColor;
    if (isExpense) {
      icon = Icons.money_off;
      avatarBackground = _accentRed.withValues(alpha: 0.15);
      iconColor = _accentRed;
    } else {
      switch (entry.type) {
        case RevenueType.visit:
          icon = Icons.medical_services;
          break;
        case RevenueType.online:
          icon = Icons.videocam;
          break;
        case RevenueType.miscellaneous:
          icon = Icons.miscellaneous_services;
          break;
      }
      avatarBackground = AppColors.chartBarDim;
      iconColor = Colors.white;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: avatarBackground,
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$amountPrefix₹${entry.amount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: amountColor,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: amountColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: amountColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  isExpense ? 'Expense' : 'Income',
                  style: AppColors.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The four fields the person asked for: who it was paid to, the
/// date, the day of the week, and the payment note.
class _TransactionInfoCard extends StatelessWidget {
  final RevenueEntry entry;
  const _TransactionInfoCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isExpense = entry.kind == TransactionKind.expense;
    final dateStr = DateFormat('d MMM yyyy').format(entry.date);
    final dayStr = DateFormat('EEEE').format(entry.date);
    final hasPayer = entry.payer?.trim().isNotEmpty ?? false;
    final hasNote = entry.description.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            icon: Icons.person_outline,
            // "Paid To" for money going out, "Received From" for money
            // coming in — same underlying `payer` field either way.
            label: isExpense ? 'Paid To' : 'Received From',
            value: hasPayer ? entry.payer! : 'Not specified',
          ),
          const _InfoDivider(),
          _InfoRow(
            icon: Icons.calendar_today,
            label: 'Date',
            value: dateStr,
          ),
          const _InfoDivider(),
          _InfoRow(
            icon: Icons.event_note,
            label: 'Day',
            value: dayStr,
          ),
          const _InfoDivider(),
          _InfoRow(
            icon: Icons.sticky_note_2_outlined,
            label: 'Payment Note',
            value: hasNote ? entry.description : 'No note added',
          ),
        ],
      ),
    );
  }
}

class _InfoDivider extends StatelessWidget {
  const _InfoDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.black.withValues(alpha: 0.06),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.silver),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppColors.bodySmall),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppColors.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}