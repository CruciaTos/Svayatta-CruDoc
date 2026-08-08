import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart'
    show staticMapUrlFor;

/// Whether the current platform supports the native `GoogleMap` widget.
///
/// `google_maps_flutter` works on Android, iOS, and Web. Desktop
/// platforms (Windows, macOS, Linux) are not supported — we fall back
/// to a clickable Static Maps image there.
bool get _supportsEmbeddedMap {
  if (kIsWeb) return true; // google_maps_flutter_web
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return false;
  }
}

/// A platform-aware map widget for displaying a visit's location.
///
/// - **Android / iOS / Web**: Renders an interactive [GoogleMap] with a
///   red marker at [latitude], [longitude].
/// - **Windows / macOS / Linux**: Falls back to a [CachedNetworkImage]
///   showing the Google Static Maps preview, tappable to open in browser.
///
/// If [latitude] or [longitude] is null, shows a placeholder with an
/// icon and "No location available" text — never crashes.
///
/// [height] controls the widget's height. Defaults to 180.
class VisitLocationMap extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  final double height;

  /// Called when the user taps the static map fallback (desktop) or the
  /// "Open in Maps" overlay button. The caller should launch the Maps
  /// URL via `url_launcher`.
  final VoidCallback? onOpenMaps;

  /// If true, the map is non-interactive (no pan/zoom/tilt) — useful
  /// inside bottom sheets and cards where gestures conflict with the
  /// parent scroll. Defaults to false (fully interactive).
  final bool lite;

  const VisitLocationMap({
    super.key,
    required this.latitude,
    required this.longitude,
    this.height = 180,
    this.onOpenMaps,
    this.lite = false,
  });

  @override
  Widget build(BuildContext context) {
    if (latitude == null || longitude == null) {
      return _placeholder();
    }

    if (_supportsEmbeddedMap) {
      return _embeddedMap();
    }

    return _staticMapFallback();
  }

  Widget _placeholder() {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_outlined,
              size: 32,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'No location available',
              style: AppColors.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _embeddedMap() {
    final position = LatLng(latitude!, longitude!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: position,
                zoom: 15,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('visit_location'),
                  position: position,
                ),
              },
              // Lite mode: disable all interactions so the map doesn't
              // steal gestures from the parent scroll.
              scrollGesturesEnabled: !lite,
              zoomGesturesEnabled: !lite,
              tiltGesturesEnabled: false,
              rotateGesturesEnabled: false,
              zoomControlsEnabled: !lite,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              liteModeEnabled: lite && defaultTargetPlatform == TargetPlatform.android,
            ),
            // Overlay "Open in Maps" button in the top-right corner.
            if (onOpenMaps != null)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  elevation: 2,
                  child: InkWell(
                    onTap: onOpenMaps,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: AppColors.slateBlue,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _staticMapFallback() {
    final url = staticMapUrlFor(latitude: latitude, longitude: longitude);
    if (url == null) return _placeholder();

    return GestureDetector(
      onTap: onOpenMaps,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: AppColors.cardSurface,
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (_, _, _) => Container(
                  color: AppColors.cardSurface,
                  child: const Center(
                    child: Icon(
                      Icons.map_outlined,
                      color: AppColors.silver,
                      size: 32,
                    ),
                  ),
                ),
              ),
              // Semi-transparent overlay with "Open in Maps" label.
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        Icons.open_in_new,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Open in Google Maps',
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
