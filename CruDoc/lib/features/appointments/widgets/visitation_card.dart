import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart'
    show staticMapUrlFor, VisitStatus, VisitType;

const String _defaultMapAsset = 'assets/images/default_map.png';

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

  // --- Phase 3 additions ---
  final VisitStatus status;
  final VisitType visitType;
  final VoidCallback? onTap;
  final VoidCallback? onReschedule;
  final VoidCallback? onMarkCompleted;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

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
    required this.status,
    required this.visitType,
    this.onTap,
    this.onReschedule,
    this.onMarkCompleted,
    this.onCancel,
    this.onDelete,
  });

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
    final hasMenu = onReschedule != null ||
        onMarkCompleted != null ||
        onCancel != null ||
        onDelete != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(minHeight: 240),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(36),
        ),
        // A Column that sizes to its content, rather than a Stack of
        // Positioned children at fixed pixel offsets. Previously the
        // address text (up to 2 lines) and the map preview below it
        // were both pinned to fixed offsets, so a 2-line address was
        // painted over by the map box instead of pushing it down.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Patient name + visit-type badge + status badge + menu ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    patientName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: AppColors.headingFontFamily,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _visitTypeColor(visitType),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _visitTypeIcon(visitType),
                    color: Colors.white,
                    size: 13,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (hasMenu)
                  PopupMenuButton<String>(
                    padding: const EdgeInsets.only(left: 4),
                    icon: const Icon(
                      Icons.more_vert,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    color: AppColors.cardSurface,
                    itemBuilder: (context) => [
                      if (onReschedule != null)
                        const PopupMenuItem(
                          value: 'reschedule',
                          child: Text('Reschedule'),
                        ),
                      if (onMarkCompleted != null)
                        const PopupMenuItem(
                          value: 'complete',
                          child: Text('Mark Completed'),
                        ),
                      if (onCancel != null)
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('Cancel Visit'),
                        ),
                      if (onDelete != null)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete Visit'),
                        ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'reschedule':
                          onReschedule?.call();
                          break;
                        case 'complete':
                          onMarkCompleted?.call();
                          break;
                        case 'cancel':
                          onCancel?.call();
                          break;
                        case 'delete':
                          onDelete?.call();
                          break;
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // --- Date & Day ---
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text('$date  •  $day', style: AppColors.bodyMeta),
              ],
            ),
            const SizedBox(height: 6),

            // --- Time & Duration ---
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.access_time,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text('$time  •  $duration', style: AppColors.bodyMeta),
              ],
            ),
            const SizedBox(height: 6),

            // --- Address — up to 2 lines; the map preview below is a
            // normal flow item, so it's always pushed down below
            // whatever height the address actually needs. ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    address,
                    style: AppColors.bodyMeta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // --- Map preview / open-in-maps button ---
            GestureDetector(
              onTap: () => onMapTap(_destinationUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 110,
                  child: Stack(
                    children: [
                      _buildMapContent(),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.45,
                              ),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Visit type badge helpers ----------
  Color _visitTypeColor(VisitType visitType) {
    switch (visitType) {
      case VisitType.clinic:
        return AppColors.slateBlue;
      case VisitType.home:
        return AppColors.positiveGreen;
    }
  }

  IconData _visitTypeIcon(VisitType visitType) {
    switch (visitType) {
      case VisitType.clinic:
        return Icons.local_hospital;
      case VisitType.home:
        return Icons.home;
    }
  }

  // ---------- Status badge helpers ----------
  Color _statusColor(VisitStatus status) {
    switch (status) {
      case VisitStatus.scheduled:
        return Colors.blue;
      case VisitStatus.completed:
        return Colors.green;
      case VisitStatus.cancelled:
        return Colors.orange;
      case VisitStatus.missed:
        return Colors.red;
    }
  }

  String _statusLabel(VisitStatus status) {
    switch (status) {
      case VisitStatus.scheduled:
        return 'Scheduled';
      case VisitStatus.completed:
        return 'Completed';
      case VisitStatus.cancelled:
        return 'Cancelled';
      case VisitStatus.missed:
        return 'Missed';
    }
  }

  // ---------- Map content (unchanged) ----------
  Widget _buildMapContent() {
    final mapImageUrl = staticMapUrlFor(
      latitude: latitude,
      longitude: longitude,
    );
    if (mapImageUrl == null) {
      return _buildMapPlaceholder();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
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
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.3)),
        ),
        const Center(
          child: Text(
            'Tap to open maps',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
          ),
        ),
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
        Image.asset(
          _defaultMapAsset,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.3)),
        ),
        const Center(
          child: Text(
            'Tap to open maps',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
          ),
        ),
      ],
    );
  }
}