import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A callable Cloud Function refused or failed. [code] is the callable error
/// code ('permission-denied', 'not-found', ... or 'unavailable' when the
/// server couldn't be reached), as FirebaseFunctionsException has it.
class CallableException implements Exception {
  const CallableException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Calls an `onCall` Cloud Function on every platform.
///
/// The `cloud_functions` plugin has no Windows or Linux implementation, so
/// there every `httpsCallable(...).call()` fails before leaving the machine.
/// On those platforms this speaks the callable protocol itself: a POST of
/// `{"data": ...}` with the signed-in user's ID token, answered with
/// `{"result": ...}` or `{"error": {"status", "message"}}`. It targets the
/// local emulator when the app was started with USE_FIREBASE_EMULATORS, like
/// main.dart does for the plugin.
class CallableClient {
  CallableClient({this.region = 'asia-south1', http.Client? client})
    : _client = client;

  final String region;
  final http.Client? _client;

  static const bool _useEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
  );
  static const String _emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );

  /// Whether this platform has the plugin.
  static bool get hasPlugin =>
      kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// Runs [name] with [data]; returns the function's result. Throws
  /// [CallableException].
  Future<dynamic> call(String name, Map<String, dynamic> data) async {
    if (hasPlugin) {
      try {
        final result = await FirebaseFunctions.instanceFor(
          region: region,
        ).httpsCallable(name).call<dynamic>(data);
        return result.data;
      } on FirebaseFunctionsException catch (e) {
        throw CallableException(e.code, e.message ?? '');
      }
    }
    return _callOverHttp(name, data);
  }

  Future<dynamic> _callOverHttp(String name, Map<String, dynamic> data) async {
    final projectId = Firebase.app().options.projectId;
    final url = _useEmulators
        ? Uri.parse('http://$_emulatorHost:5001/$projectId/$region/$name')
        : Uri.parse('https://$region-$projectId.cloudfunctions.net/$name');
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final client = _client ?? http.Client();
    final http.Response res;
    try {
      res = await client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': ?(token == null ? null : 'Bearer $token'),
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(const Duration(seconds: 70));
    } catch (e) {
      throw CallableException('unavailable', '$e');
    } finally {
      if (_client == null) client.close();
    }
    return decodeResponse(res.statusCode, res.body);
  }

  /// The result in a callable response, or the [CallableException] its
  /// error describes. Public for tests.
  static dynamic decodeResponse(int status, String body) {
    Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      json = null;
    }
    if (json is Map && json['error'] is Map) {
      final err = json['error'] as Map;
      final s = '${err['status'] ?? 'INTERNAL'}';
      throw CallableException(
        s.toLowerCase().replaceAll('_', '-'),
        '${err['message'] ?? ''}',
      );
    }
    if (status >= 200 && status < 300 && json is Map) {
      return json['result'] ?? json['data'];
    }
    throw CallableException(
      status == 404 ? 'not-found' : 'internal',
      'HTTP $status',
    );
  }
}
