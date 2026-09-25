// lib/features/radiology/ai/rad_ai.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';

// Regulatory note: AI findings shown to clinicians may fall under India's
// CDSCO Software-as-a-Medical-Device rules. Keep them clearly labelled as
// suggestions that need confirmation.

/// The 4 clinical findings detected by the second read.
enum RadAiKind { caries, boneLoss, periapical, impacted }

extension RadAiKindExt on RadAiKind {
  String get label => switch (this) {
        RadAiKind.caries => 'Caries',
        RadAiKind.boneLoss => 'Bone loss',
        RadAiKind.periapical => 'Periapical lesion',
        RadAiKind.impacted => 'Impacted tooth',
      };
}

/// One finding suggested by the AI second reader.
class RadAiFinding {
  const RadAiFinding({
    required this.id,
    required this.kind,
    required this.label,
    required this.confidence,
    this.box,
    this.tooth = '',
    this.status = 'pending',
  });

  final String id;
  final RadAiKind kind;
  final String label; // "Distal caries", "Horizontal bone loss ~30%"
  final double confidence; // 0..1
  final Rect? box; // normalised 0..1 on the image, null if none
  final String tooth; // FDI or ''
  final String status; // 'pending' | 'accepted' | 'rejected' | 'edited'

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isEdited => status == 'edited';

  RadAiFinding copyWith({
    String? id,
    RadAiKind? kind,
    String? label,
    double? confidence,
    Rect? box,
    String? tooth,
    String? status,
  }) =>
      RadAiFinding(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        label: label ?? this.label,
        confidence: confidence ?? this.confidence,
        box: box ?? this.box,
        tooth: tooth ?? this.tooth,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'label': label,
        'confidence': confidence,
        'box': box == null
            ? null
            : [box!.left, box!.top, box!.right, box!.bottom],
        'tooth': tooth,
        'status': status,
      };

