import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Where this device is right now, so address search can list the places
/// nearest to the doctor first. Phones and tablets use GPS; a laptop uses
/// Windows location (worked out from nearby Wi-Fi), which needs Location
/// turned on in Windows Settings.
///
/// Returns null when location is off, refused or can't be found in time,
/// so callers fall back to the clinic's address.
class DeviceLocationService {
  DeviceLocationService._();

  static final DeviceLocationService instance = DeviceLocationService._();

  /// A fix this recent is reused instead of asking the device again.
  static const Duration _fresh = Duration(minutes: 5);

  /// How long to wait for a fix before giving up.
  static const Duration _wait = Duration(seconds: 10);

  ({double latitude, double longitude})? _last;
  DateTime? _lastAt;
  Future<({double latitude, double longitude})?>? _pending;

  Future<({double latitude, double longitude})?> current() {
    final last = _last;
    final at = _lastAt;
    if (last != null && at != null && DateTime.now().difference(at) < _fresh) {
      return Future.value(last);
    }
    return _pending ??= _locate().whenComplete(() => _pending = null);
  }

  Future<({double latitude, double longitude})?> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        ).timeout(_wait);
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return null;
      final here = (latitude: position.latitude, longitude: position.longitude);
      _last = here;
      _lastAt = DateTime.now();
      return here;
    } catch (_) {
      return null;
    }
  }
}
