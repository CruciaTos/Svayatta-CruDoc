import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sends audio (plus a prompt) to Gemini and returns the model's JSON reply,
/// constrained by a response [Schema]. Shared by the AI Scribe and voice
/// form filling.
///
/// Two transports:
/// - **Direct REST** when an API key is available via constructor,
///   `--dart-define=GEMINI_API_KEY=...`, environment variable, or `.env.local`.
/// - **Firebase AI Logic** (fallback when no API key is provided):
///   authenticates via Firebase project credentials.
///
/// The model name comes from constructor, `--dart-define=GEMINI_MODEL`,
/// `.env.local`, Remote Config key [remoteConfigModelKey], then [fallbackModel].
class GeminiJsonClient {
  GeminiJsonClient({String? apiKey, String? model, http.Client? httpClient})
    : _apiKey = apiKey ?? _resolveApiKey(),
      _modelOverride = model ?? (_resolveModel().isEmpty ? null : _resolveModel()),
      _http = httpClient ?? http.Client();

  static const _envApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _envModel = String.fromEnvironment('GEMINI_MODEL');

  static const defaultScribeApiKey =
      'AIzaSyBEJGmmNiiWT2GqGtfLBzoa7jqcryui1SM';

  static String _readKeyFromEnvFile(File file, String keyName) {
    try {
      if (file.existsSync()) {
        for (final line in file.readAsLinesSync()) {
          final i = line.indexOf('=');
          if (line.trim().startsWith('#') || i <= 0) continue;
          if (line.substring(0, i).trim() == keyName) {
            final val = line.substring(i + 1).trim();
            if (val.isNotEmpty) return val;
          }
        }
      }
    } catch (_) {}
    return '';
  }

  static String _resolveApiKey() {
    if (_envApiKey.isNotEmpty) return _envApiKey;
    try {
      final platKey = Platform.environment['GEMINI_API_KEY'];
      if (platKey != null && platKey.isNotEmpty) return platKey;
    } catch (_) {}
    // Check .env.local in current directory
    final localKey = _readKeyFromEnvFile(File('.env.local'), 'GEMINI_API_KEY');
    if (localKey.isNotEmpty) return localKey;

    // Check .env.local next to executable for standalone / release builds
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final exeKey = _readKeyFromEnvFile(
        File('${exeDir.path}${Platform.pathSeparator}.env.local'),
        'GEMINI_API_KEY',
      );
      if (exeKey.isNotEmpty) return exeKey;
    } catch (_) {}

    return defaultScribeApiKey;
  }

  static String _resolveModel() {
    if (_envModel.isNotEmpty) return _envModel;
    try {
      final platModel = Platform.environment['GEMINI_MODEL'];
      if (platModel != null && platModel.isNotEmpty) return platModel;
    } catch (_) {}
    final localModel = _readKeyFromEnvFile(File('.env.local'), 'GEMINI_MODEL');
    if (localModel.isNotEmpty) return localModel;
    return '';
  }

  static const remoteConfigModelKey = 'scribe_gemini_model';

  /// GA Flash model for clinical transcription and reasoning.
  static const fallbackModel = 'gemini-2.5-flash';

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
    // If the primary model produces a 404, fall back to known alternatives
    final candidateModels = [
      model,
      if (model != 'gemini-2.5-flash') 'gemini-2.5-flash',
      if (model != 'gemini-1.5-flash') 'gemini-1.5-flash',
      if (model != 'gemini-3.5-flash') 'gemini-3.5-flash',
    ];

    GeminiHttpException? lastHttpException;
    for (final candidate in candidateModels) {
      final response = await _http
          .post(
            Uri.parse('$_restBase/$candidate:generateContent'),
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

      final raw = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode == 404 && candidate != candidateModels.last) {
        debugPrint('[GeminiJsonClient] Model $candidate returned 404, trying fallback...');
        lastHttpException = GeminiHttpException(response.statusCode, raw);
        continue;
      }
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
    if (lastHttpException != null) throw lastHttpException;
    return '';
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

  /// True if the Generative Language API is disabled in the Google Cloud project.
  bool get isServiceDisabled =>
      body.contains('SERVICE_DISABLED') ||
      body.contains('has not been used in project');

  /// True if the key has restrictions blocking this API.
  bool get isKeyBlocked => body.contains('API_KEY_SERVICE_BLOCKED');

  /// Human-readable error message from the Google API error response, if available.
  String? get apiErrorMessage {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final msg = decoded['error']['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return null;
  }

  @override
  String toString() {
    final snippet = body.length > 300 ? '${body.substring(0, 300)}…' : body;
    return 'GeminiHttpException($statusCode): $snippet';
  }
}
