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
      margin: const EdgeInsets.only(bottom: 12),
      height: 280,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(36),
      ),
      child: Stack(
        children: [
          // --- Patient name (top‑left) ---
          Positioned(
            top: 12,
            left: 12,
            child: Text(
              patientName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // --- Date & Day (below name) ---
          Positioned(
            top: 52,
            left: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.black),   // ← icon black
                const SizedBox(width: 4),
                Text(
                  '$date  •  $day',
                  style: const TextStyle(
                      color: Color.fromARGB(255, 52, 52, 52), fontSize: 13),   // ← text light
                ),
              ],
            ),
          ),

          // --- Time & Duration (below date) ---
          Positioned(
            top: 76,
            left: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.black),   // ← icon black
                const SizedBox(width: 6),
                Text(
                  '$time  •  $duration',
                  style: const TextStyle(
                      color: Color.fromARGB(255, 52, 52, 52), fontSize: 13),   // ← text light
                ),
              ],
            ),
          ),

          // --- Address (below time) ---
          Positioned(
            top: 100,
            left: 12,
            right: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.black),   // ← icon black
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    address,
                    style: const TextStyle(
                        color: Color.fromARGB(255, 52, 52, 52), fontSize: 13),   // ← text light
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // --- Map button (unchanged) ---
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: GestureDetector(
              onTap: () => onMapTap(mapsQuery),
              child: Container(
                height: 120,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.cardSurfaceAlt,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppColors.divider,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map_outlined, color: AppColors.beige, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'Tap to open in Google Maps',
                      style: TextStyle(
                        color: AppColors.beige,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}