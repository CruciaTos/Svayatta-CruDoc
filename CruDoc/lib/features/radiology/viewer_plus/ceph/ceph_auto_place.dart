import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/ceph/ceph_analysis.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/plus_canvas.dart';

/// Confidence under which a proposed point is flagged for the dentist.
const cephLowConfidence = 0.6;

/// One landmark the AI proposed: [point] in image pixels.
class CephAiPoint {
  const CephAiPoint(this.id, this.point, this.confidence);
  final String id;
  final Offset point;
  final double confidence;
  bool get low => confidence < cephLowConfidence;
}

/// Asks Gemini to place the ceph landmarks on [image]. Only ids from
/// [cephLandmarks] are returned. Throws on offline / AI / bad-JSON errors
/// (the caller shows a message).
Future<List<CephAiPoint>> cephAutoPlace(ui.Image image) async {
  final jpeg = await _jpeg(image);
  final list = cephLandmarks
      .map((l) => '- ${l.id}: ${l.name} (${l.hint})')
      .join('\n');
  final reply = await GeminiJsonClient().generateJson(
    systemPrompt:
        'You are an assistant that proposes cephalometric landmark positions '
        'on a lateral cephalogram for a dentist to review and correct. '
        'You are not making a diagnosis.',
    prompt:
        '''
This is a lateral cephalometric radiograph. Place these landmarks, using EXACTLY these ids:
$list

Return JSON {"landmarks":[{"id":"S","x":0.0,"y":0.0,"confidence":0.0}]}.
x and y are normalised 0 to 1: x from the left edge divided by image width, y from the top edge divided by image height.
confidence is 0 to 1. Leave out any landmark you cannot see; never guess wildly.
''',
    images: [jpeg],
    schema: Schema.object(
      properties: {
        'landmarks': Schema.array(
          items: Schema.object(
            properties: {
              'id': Schema.string(),
              'x': Schema.number(),
              'y': Schema.number(),
              'confidence': Schema.number(),
            },
          ),
        ),
      },
    ),
    maxOutputTokens: 4096,
    timeout: const Duration(seconds: 60),
    feature: 'ceph_auto_place',
  );
  final raw = reply['landmarks'];
  if (raw is! List) throw const FormatException('No landmarks in reply');
  final known = {for (final l in cephLandmarks) l.id};
  final out = <String, CephAiPoint>{};
  for (final e in raw) {
    if (e is! Map) continue;
    final id = '${e['id']}';
    final x = e['x'], y = e['y'];
    if (!known.contains(id) || x is! num || y is! num) continue;
    if (x < 0 || x > 1 || y < 0 || y > 1) continue;
    final conf = e['confidence'] is num
        ? (e['confidence'] as num).toDouble().clamp(0.0, 1.0)
        : 0.0;
    out[id] = CephAiPoint(
      id,
      Offset(x.toDouble() * image.width, y.toDouble() * image.height),
      conf,
    );
  }
  if (out.isEmpty) throw const FormatException('No usable landmarks');
  return out.values.toList();
}

/// The image downscaled to at most 1536 px on the long side, as JPEG.
Future<Uint8List> _jpeg(ui.Image image) async {
  final long = math.max(image.width, image.height);
  final s = long > 1536 ? 1536 / long : 1.0;
  final w = (image.width * s).round(), h = (image.height * s).round();
  final png = await plusRenderPng(w, h, (canvas) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
  });
  final decoded = img.decodePng(png);
  if (decoded == null) throw StateError('Could not prepare the image');
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 85));
}
