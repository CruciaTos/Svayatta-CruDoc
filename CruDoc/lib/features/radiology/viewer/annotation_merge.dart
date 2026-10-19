import 'dart:convert';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';

/// Three-way merges of the viewer's working annotations and calibration
/// with the study as it is now in the database, so a save from this
/// device never wipes out what another device added in the meantime.
///
/// [base] is what this viewer last loaded or saved, [local] its working
/// copy, [remote] the study's current copy. Per annotation (by id): a
/// change made here wins; otherwise the remote copy is taken. Something
/// deleted on either side stays deleted unless the other side changed it.
Map<String, List<RadAnnotation>> radMergeAnnotations({
  required Map<String, List<RadAnnotation>> base,
  required Map<String, List<RadAnnotation>> local,
  required Map<String, List<RadAnnotation>> remote,
}) {
  final out = <String, List<RadAnnotation>>{};
  final images = {...base.keys, ...local.keys, ...remote.keys};
  for (final image in images) {
    final b = _byId(base[image]);
    final l = _byId(local[image]);
    final r = _byId(remote[image]);
    final merged = <RadAnnotation>[];
    // Local order first (what the doctor sees), then remote additions.
    final ids = <String>[...l.keys, ...r.keys.where((id) => !l.containsKey(id))];
    for (final id in ids) {
      final pick = _pick(b[id], l[id], r[id]);
      if (pick != null) merged.add(pick);
    }
    if (merged.isNotEmpty) out[image] = merged;
  }
  return out;
}

/// Calibration (mm per pixel by image), merged the same way.
Map<String, double> radMergeCalibration({
  required Map<String, double> base,
  required Map<String, double> local,
  required Map<String, double> remote,
}) {
  final out = <String, double>{};
  for (final image in {...base.keys, ...local.keys, ...remote.keys}) {
    final b = base[image], l = local[image], r = remote[image];
    final v = l != b ? l : r;
    if (v != null) out[image] = v;
  }
  return out;
}

/// True when [a] and [b] hold the same annotations.
bool radSameAnnotations(
  Map<String, List<RadAnnotation>> a,
  Map<String, List<RadAnnotation>> b,
) => _encode(a) == _encode(b);

RadAnnotation? _pick(
  RadAnnotation? base,
  RadAnnotation? local,
  RadAnnotation? remote,
) {
  final localChanged = !_same(base, local);
  final remoteChanged = !_same(base, remote);
  if (localChanged && local != null) return local;
  if (localChanged && local == null) {
    // Deleted here; kept only if the other device changed it meanwhile.
    return remoteChanged ? remote : null;
  }
  // Untouched here: the database's copy (null if deleted there).
  return remote;
}

bool _same(RadAnnotation? a, RadAnnotation? b) {
  if (a == null || b == null) return a == null && b == null;
  return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
}

Map<String, RadAnnotation> _byId(List<RadAnnotation>? list) => {
  for (final a in list ?? const <RadAnnotation>[]) a.id: a,
};

String _encode(Map<String, List<RadAnnotation>> m) {
  final keys = m.keys.where((k) => m[k]!.isNotEmpty).toList()..sort();
  return jsonEncode({
    for (final k in keys) k: [for (final a in m[k]!) a.toJson()],
  });
}
