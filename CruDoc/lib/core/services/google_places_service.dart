import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;

import 'package:doctor_management_app/core/services/maps_key.dart';

import 'places_service_stub.dart'
    if (dart.library.js) 'places_service_web.dart' as web_impl;

/// A single place suggestion returned by the Google Places Autocomplete API.
class PlacePrediction {
  /// Human-readable full description (e.g. "221B Baker Street, London").
  final String description;

  /// The Place ID used to fetch full details (lat/lng) from the Place
  /// Details endpoint.
  final String placeId;

  /// Structured main text (usually the place/street name) for richer UI
  /// display — e.g. bold the main text and show [secondaryText] dimmer.
  final String mainText;

  /// Structured secondary text (usually city/region/country).
  final String secondaryText;

  /// Straight-line distance from the search's origin (the clinic), when
  /// one was given.
  final int? distanceMeters;

  const PlacePrediction({
    required this.description,
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    this.distanceMeters,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structured =
        json['structured_formatting'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
    return PlacePrediction(
      description: json['description'] as String? ?? '',
      placeId: json['place_id'] as String? ?? '',
      mainText: structured['main_text'] as String? ?? '',
      secondaryText: structured['secondary_text'] as String? ?? '',
    );
  }
}

/// Resolved coordinates from a Place Details call.
class PlaceDetails {
  final double latitude;
  final double longitude;
  final String formattedAddress;

  const PlaceDetails({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
  });
}

/// Thin wrapper around the Google Places Autocomplete and Place Details
/// REST APIs. Uses the same [MapsKey] that the rest of this app uses for
/// Geocoding and Static Maps, keeping credentials in one place.
///
/// Fully updated to use the Google Places API (New) endpoints to support
/// newly created Google Cloud Console projects where the legacy Places API
/// is disabled by default.
class GooglePlacesService {
  GooglePlacesService._();
  static final instance = GooglePlacesService._();

  /// Whether a Google Maps key is known yet ([MapsKey]). Without one there
  /// are no suggestions: the address is typed in full.
  bool get isConfigured => MapsKey.isSet;

  /// How far around the origin to prefer results: a city practice.
  static const double _biasRadiusMeters = 30000;

  /// Real Google Places suggestions for [input], limited to
  /// [countryCode]. With [near] (the clinic), nearby places are preferred
  /// and the list is ordered closest first, each with its distance.
  ///
  /// Returns an empty list with no key, no match or no network. Never
  /// invents suggestions.
  Future<List<PlacePrediction>> autocomplete(
    String input, {
    String countryCode = 'in',
    ({double latitude, double longitude})? near,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return const [];
    final apiKey = await MapsKey.load();
    if (apiKey.isEmpty) return const [];

    if (kIsWeb) return web_impl.getWebAutocomplete(trimmed);

    try {
      final response = await http.post(
        Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
        },
        body: jsonEncode({
          'input': trimmed,
          'includedRegionCodes': [countryCode.toUpperCase()],
          if (near != null) ...{
            'locationBias': {
              'circle': {
                'center': {
                  'latitude': near.latitude,
                  'longitude': near.longitude,
                },
                'radius': _biasRadiusMeters,
              },
            },
            // Makes Google return each place's distance from the clinic.
            'origin': {
              'latitude': near.latitude,
              'longitude': near.longitude,
            },
          },
        }),
      );
      if (response.statusCode != 200) {
        debugPrint(
          'Places autocomplete ${response.statusCode}: ${response.body}',
        );
        return const [];
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = body['suggestions'] as List<dynamic>? ?? const [];
      final list = <PlacePrediction>[];
      for (final suggestion in suggestions) {
        final prediction =
            (suggestion as Map<String, dynamic>)['placePrediction']
                as Map<String, dynamic>?;
        if (prediction == null) continue;
        final structured =
            prediction['structuredFormat'] as Map<String, dynamic>?;
        list.add(PlacePrediction(
          description:
              (prediction['text'] as Map<String, dynamic>?)?['text']
                      as String? ??
                  '',
          placeId: prediction['placeId'] as String? ?? '',
          mainText: (structured?['mainText'] as Map<String, dynamic>?)?['text']
                  as String? ??
              '',
          secondaryText:
              (structured?['secondaryText'] as Map<String, dynamic>?)?['text']
                      as String? ??
                  '',
          distanceMeters: (prediction['distanceMeters'] as num?)?.toInt(),
        ));
      }

      // Closest first; Google's order breaks ties (and places without a
      // distance keep their relevance order, after those with one).
      if (near != null) {
        final ranked = [for (var i = 0; i < list.length; i++) (i, list[i])]
          ..sort((a, b) {
            final da = a.$2.distanceMeters;
            final db = b.$2.distanceMeters;
            if (da != null && db != null && da != db) return da.compareTo(db);
            if (da == null && db != null) return 1;
            if (da != null && db == null) return -1;
            return a.$1.compareTo(b.$1);
          });
        return [for (final r in ranked) r.$2];
      }
      return list;
    } catch (e) {
      debugPrint('Places autocomplete failed: $e');
      return const [];
    }
  }

  final Map<String, ({double latitude, double longitude})?> _geocoded = {};

  /// Coordinates for a typed [address] (Geocoding API), remembered for the
  /// session. Null with no key, no match or no network.
  Future<({double latitude, double longitude})?> geocode(String address) async {
    final key = address.trim().toLowerCase();
    if (key.isEmpty) return null;
    if (_geocoded.containsKey(key)) return _geocoded[key];
    final apiKey = await MapsKey.load();
    if (apiKey.isEmpty) return null;
    ({double latitude, double longitude})? result;
    try {
      final response = await http.get(
        Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
          'address': address.trim(),
          'region': 'in',
          'key': apiKey,
        }),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final results = body['results'] as List<dynamic>? ?? const [];
        if (results.isNotEmpty) {
          final location = ((results.first as Map<String, dynamic>)['geometry']
              as Map<String, dynamic>?)?['location'] as Map<String, dynamic>?;
          final lat = (location?['lat'] as num?)?.toDouble();
          final lng = (location?['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            result = (latitude: lat, longitude: lng);
          }
        }
      }
    } catch (e) {
      debugPrint('Geocoding failed: $e');
    }
    _geocoded[key] = result;
    return result;
  }

  /// Fetches coordinates for [placeId] via the Place Details API.
  ///
  /// Returns `null` on any failure — never throws.
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    if (placeId.isEmpty) {
      return null;
    }

    final apiKey = await MapsKey.load();
    if (apiKey.isEmpty) return null;

    if (kIsWeb) {
      return web_impl.getWebPlaceDetails(placeId);
    }

    final uri = Uri.parse('https://places.googleapis.com/v1/places/$placeId');

    try {
      final response = await http.get(
        uri,
        headers: {
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'id,formattedAddress,location',
        },
      );
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final formattedAddress = body['formattedAddress'] as String? ?? '';

      final location = body['location'] as Map<String, dynamic>?;
      final lat = (location?['latitude'] as num?)?.toDouble();
      final lng = (location?['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      return PlaceDetails(
        latitude: lat,
        longitude: lng,
        formattedAddress: formattedAddress,
      );
    } catch (_) {
      return null;
    }
  }
}
