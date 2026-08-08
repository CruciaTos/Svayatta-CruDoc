// ignore_for_file: undefined_function, avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:js';
import 'google_places_service.dart';

Future<List<PlacePrediction>> getWebAutocomplete(String input) {
  final completer = Completer<List<PlacePrediction>>();
  try {
    context.callMethod('googlePlacesAutocomplete', [
      input,
      allowInterop((String jsonResults) {
        try {
          final List<dynamic> list = jsonDecode(jsonResults);
          final predictions = list
              .map((item) => PlacePrediction.fromJson(item as Map<String, dynamic>))
              .toList();
          completer.complete(predictions);
        } catch (_) {
          completer.complete([]);
        }
      })
    ]);
  } catch (_) {
    completer.complete([]);
  }
  return completer.future;
}

Future<PlaceDetails?> getWebPlaceDetails(String placeId) {
  final completer = Completer<PlaceDetails?>();
  try {
    context.callMethod('googlePlaceDetails', [
      placeId,
      allowInterop((String? jsonResult) {
        if (jsonResult == null) {
          completer.complete(null);
          return;
        }
        try {
          final map = jsonDecode(jsonResult) as Map<String, dynamic>;
          final formattedAddress = map['formatted_address'] as String;
          final geometry = map['geometry'] as Map<String, dynamic>;
          final location = geometry['location'] as Map<String, dynamic>;
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          completer.complete(PlaceDetails(
            latitude: lat,
            longitude: lng,
            formattedAddress: formattedAddress,
          ));
        } catch (_) {
          completer.complete(null);
        }
      })
    ]);
  } catch (_) {
    completer.complete(null);
  }
  return completer.future;
}
