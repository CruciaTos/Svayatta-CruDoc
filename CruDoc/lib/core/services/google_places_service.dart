import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart'
    show kGoogleMapsApiKey;

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

  const PlacePrediction({
    required this.description,
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
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
/// REST APIs. Uses the same [kGoogleMapsApiKey] that the rest of this app
/// uses for Geocoding and Static Maps, keeping credentials in one place.
///
/// Fully updated to use the Google Places API (New) endpoints to support
/// newly created Google Cloud Console projects where the legacy Places API
/// is disabled by default.
class GooglePlacesService {
  GooglePlacesService._();
  static final instance = GooglePlacesService._();

  /// Returns autocomplete predictions for [input].
  ///
  /// Biased to India (`components=country:in`) to surface relevant
  /// addresses for this medical-practice app. Override with
  /// [countryCode] if needed.
  Future<List<PlacePrediction>> autocomplete(
    String input, {
    String countryCode = 'in',
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty || kGoogleMapsApiKey == 'YOUR_GOOGLE_MAPS_API_KEY') {
      return const [];
    }

    if (kIsWeb) {
      return web_impl.getWebAutocomplete(trimmed);
    }

    final uri = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');
    print('[GooglePlacesService] Requesting autocomplete for: "$trimmed"');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': kGoogleMapsApiKey,
        },
        body: jsonEncode({
          'input': trimmed,
          'includedRegionCodes': [countryCode.toUpperCase()],
        }),
      );
      print('[GooglePlacesService] Response status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        print('[GooglePlacesService] Error response: ${response.body}');
        return const [];
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = body['suggestions'] as List<dynamic>?;
      if (suggestions == null) {
        print('[GooglePlacesService] No suggestions found in response body');
        return const [];
      }

      final list = <PlacePrediction>[];
      for (final suggestion in suggestions) {
        final prediction = suggestion['placePrediction'] as Map<String, dynamic>?;
        if (prediction == null) continue;
        
        final placeId = prediction['placeId'] as String? ?? '';
        final textObj = prediction['text'] as Map<String, dynamic>?;
        final description = textObj?['text'] as String? ?? '';
        
        final structured = prediction['structuredFormat'] as Map<String, dynamic>?;
        final mainTextObj = structured?['mainText'] as Map<String, dynamic>?;
        final mainText = mainTextObj?['text'] as String? ?? '';
        
        final secondaryTextObj = structured?['secondaryText'] as Map<String, dynamic>?;
        final secondaryText = secondaryTextObj?['text'] as String? ?? '';
        
        list.add(PlacePrediction(
          description: description,
          placeId: placeId,
          mainText: mainText,
          secondaryText: secondaryText,
        ));
      }
      print('[GooglePlacesService] Parsed ${list.length} predictions');
      return list;
    } catch (e, stackTrace) {
      print('[GooglePlacesService] Exception during request: $e');
      print(stackTrace);
      return const [];
    }
  }

  /// Fetches coordinates for [placeId] via the Place Details API.
  ///
  /// Returns `null` on any failure — never throws.
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    if (placeId.isEmpty || kGoogleMapsApiKey == 'YOUR_GOOGLE_MAPS_API_KEY') {
      return null;
    }

    if (kIsWeb) {
      return web_impl.getWebPlaceDetails(placeId);
    }

    final uri = Uri.parse('https://places.googleapis.com/v1/places/$placeId');

    try {
      final response = await http.get(
        uri,
        headers: {
          'X-Goog-Api-Key': kGoogleMapsApiKey,
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
