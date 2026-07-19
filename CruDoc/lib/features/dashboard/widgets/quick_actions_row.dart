import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({
    super.key,
    this.onNewVisit,
    this.onNewInvoice,
    this.onAddPatient,
    this.onLogExpense,
  });

  final VoidCallback? onNewVisit;
  final VoidCallback? onNewInvoice;
  final VoidCallback? onAddPatient;
  final VoidCallback? onLogExpense;

  static const List<_QuickAction> _actions = [
    _QuickAction(icon: Icons.calendar_today_outlined, label: 'New Visit'),
    _QuickAction(icon: Icons.description_outlined, label: 'New Invoice'),
    _QuickAction(icon: Icons.person_add, label: 'Add Patient'),
    _QuickAction(icon: Icons.remove_circle_outline, label: 'Log Expense'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 36) / 4;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _actions
              .map(
                (action) => SizedBox(
                  width: itemWidth.clamp(74.0, 120.0),
                  child: _ActionButton(
                    action: action,
                    onTap: _tapHandlerFor(action.label),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  VoidCallback? _tapHandlerFor(String label) {
    switch (label) {
      case 'New Visit':
        return onNewVisit;
      case 'New Invoice':
        return onNewInvoice;
      case 'Add Patient':
        return onAddPatient;
      case 'Log Expense':
        return onLogExpense;
    }
    return null;
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  const _QuickAction({required this.icon, required this.label});
}

class _ActionButton extends StatelessWidget {
  final _QuickAction action;
  final VoidCallback? onTap;

  const _ActionButton({required this.action, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.chartBarLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(action.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              action.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
