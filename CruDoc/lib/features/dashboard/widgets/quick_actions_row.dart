import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  static const List<_QuickAction> _actions = [
    _QuickAction(icon: Icons.calendar_today_outlined, label: 'New Visit'),
    _QuickAction(icon: Icons.description_outlined, label: 'New Invoice'),
    _QuickAction(icon: Icons.person_add, label: 'Add Patient'),
    _QuickAction(icon: Icons.remove_circle_outline, label: 'Log Expense'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _actions
          .map(
            (action) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _ActionButton(action: action),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  const _QuickAction({required this.icon, required this.label});
}

class _ActionButton extends StatelessWidget {
  final _QuickAction action;
  const _ActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        // Placeholder — will route to the real flow once go_router lands.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${action.label} — coming soon')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(action.icon, color: AppColors.beige, size: 20),
            const SizedBox(height: 6),
            Text(
              action.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}