  factory RadAiFinding.fromJson(Map<String, dynamic> j) {
    RadAiKind parseKind(String k) {
      return RadAiKind.values.firstWhere(
        (e) => e.name == k,
        orElse: () => RadAiKind.caries,
      );
    }

    Rect? parseBox(dynamic b) {
      if (b is List && b.length == 4) {
        final n0 = (b[0] as num).toDouble().clamp(0.0, 1.0);
        final n1 = (b[1] as num).toDouble().clamp(0.0, 1.0);
        final n2 = (b[2] as num).toDouble().clamp(0.0, 1.0);
        final n3 = (b[3] as num).toDouble().clamp(0.0, 1.0);
        final x0 = math.min(n0, n2);
        final x1 = math.max(n0, n2);
        final y0 = math.min(n1, n3);
        final y1 = math.max(n1, n3);
        return Rect.fromLTRB(x0, y0, x1, y1);
      }
      return null;
    }

    return RadAiFinding(
      id: j['id'] as String? ?? const Uuid().v4(),
      kind: parseKind(j['kind'] as String? ?? ''),
      label: j['label'] as String? ?? '',
      confidence: (j['confidence'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0,
      box: parseBox(j['box']),
      tooth: j['tooth'] as String? ?? '',
      status: j['status'] as String? ?? 'pending',
    );
  }
}

/// Abstract contract for radiology second reading.
abstract class RadAiProvider {
  bool get connected;
  Future<List<RadAiFinding>> secondRead(
    Uint8List pngPixelsOnly, {
    required String modality,
  });
}

/// Fallback provider used when no API key is configured.
class NoAiProvider implements RadAiProvider {
  @override
  bool get connected => false;

  @override
  Future<List<RadAiFinding>> secondRead(
    Uint8List pngPixelsOnly, {
    required String modality,
  }) async {
    throw StateError('No AI key connected');
  }
}

/// Reads the Gemini API key from environment, dart-defines, or `.env.local`.
String resolveGeminiApiKey() {
  const envKey = String.fromEnvironment('GEMINI_API_KEY');
  if (envKey.isNotEmpty) return envKey;
  final platKey = Platform.environment['GEMINI_API_KEY'];
  if (platKey != null && platKey.isNotEmpty) return platKey;
  try {
    final file = File('.env.local');
    if (file.existsSync()) {
      for (final line in file.readAsLinesSync()) {
        final i = line.indexOf('=');
        if (line.trim().startsWith('#') || i <= 0) continue;
        if (line.substring(0, i).trim() == 'GEMINI_API_KEY') {
          final val = line.substring(i + 1).trim();
          if (val.isNotEmpty) return val;
        }
      }
    }
  } catch (_) {}
  return '';
}

/// Real AI second reader calling Gemini 3.5 Flash via REST.
class GeminiRadAiProvider implements RadAiProvider {
  GeminiRadAiProvider({String? apiKey, http.Client? client})
      : _apiKey = apiKey ?? resolveGeminiApiKey(),
        _http = client ?? http.Client();

  final String _apiKey;
  final http.Client _http;

  @override
  bool get connected => _apiKey.isNotEmpty;

  @override
  Future<List<RadAiFinding>> secondRead(
    Uint8List pngPixelsOnly, {
    required String modality,
  }) async {
    if (!connected) throw StateError('No AI key connected');

    final model = GeminiJsonClient.fallbackModel; // gemini-3.5-flash
    const systemPrompt =
        'You are an expert dental radiology AI second-reader assistant. '
        'You provide suggestions for a qualified dentist or radiologist to confirm or reject. '
        'This is a second reader, not an autonomous clinical diagnosis.';

    final prompt = '''
Examine this dental radiograph (modality: $modality).
Identify findings strictly in these four categories:
1. caries (enamel caries, dentin caries, proximal, occlusal, cervical, recurrent)
2. boneLoss (horizontal or vertical bone loss, alveolar crest reduction with estimated percentage)
3. periapical (periapical radiolucency, widening of periodontal ligament, apical cyst/granuloma)
4. impacted (impacted, unerupted, ectopic, or angulated teeth)

Return a JSON array of up to 20 findings. If none found, return an empty array [].
Output ONLY valid JSON matching this schema:
[
  {
    "kind": "caries" | "boneLoss" | "periapical" | "impacted",
    "label": "Concise description (e.g. Distal caries, Horizontal bone loss ~30%, Periapical radiolucency)",
    "confidence": 0.0 to 1.0,
    "box": [x0, y0, x1, y1],
    "tooth": "FDI number (e.g. 16, 24, 38, 46) or empty string"
  }
]
Note: Coordinates in "box" must be normalised floats from 0.0 to 1.0 representing [left, top, right, bottom].
''';

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );

    final response = await _http
        .post(
          uri,
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
                      'mimeType': 'image/png',
                      'data': base64Encode(pngPixelsOnly),
                    },
                  },
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.1,
              'maxOutputTokens': 4096,
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 45));

    final raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw GeminiHttpException(response.statusCode, raw);
    }

    final body = jsonDecode(raw);
    final parts = (body is Map ? body['candidates'] : null) is List
        ? ((body['candidates'] as List).firstOrNull as Map?)?['content']?['parts']
        : null;
    if (parts is! List) return [];

    final text = parts
        .whereType<Map>()
        .where((p) => p['thought'] != true)
        .map((p) => p['text'])
        .whereType<String>()
        .join();

    final jsonStr = GeminiJsonClient.extractJson(text);
    final decoded = jsonDecode(jsonStr);
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['findings'] is List
            ? decoded['findings'] as List
            : <dynamic>[]);

    final findings = <RadAiFinding>[];
    for (final item in list) {
      if (item is! Map) continue;
      try {
        final f = RadAiFinding.fromJson(Map<String, dynamic>.from(item));
        findings.add(f);
        if (findings.length >= 20) break;
      } catch (_) {}
    }
    return findings;
  }
}

/// Provider for the AI second reader.
final radAiProviderProvider = Provider<RadAiProvider>((ref) {
  final key = resolveGeminiApiKey();
  if (key.isEmpty) return NoAiProvider();
  return GeminiRadAiProvider(apiKey: key);
});

/// Whether AI overlay marks are shown on the viewer.
final radShowAiMarksProvider = StateProvider<bool>((ref) => true);
