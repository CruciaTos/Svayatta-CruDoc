import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/dashboard/data/models/activity_item.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/recent_activity_provider.dart';

/// Dashboard card showing the most recent patient, visit, inventory, and
/// revenue activity in chronological order (newest first).
///
/// Compact and proportionally sized to avoid bottom screen clipping.
class RecentActivityCard extends ConsumerStatefulWidget {
  const RecentActivityCard({super.key});

  @override
  ConsumerState<RecentActivityCard> createState() => _RecentActivityCardState();
}

class _RecentActivityCardState extends ConsumerState<RecentActivityCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activityAsync = ref.watch(recentActivityProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.8),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ===================================================================
          // 1. FIXED CARD HEADER (Title + Activity Count Badge)
          // ===================================================================
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.chartBarLight.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      size: 16,
                      color: AppColors.chartBarLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              activityAsync.whenOrNull(
                data: (items) {
                  if (items.isNotEmpty) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.chartBarLight.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${items.length} updates',
                        style: const TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          color: AppColors.chartBarLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ) ??
                  const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 8),

          // ===================================================================
          // 2. SCROLLABLE INTERNAL ACTIVITY FEED
          // ===================================================================
          activityAsync.when(
            loading: () => const SizedBox(
              height: 120,
              child: Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.chartBarLight,
                  ),
                ),
              ),
            ),
            error: (error, stack) => const SizedBox(
              height: 70,
              child: Center(
                child: Text(
                  'Could not load recent activity.',
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const SizedBox(
                  height: 80,
                  child: Center(
                    child: Text(
                      'No recent activity yet.',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 175, // Generously sized scroll viewport to eliminate extra empty space
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: false,
                  radius: const Radius.circular(4),
                  thickness: 3.5,
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    physics: const BouncingScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 14,
                      thickness: 0.7,
                      color: Color(0xFFE8EEF5),
                    ),
                    itemBuilder: (context, index) {
                      return _ActivityRow(item: items[index]);
                    },
                  ),
                ),
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
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(5.5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Icon(
              item.icon,
              color: AppColors.slateBlue,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            item.relativeTime,
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              color: AppColors.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}