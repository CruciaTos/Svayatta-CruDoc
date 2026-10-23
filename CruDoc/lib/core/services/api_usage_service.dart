import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';

/// Paid outside services CruDoc calls. The names are the keys Super Admin
/// reads in the daily usage documents.
enum ApiService {
  /// Google Gemini: Scribe, voice forms, the patient voice bar, document
  /// scans, radiology and homeopathy AI.
  gemini,

  /// Sarvam speech-to-text, through the desktop voice server.
  sarvam,

  /// WhatsApp Cloud API messages sent from the app.
  whatsapp,

  /// Google Places: address autocomplete and place details.
  places,

  /// Google Static Maps images.
  maps,
}

/// Records calls to paid outside services, per person per day, at
/// `users/{uid}/api_usage/{yyyy-MM-dd}`. Counters only: never prompts,
/// audio, phone numbers or addresses. Super Admin adds them up per doctor,
/// clinic and service.
///
/// Recording never blocks or fails the call it describes; demo sessions
/// record nothing.
abstract final class ApiUsage {
  /// Replaces the Firestore write (tests).
  @visibleForTesting
  static Future<void> Function(String uid, String day, Map<String, Object?>)?
  writeOverride;

  /// Who is signed in (tests replace it).
  @visibleForTesting
  static String? Function() currentUid = () {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  };

  static final _day = DateFormat('yyyy-MM-dd');

  /// The day document's id for [at] (the device's own date).
  static String dayKey(DateTime at) => _day.format(at);

  /// What one record adds, as plain numbers (see [record]).
  static Map<String, Object?> delta(
    ApiService service, {
    required String feature,
    int count = 1,
    bool error = false,
    int inputTokens = 0,
    int outputTokens = 0,
    double seconds = 0,
  }) => {
    service.name: {
      'calls': count,
      if (error) 'errors': 1,
      if (inputTokens > 0) 'inputTokens': inputTokens,
      if (outputTokens > 0) 'outputTokens': outputTokens,
      if (seconds > 0) 'seconds': double.parse(seconds.toStringAsFixed(2)),
      'features': {_featureKey(feature): count},
    },
  };

  /// Adds [count] calls of [service] made for [feature] (`scribe`,
  /// `voice_form`, `campaign`...). Fire and forget.
  static void record(
    ApiService service, {
    required String feature,
    int count = 1,
    bool error = false,
    int inputTokens = 0,
    int outputTokens = 0,
    double seconds = 0,
  }) {
    if (DemoSessionService.isDemoMode || count <= 0) return;
    final uid = currentUid();
    if (uid == null) return;
    final now = DateTime.now();
    final day = dayKey(now);
    final data = <String, Object?>{
      'date': day,
      // Clinic members bill to the clinic: its id is the owner's uid.
      'clinicId': _clinicId() ?? uid,
      ..._increments(
        delta(
          service,
          feature: feature,
          count: count,
          error: error,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          seconds: seconds,
        ),
      ),
    };
    final write = writeOverride;
    if (write != null) {
      unawaited(write(uid, day, data));
      return;
    }
    data['updatedAt'] = FieldValue.serverTimestamp();
    unawaited(
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('api_usage')
          .doc(day)
          .set(data, SetOptions(merge: true))
          .catchError((Object e) => debugPrint('[ApiUsage] not saved: $e')),
    );
  }

  static final Set<String> _seen = {};

  /// Records [key] (a map image's URL) at most once per app run: the image
  /// cache fetches it once, however often the screen rebuilds.
  static void recordOnce(
    ApiService service,
    String key, {
    required String feature,
  }) {
    if (_seen.add('${service.name}:$key')) {
      record(service, feature: feature);
    }
  }

  /// Records one raw Gemini REST reply: an error, or the tokens in its
  /// `usageMetadata` (thinking counts as output, as it is billed).
  static void recordGeminiRest(
    int statusCode,
    String body, {
    required String feature,
  }) {
    if (statusCode != 200) {
      record(ApiService.gemini, feature: feature, error: true);
      return;
    }
    var input = 0, output = 0;
    try {
      final usage = (jsonDecode(body) as Map)['usageMetadata'];
      if (usage is Map) {
        int n(String k) => (usage[k] as num?)?.toInt() ?? 0;
        input = n('promptTokenCount');
        output = n('candidatesTokenCount') + n('thoughtsTokenCount');
      }
    } catch (_) {}
    record(
      ApiService.gemini,
      feature: feature,
      inputTokens: input,
      outputTokens: output,
    );
  }

  static String? _clinicId() {
    try {
      return ClinicSession.instance.tenantId;
    } catch (_) {
      return null;
    }
  }

  /// Field-safe feature names ("Voice form" → "voice_form").
  static String _featureKey(String feature) {
    final key = feature
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return key.isEmpty ? 'other' : key;
  }

  /// Numbers become Firestore increments, so writes from several devices
  /// add up instead of overwriting each other.
  static Map<String, Object?> _increments(Map<String, Object?> m) => {
    for (final e in m.entries)
      e.key: switch (e.value) {
        final Map<String, Object?> inner => _increments(inner),
        final num n => writeOverride != null ? n : FieldValue.increment(n),
        final other => other,
      },
  };
}
