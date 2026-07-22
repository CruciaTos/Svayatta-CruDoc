import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/dashboard/data/models/activity_item.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/recent_activity_provider.dart';

/// Dashboard card showing the most recent patient, visit, inventory, and
/// revenue activity, newest first.
///
/// Initially shows only the top 4 items. Tapping "View all" expands the
/// list to show all activity. Tapping "Show less" collapses it back.
class RecentActivityCard extends ConsumerStatefulWidget {
  const RecentActivityCard({super.key});

  @override
  ConsumerState<RecentActivityCard> createState() => _RecentActivityCardState();
}

class _RecentActivityCardState extends ConsumerState<RecentActivityCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final activityAsync = ref.watch(recentActivityProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Activity',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              // Only show expand/collapse if there are more than 4 items
              activityAsync.whenOrNull(
                data: (items) {
                  if (items.length > 4) {
                    return GestureDetector(
                      onTap: () => setState(() => _showAll = !_showAll),
                      child: Text(
                        _showAll ? 'Show less' : 'View all',
                        style: const TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          color: AppColors.chartBarLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ) ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 14),
          activityAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.slateBlue,
                  ),
                ),
              ),
            ),
            error: (error, stack) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Could not load recent activity.',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No recent activity yet.',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                );
              }

              // Show only the first 4 unless expanded
              final displayedItems = _showAll ? items : items.take(4).toList();

              return Column(
                children: [
                  for (var i = 0; i < displayedItems.length; i++) ...[
                    _ActivityRow(item: displayedItems[i]),
                    if (i != displayedItems.length - 1)
                      const Divider(height: 24, color: Color(0xFFDDE6F0)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final ActivityItem item;
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
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.relativeTime,
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              color: AppColors.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}