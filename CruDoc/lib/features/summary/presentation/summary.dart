import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,   // global gradient shows through
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Summary',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              _PlaceholderCard(
                icon: Icons.chat,
                title: 'WhatsApp Updates',
                subtitle: 'Last sync: --',
                actionText: 'Connect WhatsApp',
              ),
              const SizedBox(height: 16),
              _PlaceholderCard(
                icon: Icons.calendar_month,
                title: 'Calendar',
                subtitle: 'No events synced',
                actionText: 'Sync Calendar',
              ),
              const SizedBox(height: 16),
              _PlaceholderCard(
                icon: Icons.wifi,
                title: 'Connectivity',
                subtitle: 'All services online',
                actionText: 'Check Status',
              ),
              const Spacer(),
              const Center(
                child: Text(
                  'More integrations coming soon',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Reusable Placeholder Card ----------
class _PlaceholderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionText;

  const _PlaceholderCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.beige, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // Placeholder – real integration later
            },
            child: Text(
              actionText,
              style: const TextStyle(
                color: AppColors.beige,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}