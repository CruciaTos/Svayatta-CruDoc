import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/core/services/maps_key.dart';

/// Static map image size (Google Static Maps: 640 px max, scale 2).
const int kHomeMapWidth = 640;
const int kHomeMapHeight = 480;

/// A home visit's position: coordinates when the address was picked from
/// the suggestions, otherwise the typed address. Null when there is
/// neither.
String? homeVisitPlace(Visit v) {
  if (v.latitude != null && v.longitude != null) {
    return '${v.latitude},${v.longitude}';
  }
  final address = v.address.trim();
  return address.isEmpty || address == 'Clinic' ? null : address;
}

/// Directions to one home visit: its saved Maps link, else Google Maps
/// directions to its place. Null when there is nothing to go on.
Uri? homeVisitDirections(Visit v) {
  final link = v.mapsLink?.trim();
  if (link != null && link.isNotEmpty) return Uri.tryParse(link);
  final place = homeVisitPlace(v);
  if (place == null) return null;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': place,
    'travelmode': 'driving',
  });
}

/// Google Maps directions through [stops] in order, from wherever the
/// doctor is now. Null when no stop has a place.
Uri? homeVisitRoute(List<ApptItem> stops) {
  final places = [for (final s in stops) ?homeVisitPlace(s.visit)];
  if (places.isEmpty) return null;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': places.last,
    if (places.length > 1)
      'waypoints': places.sublist(0, places.length - 1).join('|'),
    'travelmode': 'driving',
  });
}

/// A Static Maps image of [stops] with numbered markers, joined in visit
/// order when there is more than one. Null without an API key or without
/// any coordinates.
String? homeVisitMapUrl(List<ApptItem> stops) {
  if (!MapsKey.isSet) return null;
  final hex = (CruBrand.ink600.toARGB32() & 0xFFFFFF)
      .toRadixString(16)
      .padLeft(6, '0');
  final points = <(int, double, double)>[
    for (var i = 0; i < stops.length; i++)
      if (stops[i].visit.latitude != null && stops[i].visit.longitude != null)
        (i + 1, stops[i].visit.latitude!, stops[i].visit.longitude!),
  ];
  if (points.isEmpty) return null;
  final b = StringBuffer(
    'https://maps.googleapis.com/maps/api/staticmap'
    '?size=${kHomeMapWidth}x$kHomeMapHeight&scale=2',
  );
  final single = points.length == 1;
  for (final (n, lat, lng) in points) {
    // Marker labels are one character: 1 to 9 get a number.
    final label = !single && n <= 9 ? '%7Clabel:$n' : '';
    b.write('&markers=color:0x$hex$label%7C$lat,$lng');
  }
  if (single) {
    b.write('&zoom=15');
  } else {
    b.write('&path=color:0x${hex}CC%7Cweight:3');
    for (final (_, lat, lng) in points) {
      b.write('%7C$lat,$lng');
    }
  }
  b.write('&key=${MapsKey.value}');
  return b.toString();
}

/// Opens [uri] in the browser or the Maps app.
Future<void> openHomeVisitLink(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
