import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/therapy/data/outcome_scale.dart';
import 'package:doctor_management_app/features/therapy/data/scales/measured_scales.dart';

// Where the questionnaires come from.
//
// Item text lives in `assets/outcome_scales/*.json`, not in Dart source, for
// three reasons that all point the same way:
//
//  * These are licensed third-party instruments. Keeping them as data means
//    a licence that changes, or one that is never granted, is a file that
//    changes — not a release.
//  * The wording is the instrument. A validated scale with edited options
//    is not that scale any more, so the text has to come from the clinic's
//    own authorised copy rather than being retyped by anyone, including me.
//  * A scale with its items missing is then a visible, reportable state
//    rather than a scale that silently scores wrong.
//
// A questionnaire whose asset is absent or unparseable is left out of the
// registry and reported in [ScaleLoad.problems]. It is never substituted,
// defaulted or partially loaded.

/// Questionnaire assets the app looks for.
///
/// Listed explicitly rather than globbed, so a missing file is an error that
/// names itself instead of a scale that quietly disappears.
const List<String> kScaleAssets = [
  'assets/outcome_scales/odi.json',
  'assets/outcome_scales/ndi.json',
];

/// What a load attempt produced: the scales that parsed, and what went
/// wrong with the ones that did not.
class ScaleLoad {
  const ScaleLoad(this.scales, this.problems);

  final List<ScaleDef> scales;

  /// One line per asset that could not be used, naming the asset and the
  /// reason. Surfaced in the UI rather than logged and forgotten: a clinic
  /// that thinks it has the NDI needs to be told it has not.
  final List<String> problems;

  ScaleDef? byId(String id) {
    for (final s in scales) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Reads one scale from decoded JSON.
///
/// Throws [FormatException] on anything missing or of the wrong shape, so a
/// malformed instrument fails loudly at load instead of scoring wrongly for
/// months.
ScaleDef scaleFromJson(Map<String, dynamic> json) {
  String str(String key) {
    final v = json[key];
    if (v is! String || v.trim().isEmpty) {
      throw FormatException('"$key" must be a non-empty string');
    }
    return v;
  }

  final kind = switch (json['kind']) {
    'questionnaire' => ScaleKind.questionnaire,
    'measured' => ScaleKind.measured,
    final other => throw FormatException(
      '"kind" must be questionnaire or measured, got $other',
    ),
  };

  final rawItems = json['items'];
  final items = <ScaleItem>[];
  if (rawItems is List) {
    for (final raw in rawItems) {
      if (raw is! Map) throw const FormatException('each item must be a map');
      final id = raw['id'];
      final label = raw['label'];
      final options = raw['options'];
      if (id is! String || id.trim().isEmpty) {
        throw const FormatException('each item needs an "id"');
      }
      if (label is! String || label.trim().isEmpty) {
        throw FormatException('item "$id" needs a "label"');
      }
      if (options is! List || options.length < 2) {
        throw FormatException('item "$id" needs at least two "options"');
      }
      for (final o in options) {
        if (o is! String || o.trim().isEmpty) {
          throw FormatException('item "$id" has an empty option');
        }
      }
      items.add(ScaleItem(id, label, [for (final o in options) o as String]));
    }
  }

  if (kind == ScaleKind.questionnaire && items.isEmpty) {
    throw const FormatException(
      'a questionnaire with no items cannot be scored',
    );
  }

  // Every item of one instrument must score over the same range, or a
  // percentage across them means nothing.
  if (items.isNotEmpty) {
    final width = items.first.options.length;
    for (final i in items) {
      if (i.options.length != width) {
        throw FormatException(
          'item "${i.id}" has ${i.options.length} options, '
          'but the first item has $width — every item must score alike',
        );
      }
    }
  }

  final ids = <String>{};
  for (final i in items) {
    if (!ids.add(i.id)) {
      throw FormatException('item id "${i.id}" appears twice');
    }
  }

  final rawBands = json['bands'];
  final bands = <ScaleBand>[];
  if (rawBands is List) {
    for (final raw in rawBands) {
      if (raw is! Map) throw const FormatException('each band must be a map');
      final from = raw['from'];
      final to = raw['to'];
      final label = raw['label'];
      if (from is! int || to is! int || from > to) {
        throw const FormatException('each band needs "from" <= "to"');
      }
      if (label is! String || label.trim().isEmpty) {
        throw const FormatException('each band needs a "label"');
      }
      bands.add(ScaleBand(from, to, label));
    }
  }

  final mdc = json['mdc'];
  if (mdc != null && mdc is! int) {
    throw const FormatException('"mdc" must be a whole number, or absent');
  }
  final minAnswered = json['minAnswered'];
  if (minAnswered != null && minAnswered is! int) {
    throw const FormatException('"minAnswered" must be a whole number');
  }
  if (minAnswered is int && minAnswered > items.length) {
    throw FormatException(
      '"minAnswered" is $minAnswered but the scale has ${items.length} items',
    );
  }

  final higher = json['higherIsBetter'];
  if (higher is! bool) {
    throw const FormatException('"higherIsBetter" must be true or false');
  }

  return ScaleDef(
    id: str('id'),
    name: str('name'),
    short: str('short'),
    region: str('region'),
    kind: kind,
    unit: str('unit'),
    higherIsBetter: higher,
    source: str('source'),
    items: items,
    bands: bands,
    mdc: mdc as int?,
    minAnswered: minAnswered is int ? minAnswered : 0,
    usageNote: json['usageNote'] is String ? json['usageNote'] as String : '',
    instruction: json['instruction'] is String
        ? json['instruction'] as String
        : '',
  );
}

/// Loads every questionnaire asset, alongside the built-in measures.
///
/// [bundle] is injectable so this can be tested without a Flutter app.
Future<ScaleLoad> loadOutcomeScales({
  AssetBundle? bundle,
  List<String> assets = kScaleAssets,
}) async {
  final from = bundle ?? rootBundle;
  final scales = <ScaleDef>[...kBuiltInScales];
  final problems = <String>[];
  final seen = {for (final s in scales) s.id};

  for (final path in assets) {
    try {
      final text = await from.loadString(path);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('the file must hold one JSON object');
      }
      final scale = scaleFromJson(decoded);
      if (!seen.add(scale.id)) {
        problems.add(
          '$path — a scale with id "${scale.id}" is already '
          'loaded, so this file was skipped',
        );
        continue;
      }
      scales.add(scale);
    } on FormatException catch (e) {
      problems.add('$path — ${e.message}');
    } catch (_) {
      // Almost always a missing asset: the clinic has not supplied its
      // licensed copy of this instrument yet.
      problems.add('$path — not found or unreadable');
    }
  }

  return ScaleLoad(scales, problems);
}

/// The scales available to this app, loaded once.
final outcomeScalesProvider = FutureProvider<ScaleLoad>(
  (ref) => loadOutcomeScales(),
);
