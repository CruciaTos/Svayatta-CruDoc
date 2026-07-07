import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

enum VisitMode { home, online }

class TodaysVisitsCard extends StatelessWidget {
  const TodaysVisitsCard({super.key});

  static const List<_TodayVisit> _visits = [
    _TodayVisit(
      patientName: 'Anjali Verma',
      time: '10:30 AM',
      mode: VisitMode.home,
    ),
    _TodayVisit(
      patientName: 'Rohan Deshpande',
      time: '1:00 PM',
      mode: VisitMode.online,
    ),
    _TodayVisit(
      patientName: 'Meera Kulkarni',
      time: '5:30 PM',
      mode: VisitMode.home,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Today's Visits",
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_visits.length} scheduled',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_visits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No visits scheduled for today.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ..._visits.map((v) => _VisitRow(visit: v)),
        ],
      ),
    );
  }
}

class _TodayVisit {
  final String patientName;
  final String time;
  final VisitMode mode;

  const _TodayVisit({
    required this.patientName,
    required this.time,
    required this.mode,
  });
}

class _VisitRow extends StatelessWidget {
  final _TodayVisit visit;
  const _VisitRow({required this.visit});

  @override
  Widget build(BuildContext context) {
    final isHome = visit.mode == VisitMode.home;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.cardSurfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isHome ? Icons.home_outlined : Icons.videocam_outlined,
              color: AppColors.beige,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visit.patientName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isHome ? 'Home visit' : 'Online session',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            visit.time,
            style: const TextStyle(
              color: AppColors.silver,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}