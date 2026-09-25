import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sends audio (plus a prompt) to Gemini and returns the model's JSON reply,
/// constrained by a response [Schema]. Shared by the AI Scribe and voice
/// form filling.
///
/// Two transports:
/// - **Firebase AI Logic** (default, production): no key in the app; the
///   Gemini Developer API is enabled for the Firebase project.
/// - **Direct REST** when built with `--dart-define=GEMINI_API_KEY=...`.
///   Meant for demos and testing only — a key compiled into the app can be
///   extracted from it, so never ship a release built this way.
///
/// The model name comes from `--dart-define=GEMINI_MODEL`, then Remote
/// Config key [remoteConfigModelKey], then [fallbackModel].
class GeminiJsonClient {
  GeminiJsonClient({String? apiKey, String? model, http.Client? httpClient})
    : _apiKey = apiKey ?? _envApiKey,
      _modelOverride = model ?? (_envModel.isEmpty ? null : _envModel),
      _http = httpClient ?? http.Client();

  static const _envApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _envModel = String.fromEnvironment('GEMINI_MODEL');

  static const remoteConfigModelKey = 'scribe_gemini_model';

  /// GA Flash model; Firebase lists its retirement as no earlier than
  /// 2027-05-19. `gemini-2.0-flash` was shut down on 2026-06-01.
  static const fallbackModel = 'gemini-3.5-flash';

  static const _restBase =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final String _apiKey;
  final String? _modelOverride;
  final http.Client _http;
  bool _remoteConfigLoaded = false;

  /// True when calls go straight to the Gemini API with a developer key.
  bool get usesApiKey => _apiKey.isNotEmpty;

  Future<String> modelName() async {
    if (_modelOverride != null) return _modelOverride;
    try {
      final rc = FirebaseRemoteConfig.instance;
      if (!_remoteConfigLoaded) {
        _remoteConfigLoaded = true;
        await rc.setDefaults(const {remoteConfigModelKey: fallbackModel});
        await rc.fetchAndActivate().timeout(const Duration(seconds: 4));
      }
      final value = rc.getString(remoteConfigModelKey).trim();
      if (value.isNotEmpty) return value;
    } catch (e) {
      debugPrint('[GeminiJsonClient] Remote Config unavailable: $e');
    }
    return fallbackModel;
  }

  /// Returns the decoded JSON object. Throws [FormatException] for an empty
  /// or non-JSON reply, [GeminiHttpException] for a REST error status, and
  /// passes through Firebase AI, timeout and network exceptions.
  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String prompt,
    required Uint8List audioBytes,
    required Schema schema,
    String mimeType = 'audio/mp4',
    int maxOutputTokens = 8192,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final model = await modelName();
    final text = usesApiKey
        ? await _viaRest(
            model,
            systemPrompt,
            prompt,
            audioBytes,
            mimeType,
            schema,
            maxOutputTokens,
            timeout,
          )
        : await _viaFirebase(
            model,
            systemPrompt,
            prompt,
            audioBytes,
            mimeType,
            schema,
            maxOutputTokens,
            timeout,
          );

    if (text.trim().isEmpty) {
      throw const FormatException('Empty response from the model.');
    }
    final decoded = jsonDecode(extractJson(text));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Response was not a JSON object.');
    }
    return decoded;
  }

  Future<String> _viaFirebase(
    String model,
    String systemPrompt,
    String prompt,
    Uint8List audioBytes,
    String mimeType,
    Schema schema,
    int maxOutputTokens,
    Duration timeout,
  ) async {
    final generative = FirebaseAI.googleAI().generativeModel(
      model: model,
      systemInstruction: Content.system(systemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0.1,
        maxOutputTokens: maxOutputTokens,
        responseMimeType: 'application/json',
        responseSchema: schema,
      ),
    );
    final response = await generative
        .generateContent([
          Content.multi([
            TextPart(prompt),
            InlineDataPart(mimeType, audioBytes),
          ]),
        ])
        .timeout(timeout);
    return response.text ?? '';
  }

  Future<String> _viaRest(
    String model,
    String systemPrompt,
    String prompt,
    Uint8List audioBytes,
    String mimeType,
    Schema schema,
    int maxOutputTokens,
    Duration timeout,
  ) async {
    final response = await _http
        .post(
          Uri.parse('$_restBase/$model:generateContent'),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': _apiKey,
          },
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': systemPrompt},
              ],
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': prompt},
                  {
                    'inlineData': {
                      'mimeType': mimeType,
                      'data': base64Encode(audioBytes),
                    },
                  },
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.1,
              'maxOutputTokens': maxOutputTokens,
              'responseMimeType': 'application/json',
              'responseSchema': schema.toJson(),
            },
          }),
        )
        .timeout(timeout);

    // Decode explicitly: the transcript may contain Devanagari.
    final raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw GeminiHttpException(response.statusCode, raw);
    }
    final body = jsonDecode(raw);
    final parts = (body is Map ? body['candidates'] : null) is List
        ? ((body['candidates'] as List).firstOrNull
              as Map?)?['content']?['parts']
        : null;
    if (parts is! List) return '';
    // Thinking models may return thought parts first; join the text parts.
    return parts
        .whereType<Map>()
        .where((p) => p['thought'] != true)
        .map((p) => p['text'])
        .whereType<String>()
        .join();
  }

  /// Strips any surrounding markdown code fences or prose the model might
  /// have added despite instructions.
  static String extractJson(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{')) return trimmed;
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start != -1 && end > start) return trimmed.substring(start, end + 1);
    return trimmed;
  }
}

/// A non-200 reply from the Gemini REST API.
class GeminiHttpException implements Exception {
  const GeminiHttpException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  bool get isQuota => statusCode == 429;

  /// Bad/blocked key, API disabled, or unknown model.
  bool get isNotConfigured =>
      statusCode == 401 ||
      statusCode == 403 ||
      statusCode == 404 ||
      (statusCode == 400 && body.contains('API_KEY'));

  @override
  String toString() {
    final snippet = body.length > 300 ? '${body.substring(0, 300)}…' : body;
    return 'GeminiHttpException($statusCode): $snippet';
  }
}
