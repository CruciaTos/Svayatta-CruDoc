// Moves the ODI from Dart source into the asset JSON the app now loads.
//
// Run from the CruDoc directory:
//
//   dart run tool/export_odi_scale.dart
//
// Why a script instead of writing the JSON by hand: the item wording is the
// instrument, and retyping it is how a validated scale quietly stops being
// that scale. This copies the strings across mechanically, so what ends up
// in the asset is character-for-character what was already there.
//
// Once the asset is in place and the app loads it, `odi_scale.dart` is dead
// weight and can be deleted — the instrument then lives in one place, which
// is the clinic's own licensed copy.

import 'dart:convert';
import 'dart:io';

import 'package:doctor_management_app/features/therapy/data/outcome_scale.dart';
import 'package:doctor_management_app/features/therapy/data/scales/odi_scale.dart';

/// The JSON shape the registry reads. Kept here rather than on [ScaleDef]
/// itself: the app only ever needs to read these files, so a writer on the
/// model would be a method nothing in the app calls.
Map<String, dynamic> scaleToJson(ScaleDef s) => {
  'id': s.id,
  'name': s.name,
  'short': s.short,
  'region': s.region,
  'kind': s.isQuestionnaire ? 'questionnaire' : 'measured',
  'unit': s.unit,
  'higherIsBetter': s.higherIsBetter,
  'source': s.source,
  if (s.instruction.isNotEmpty) 'instruction': s.instruction,
  if (s.usageNote.isNotEmpty) 'usageNote': s.usageNote,
  'mdc': s.mdc,
  'minAnswered': s.minAnswered,
  'bands': [
    for (final b in s.bands) {'from': b.from, 'to': b.to, 'label': b.label},
  ],
  'items': [
    for (final i in s.items)
      {'id': i.id, 'label': i.label, 'options': i.options},
  ],
};

void main(List<String> args) {
  final dir = Directory('assets/outcome_scales');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final file = File('assets/outcome_scales/odi.json');
  if (file.existsSync() && !args.contains('--force')) {
    stderr.writeln(
      '${file.path} already exists. Pass --force to overwrite it.',
    );
    exitCode = 1;
    return;
  }

  final json = scaleToJson(kOdiScale);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );

  final items = (json['items'] as List).length;
  stdout.writeln('Wrote ${file.path}: $items items.');
}
