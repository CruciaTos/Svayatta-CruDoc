import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/dashboard/data/models/activity_item.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/recent_activity_provider.dart';

/// Displays the doctor's recent activity logs using real data from [recentActivityProvider].
class ActivityLogsWidget extends ConsumerWidget {
  const ActivityLogsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(recentActivityProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                'Activity Logs',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              activityAsync.whenOrNull(
                data: (items) => items.isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3F51B5).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${items.length} events',
                          style: const TextStyle(
                            color: Color(0xFF3F51B5),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : null,
              ) ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 12),
          activityAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF3F51B5),
                  ),
                ),
              ),
            ),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Could not load activity logs.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    'No recent activity recorded.',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                );
              }

              final displayItems = items.take(5).toList();

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayItems.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 16,
                  color: Color(0xFFF1F5F9),
                ),
                itemBuilder: (context, index) {
                  return _LogItem(item: displayItems[index]);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LogItem extends StatelessWidget {
  final ActivityItem item;

  const _LogItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF3F51B5).withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            item.icon,
            size: 14,
            color: const Color(0xFF3F51B5),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            item.text,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          item.relativeTime,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}