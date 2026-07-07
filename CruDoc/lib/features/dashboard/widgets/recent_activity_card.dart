import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard({super.key});

  static const List<_ActivityItem> _items = [
    _ActivityItem(
      icon: Icons.check_circle_outline,
      text: 'Invoice INV-2026-0007 marked as paid',
      time: '2h ago',
    ),
    _ActivityItem(
      icon: Icons.person_add,
      text: 'New patient added — Anjali Verma',
      time: 'Yesterday',
    ),
    _ActivityItem(
      icon: Icons.event_busy,
      text: 'Visit with Rohan Deshpande marked missed',
      time: 'Yesterday',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Activity',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ..._items.map((item) => _ActivityRow(item: item)),
        ],
      ),
    );
  }
}

class _ActivityItem {
  final IconData icon;
  final String text;
  final String time;
  const _ActivityItem({
    required this.icon,
    required this.text,
    required this.time,
  });
}

class _ActivityRow extends StatelessWidget {
  final _ActivityItem item;
  const _ActivityRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: AppColors.silver, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.time,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}