import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart'
    show staticMapUrlFor;

const String _defaultMapAsset = 'assets/images/default_map.png';
const String _visitsHeadingFontFamily = 'PlusJakartaSans';

class VisitCard extends StatelessWidget {
  final String patientName;
  final String date;
  final String day;
  final String time;
  final String duration;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? mapsLink;
  final void Function(String url) onMapTap;

  const VisitCard({
    super.key,
    required this.patientName,
    required this.date,
    required this.day,
    required this.time,
    required this.duration,
    required this.address,
    this.latitude,
    this.longitude,
    this.mapsLink,
    required this.onMapTap,
  });

  /// Resolves where "open in maps" should go.
  String get _destinationUrl {
    final link = mapsLink?.trim();
    if (link != null && link.isNotEmpty) {
      return (link.startsWith('http://') || link.startsWith('https://'))
          ? link
          : 'https://$link';
    }
    final query = (latitude != null && longitude != null)
        ? '$latitude,$longitude'
        : address;
    return 'https://www.google.com/maps/search/?api=1'
        '&query=${Uri.encodeComponent(query)}';
  }

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
                fontFamily: _visitsHeadingFontFamily,
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
                const Icon(Icons.calendar_today, size: 16, color: Colors.black),
                const SizedBox(width: 4),
                Text(
                  '$date  •  $day',
                  style: const TextStyle(
                      color: Color.fromARGB(255, 52, 52, 52), fontSize: 13),
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
                const Icon(Icons.access_time, size: 16, color: Colors.black),
                const SizedBox(width: 6),
                Text(
                  '$time  •  $duration',
                  style: const TextStyle(
                      color: Color.fromARGB(255, 52, 52, 52), fontSize: 13),
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
                const Icon(Icons.location_on, size: 16, color: Colors.black),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    address,
                    style: const TextStyle(
                        color: Color.fromARGB(255, 52, 52, 52), fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // --- Map preview / open-in-maps button ---
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: GestureDetector(
              onTap: () => onMapTap(_destinationUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: SizedBox(
                  height: 120,
                  child: Stack(
                    children: [
                      // Map content (image or placeholder + overlay)
                      _buildMapContent(),
                      // Black border on top for crisp corners
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.black,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the map preview content (image or fallback + overlay + texts)
  /// without the border wrapper.
  Widget _buildMapContent() {
    final mapImageUrl = staticMapUrlFor(latitude: latitude, longitude: longitude);
    if (mapImageUrl == null) {
      return _buildMapPlaceholder();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Map image
        CachedNetworkImage(
          imageUrl: mapImageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => const Center(
            child: SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) => _buildMapPlaceholder(),
        ),

        // 30% black overlay (behind the text)
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.3)),
        ),

        // Centered "Tap to open maps" text
        const Center(
          child: Text(
            'Tap to open maps',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(
                  blurRadius: 4,
                  color: Colors.black54,
                ),
              ],
            ),
          ),
        ),

        // "Open in Google Maps" pill (bottom‑right)
        Positioned(
          right: 10,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'Open in Google Maps',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapPlaceholder() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fallback image
        Image.asset(
          _defaultMapAsset,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),

        // 30% black overlay
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.3)),
        ),

        // Centered "Tap to open maps" text (same as above)
        const Center(
          child: Text(
            'Tap to open maps',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(
                  blurRadius: 4,
                  color: Colors.black54,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}