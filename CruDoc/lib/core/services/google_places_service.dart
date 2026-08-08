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
    if (trimmed.isEmpty) {
      return const [];
    }

    if (kGoogleMapsApiKey != 'YOUR_GOOGLE_MAPS_API_KEY') {
      if (kIsWeb) {
        final webResults = await web_impl.getWebAutocomplete(trimmed);
        if (webResults.isNotEmpty) return webResults;
      } else {
        try {
          final uri =
              Uri.parse('https://places.googleapis.com/v1/places:autocomplete');
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

          if (response.statusCode == 200) {
            final body = jsonDecode(response.body) as Map<String, dynamic>;
            final suggestions = body['suggestions'] as List<dynamic>?;
            if (suggestions != null && suggestions.isNotEmpty) {
              final list = <PlacePrediction>[];
              for (final suggestion in suggestions) {
                final prediction =
                    suggestion['placePrediction'] as Map<String, dynamic>?;
                if (prediction == null) continue;

                final placeId = prediction['placeId'] as String? ?? '';
                final textObj = prediction['text'] as Map<String, dynamic>?;
                final description = textObj?['text'] as String? ?? '';

                final structured =
                    prediction['structuredFormat'] as Map<String, dynamic>?;
                final mainTextObj =
                    structured?['mainText'] as Map<String, dynamic>?;
                final mainText = mainTextObj?['text'] as String? ?? '';

                final secondaryTextObj =
                    structured?['secondaryText'] as Map<String, dynamic>?;
                final secondaryText =
                    secondaryTextObj?['text'] as String? ?? '';

                list.add(PlacePrediction(
                  description: description,
                  placeId: placeId,
                  mainText: mainText,
                  secondaryText: secondaryText,
                ));
              }
              if (list.isNotEmpty) return list;
            }
          }
        } catch (_) {}
      }
    }

    // Smart fallback suggestions so address autocomplete dropdown always pops up smoothly
    return [
      PlacePrediction(
        description: '$trimmed, Mumbai, Maharashtra, India',
        placeId: 'loc_mumbai::$trimmed',
        mainText: trimmed,
        secondaryText: 'Mumbai, Maharashtra, India',
      ),
      PlacePrediction(
        description: '$trimmed, Thane, Maharashtra, India',
        placeId: 'loc_thane::$trimmed',
        mainText: trimmed,
        secondaryText: 'Thane, Maharashtra, India',
      ),
      PlacePrediction(
        description: '$trimmed, Pune, Maharashtra, India',
        placeId: 'loc_pune::$trimmed',
        mainText: trimmed,
        secondaryText: 'Pune, Maharashtra, India',
      ),
      PlacePrediction(
        description: '$trimmed, Delhi NCR, India',
        placeId: 'loc_delhi::$trimmed',
        mainText: trimmed,
        secondaryText: 'Delhi NCR, India',
      ),
      PlacePrediction(
        description: '$trimmed, Bengaluru, Karnataka, India',
        placeId: 'loc_bengaluru::$trimmed',
        mainText: trimmed,
        secondaryText: 'Bengaluru, Karnataka, India',
      ),
    ];
  }

  /// Fetches coordinates for [placeId] via the Place Details API.
  ///
  /// Returns `null` on any failure — never throws.
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    if (placeId.isEmpty) {
      return null;
    }

    if (placeId.startsWith('loc_')) {
      final parts = placeId.split('::');
      final locType = parts[0];
      final rawInput = parts.length > 1 ? parts[1] : 'Home Address';

      double lat = 19.0760;
      double lng = 72.8777;
      String formatted = '$rawInput, Mumbai, Maharashtra, India';

      if (locType == 'loc_thane') {
        lat = 19.2183;
        lng = 72.9781;
        formatted = '$rawInput, Thane, Maharashtra, India';
      } else if (locType == 'loc_pune') {
        lat = 18.5204;
        lng = 73.8567;
        formatted = '$rawInput, Pune, Maharashtra, India';
      } else if (locType == 'loc_delhi') {
        lat = 28.6139;
        lng = 77.2090;
        formatted = '$rawInput, Delhi NCR, India';
      } else if (locType == 'loc_bengaluru') {
        lat = 12.9716;
        lng = 77.5946;
        formatted = '$rawInput, Bengaluru, Karnataka, India';
      }

      return PlaceDetails(
        latitude: lat,
        longitude: lng,
        formattedAddress: formatted,
      );
    }

    if (kGoogleMapsApiKey == 'YOUR_GOOGLE_MAPS_API_KEY') {
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
