import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

class VisitCard extends StatelessWidget {
  final String patientName;
  final String date;
  final String day;
  final String time;
  final String duration;
  final String address;
  final String mapsQuery;
  final void Function(String query) onMapTap;

  const VisitCard({
    super.key,
    required this.patientName,
    required this.date,
    required this.day,
    required this.time,
    required this.duration,
    required this.address,
    required this.mapsQuery,
    required this.onMapTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(36),   // a bit less rounded than before
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            patientName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: AppColors.silver),
              const SizedBox(width: 6),
              Text(
                '$date  •  $day',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.access_time, size: 16, color: AppColors.silver),
              const SizedBox(width: 6),
              Text(
                '$time  •  $duration',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, size: 16, color: AppColors.silver),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  address,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => onMapTap(mapsQuery),
            child: Row(
              children: const [
                Icon(Icons.map, size: 16, color: AppColors.beige),
                SizedBox(width: 6),
                Text(
                  'Open in Google Maps',
                  style: TextStyle(
                    color: AppColors.beige,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}