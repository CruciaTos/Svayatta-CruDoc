import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';

/// The Google Maps key used for address search, geocoding and map images.
///
/// A key built in with `--dart-define=GOOGLE_MAPS_API_KEY=...` wins.
/// Otherwise it is the key the super admin saved under API settings. That
/// is copied to `system_config/client_keys`, which any signed-in doctor
/// can read (unlike `api_keys_config`, which also holds server secrets).
class MapsKey {
  MapsKey._();

  static const String _builtIn =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');

  /// Where the doctor's app reads the saved key from.
  static const String collection = 'system_config';
  static const String document = 'client_keys';
  static const String field = 'googleMapsApiKey';

  /// After a failed or empty load, wait this long before asking again.
  static const Duration _retryAfter = Duration(minutes: 1);

  static String _saved = '';
  static DateTime? _failedAt;
  static Future<String>? _loading;

  /// The key known right now: empty until [load] has found one.
  static String get value => _builtIn.isNotEmpty ? _builtIn : _saved;

  static bool get isSet => value.isNotEmpty;

  /// The key, fetching the saved one if it isn't known yet. Empty when
  /// none is saved, the doctor isn't signed in or there is no network.
  static Future<String> load() {
    if (isSet) return Future.value(value);
    final failed = _failedAt;
    if (failed != null && DateTime.now().difference(failed) < _retryAfter) {
      return Future.value('');
    }
    return _loading ??= _fetch().whenComplete(() => _loading = null);
  }

  /// Fetches the key as soon as someone signs in, so maps and address
  /// search are ready when they're first needed.
  static void loadOnSignIn() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) return;
      _failedAt = null;
      unawaited(load());
    });
  }

  static Future<String> _fetch() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(collection)
          .doc(document)
          .get();
      _saved = (snap.data()?[field] as String?)?.trim() ?? '';
    } catch (_) {
      _saved = '';
    }
    _failedAt = _saved.isEmpty ? DateTime.now() : null;
    return value;
  }
}

/// The Maps key once loaded. Widgets that draw maps watch it so they
/// redraw when the key arrives after sign-in.
final mapsKeyProvider = FutureProvider<String>((ref) {
  ref.watch(authStateProvider);
  return MapsKey.load();
});
