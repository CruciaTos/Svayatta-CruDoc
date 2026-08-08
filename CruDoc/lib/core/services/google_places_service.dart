import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart'
    show kGoogleMapsApiKey;

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
/// All methods are best-effort: a network error, a bad API key, or zero
/// results simply returns an empty list / null — never throws. This
/// matches the app's existing "maps features are nice-to-have, never
/// block the workflow" philosophy (see [VisitRepository._resolveCoords]).
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

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': trimmed,
        'key': kGoogleMapsApiKey,
        'components': 'country:$countryCode',
        'types': 'geocode|establishment',
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final predictions = body['predictions'] as List<dynamic>?;
      if (predictions == null) return const [];

      return predictions
          .map((p) => PlacePrediction.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
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

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'key': kGoogleMapsApiKey,
        'fields': 'geometry,formatted_address',
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      final geometry = result['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      return PlaceDetails(
        latitude: lat,
        longitude: lng,
        formattedAddress:
            result['formatted_address'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
