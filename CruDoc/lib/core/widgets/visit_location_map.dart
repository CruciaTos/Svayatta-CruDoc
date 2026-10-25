import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:doctor_management_app/core/services/api_usage_service.dart';
import 'package:doctor_management_app/core/theme/cru_theme.dart';
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
      return _placeholder(context);
    }
    if (_supportsEmbeddedMap) return _embeddedMap(context);
    return _staticMapFallback(context);
  }

  Widget _placeholder(BuildContext context) {
    final c = context.cru;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CruRadius.control),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: CruSpace.s32, color: c.label3),
            const SizedBox(height: CruSpace.s8),
            Text(
              'No location available',
              style: CruType.caption.tint(c.label2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _embeddedMap(BuildContext context) {
    final position = LatLng(latitude!, longitude!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(CruRadius.control),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: position, zoom: 15),
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
              liteModeEnabled:
                  lite && defaultTargetPlatform == TargetPlatform.android,
            ),
            if (onOpenMaps != null)
              Positioned(
                top: CruSpace.s8,
                right: CruSpace.s8,
                child: _OpenInMapsPill(onTap: onOpenMaps),
              ),
          ],
        ),
      ),
    );
  }

  Widget _staticMapFallback(BuildContext context) {
    final c = context.cru;
    final url = staticMapUrlFor(latitude: latitude, longitude: longitude);
    if (url == null) return _placeholder(context);
    ApiUsage.recordOnce(ApiService.maps, url, feature: 'visit_map');

    return GestureDetector(
      onTap: onOpenMaps,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CruRadius.control),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => ColoredBox(
                  color: c.inset,
                  child: Center(
                    child: SizedBox.square(
                      dimension: CruSpace.s24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.accent,
                      ),
                    ),
                  ),
                ),
                errorWidget: (_, _, _) => ColoredBox(
                  color: c.inset,
                  child: Center(
                    child: Icon(
                      Icons.map_outlined,
                      color: c.label3,
                      size: CruSpace.s32,
                    ),
                  ),
                ),
              ),
              if (onOpenMaps != null)
                Positioned(
                  right: CruSpace.s8,
                  bottom: CruSpace.s8,
                  child: _OpenInMapsPill(onTap: onOpenMaps, label: true),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Open in Google Maps" over the map: a surface pill, so it reads the same
/// in Day and Evening whatever the map shows underneath.
class _OpenInMapsPill extends StatelessWidget {
  const _OpenInMapsPill({required this.onTap, this.label = false});

  final VoidCallback? onTap;
  final bool label;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Material(
      color: c.surface,
      shape: StadiumBorder(side: BorderSide(color: c.cardBorder)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label ? CruSpace.s12 : CruSpace.s8,
            vertical: CruSpace.s6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_new, size: CruSpace.s14, color: c.label2),
              if (label) ...[
                const SizedBox(width: CruSpace.s4),
                Text(
                  'Open in Google Maps',
                  style: CruType.caption.w600.tint(c.label),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
