import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:intl/intl.dart';

/// A single row inside the "Recent transactions" list.
///
/// Shows a coloured avatar (red for expense, blue for income),
/// description, date, and a prefixed amount with appropriate colour.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.entry,
    this.onTap,
  });

  final RevenueEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isExpense = entry.kind == TransactionKind.expense;

    // ---- icon & avatar colours ----
    final IconData icon;
    final Color avatarBackground;
    final Color iconColor;
    if (isExpense) {
      icon = Icons.money_off;
      avatarBackground = AppColors.negativeRed.withValues(alpha: 0.15);
      iconColor = AppColors.negativeRed;
    } else {
      // Original type‑based icon for income entries
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

    // ---- amount text styling ----
    final amountColor = isExpense
        ? AppColors.negativeRed
        : const Color(0xFF2E7D32); // existing green
    final amountPrefix = isExpense ? '−' : '+';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: avatarBackground,
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.description,
                    style: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.yMMMd().format(entry.date),
                    style: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$amountPrefix₹${entry.amount.toStringAsFixed(0)}',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: amountColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}