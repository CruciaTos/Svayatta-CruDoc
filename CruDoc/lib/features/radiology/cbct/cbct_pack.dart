import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/features/radiology/cbct/cbct_posters.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/dicom/dicom_file.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';

/// Bump to force every scan to be packed again.
const cbctPackVersion = 3;

/// The most voxels along one axis the viewer loads; bigger scans are
/// averaged down by a whole factor (the DICOM files are never touched).
const _maxAxis = 512;

/// A scan this viewer can't turn into a volume; [message] is fit to show.
class CbctPackException implements Exception {
  CbctPackException(this.message);
  final String message;
  @override
  String toString() => 'CbctPackException: $message';
}

/// A finished pack: the folder holding `full.i16` and `meta.json`, and the
/// parsed `meta.json`.
class CbctPack {
  const CbctPack({required this.dir, required this.meta});
  final Directory dir;
  final Map<String, dynamic> meta;
}

final Map<String, Future<CbctPack>> _inflight = {};

/// Where a study's pack lives and the fingerprint of the files it is made
/// from; a pack with another fingerprint is out of date.
class CbctPlan {
  const CbctPlan({required this.dir, required this.fingerprint});
  final String dir;
  final String fingerprint;
}

/// Plans [study] without reading pixels. Throws [CbctPackException] when the
/// scan can't be a volume.
CbctPlan planCbctPack(RadStudy study, Directory studyDir) {
  final job = _plan(study, studyDir);
  return CbctPlan(dir: job.dir, fingerprint: job.fingerprint);
}

/// The parsed `meta.json` of [dir] when it is a finished, current pack made
/// from files with [fingerprint]; otherwise null.
Future<Map<String, dynamic>?> readReadyCbctMeta(String dir, String fingerprint) async {
  final metaFile = File(p.join(dir, 'meta.json'));
  if (!await metaFile.exists()) return null;
  try {
    final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    final source = meta['source'] as Map<String, dynamic>?;
    if (meta['packVersion'] == cbctPackVersion &&
        source?['fingerprint'] == fingerprint &&
        await File(p.join(dir, 'full.i16')).exists() &&
        await File(p.join(dir, 'preview.i16')).exists()) {
      final vols = meta['volumes'] as Map<String, dynamic>?;
      final lods = vols?['lods'] as List?;
      if (lods != null) {
        for (final entry in lods) {
          if (entry is Map && entry['file'] is String) {
            if (!await File(p.join(dir, entry['file'] as String)).exists()) {
              return null;
            }
          }
        }
      }
      return meta;
    }
  } on Object {
    // Unreadable: pack again.
  }
  return null;
}

/// The ready pack for [study], building it in a background isolate when it
/// is missing or out of date. One build per folder at a time. [onProgress]
/// gets a stage name and 0..1 while it builds.
Future<CbctPack> ensureCbctPack({
  required RadStudy study,
  required Directory studyDir,
  void Function(String stage, double progress)? onProgress,
}) {
  final job = _plan(study, studyDir);
  return _inflight[job.dir] ??= _run(job, onProgress).whenComplete(() {
    // A block body: returning the removed future would make it wait on itself.
    _inflight.remove(job.dir);
  });
}

Future<CbctPack> _run(_Job job, void Function(String, double)? onProgress) async {
  final dir = Directory(job.dir);
  final ready = await readReadyCbctMeta(job.dir, job.fingerprint);
  if (ready != null) return CbctPack(dir: dir, meta: ready);
  final watch = Stopwatch()..start();
  final meta = await _buildInIsolate(job, onProgress);
  debugPrint('[cbct] packed ${job.slices.length} slices in ${watch.elapsedMilliseconds} ms');
  return CbctPack(dir: dir, meta: meta);
}

void _entry(List<Object> args) {
  final port = args[0] as SendPort;
  final job = args[1] as _Job;
  try {
    final meta = _build(job, (stage, p) => port.send(['p', stage, p]));
    port.send(['ok', jsonEncode(meta)]);
  } on CbctPackException catch (e) {
    port.send(['pack', e.message]);
  } on Object catch (e) {
    port.send(['err', '$e']);
  }
}

Future<Map<String, dynamic>> _buildInIsolate(
  _Job job,
  void Function(String, double)? onProgress,
) async {
  final port = ReceivePort();
  final done = Completer<Map<String, dynamic>>();
  final sub = port.listen((m) {
    final msg = m as List;
    switch (msg[0]) {
      case 'p':
        onProgress?.call(msg[1] as String, (msg[2] as num).toDouble());
      case 'ok':
        done.complete(jsonDecode(msg[1] as String) as Map<String, dynamic>);
      case 'pack':
        done.completeError(CbctPackException(msg[1] as String));
      default:
        done.completeError(StateError(msg[1] as String));
    }
  });
  final exit = ReceivePort();
  exit.listen((_) {
    // The result message may still be on its way; give it a moment.
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (!done.isCompleted) done.completeError(StateError('The packer stopped.'));
    });
  });
  try {
    await Isolate.spawn<List<Object>>(_entry, [port.sendPort, job], onExit: exit.sendPort);
    return await done.future;
  } finally {
    await sub.cancel();
    port.close();
    exit.close();
  }
}

// ───────────────────────────── Planning ─────────────────────────────

class _Slice {
  const _Slice(this.path, this.frame, this.key);
  final String path;
  final int frame;

  /// Position along the slice normal (mm), or the instance number when the
  /// file has no position.
  final double key;
}

/// Everything the background isolate needs: plain values only.
class _Job {
  const _Job({
    required this.dir,
    required this.seriesKey,
    required this.fingerprint,
    required this.slices,
    required this.orientation,
    required this.origin,
    required this.pixelSpacing,
    required this.gap,
  });

  final String dir;
  final String seriesKey;
  final String fingerprint;
  final List<_Slice> slices;
  final List<double> orientation;
  final List<double> origin;
  final double pixelSpacing;
  final double gap;
}

String _hex16(String s) => sha256.convert(utf8.encode(s)).toString().substring(0, 16);

_Job _plan(RadStudy study, Directory studyDir) {
  final dicom = study.images.where((i) => i.kind == RadFileKind.dicom).toList();
  if (dicom.isEmpty) throw CbctPackException('This study has no DICOM slices.');

  // The series with the most slices is the scan.
  final bySeries = <String, List<RadImageRef>>{};
  for (final i in dicom) {
    bySeries.putIfAbsent(i.seriesUid, () => []).add(i);
  }
  final series = bySeries.values.reduce(
    (a, b) => _frames(a) >= _frames(b) ? a : b,
  );
  final first = series.first;
  final ori = (first.orientation != null && first.orientation!.length == 6)
      ? first.orientation!
      : const [1.0, 0.0, 0.0, 0.0, 1.0, 0.0];
  final normal = _cross(ori.sublist(0, 3), ori.sublist(3, 6));
  final px = first.pixelSpacingMm ?? 1.0;
  final thickness = first.sliceThickness ?? px;

  final withPosition = series.every((i) => i.position != null && i.position!.length == 3);
  final slices = <_Slice>[];
  for (final i in series) {
    final path = p.join(studyDir.path, i.path);
    final base = withPosition ? _dot(i.position!, normal) : i.instanceNumber.toDouble();
    for (var f = 0; f < math.max(1, i.frames); f++) {
      // One multi-frame file has one position: frames are evenly spaced.
      final key = i.frames > 1 && withPosition ? base + f * thickness : base + f;
      slices.add(_Slice(path, f, key));
    }
  }
  slices.sort((a, b) => a.key.compareTo(b.key));
  if (slices.length < 16) {
    throw CbctPackException('This scan has too few slices for the 3D viewer.');
  }

  var gap = thickness;
  if (withPosition) {
    final diffs = <double>[
      for (var i = 1; i < slices.length; i++) slices[i].key - slices[i - 1].key,
    ]..sort();
    gap = diffs[diffs.length ~/ 2];
    if (gap <= 1e-6 || diffs.first < gap * 0.98 || diffs.last > gap * 1.02) {
      throw CbctPackException(
        "This scan's slices aren't evenly spaced. Use the 2D viewer.",
      );
    }
  }

  var origin = const [0.0, 0.0, 0.0];
  if (withPosition) {
    // The lowest slice's position: first.position moved along the normal.
    final lowest = series.reduce(
      (a, b) => _dot(a.position!, normal) <= _dot(b.position!, normal) ? a : b,
    );
    origin = lowest.position!;
  }

  final ids = series.map((i) => '${i.id}:${_size(studyDir, i)}').join('|');
  return _Job(
    dir: p.join(studyDir.path, '.cbct', _hex16(first.seriesUid.isNotEmpty ? first.seriesUid : ids)),
    seriesKey: _hex16(first.seriesUid.isNotEmpty ? first.seriesUid : ids),
    fingerprint: sha256.convert(utf8.encode(ids)).toString(),
    slices: slices,
    orientation: ori,
    origin: origin,
    pixelSpacing: px,
    gap: gap,
  );
}

int _frames(List<RadImageRef> l) => l.fold(0, (n, i) => n + math.max(1, i.frames));

int _size(Directory studyDir, RadImageRef i) {
  try {
    return File(p.join(studyDir.path, i.path)).lengthSync();
  } on Object {
    return 0;
  }
}

List<double> _cross(List<double> a, List<double> b) => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
];

double _dot(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

// ───────────────────────────── Building (isolate) ─────────────────────────────

typedef _Report = void Function(String stage, double progress);

/// Box-averages [src] by a whole [f] along every axis (edge boxes average
/// the voxels they have).
(Int16List, List<int>) _downsample(Int16List src, List<int> d, int f) {
  final nx = (d[0] / f).ceil(), ny = (d[1] / f).ceil(), nz = (d[2] / f).ceil();
  final out = Int16List(nx * ny * nz);
  final acc = Int32List(nx * ny);
  final cnt = Int32List(nx * ny);
  for (var oz = 0; oz < nz; oz++) {
    acc.fillRange(0, acc.length, 0);
    cnt.fillRange(0, cnt.length, 0);
    for (var z = oz * f; z < math.min(d[2], oz * f + f); z++) {
      final zb = z * d[0] * d[1];
      for (var y = 0; y < d[1]; y++) {
        final row = (y ~/ f) * nx;
        final sb = zb + y * d[0];
        for (var x = 0; x < d[0]; x++) {
          final o = row + x ~/ f;
          acc[o] += src[sb + x];
          cnt[o]++;
        }
      }
    }
    final base = oz * nx * ny;
    for (var i = 0; i < acc.length; i++) {
      out[base + i] = (acc[i] / math.max(1, cnt[i])).round();
    }
  }
  return (out, [nx, ny, nz]);
}

Uint8List _bytes(Int16List v) => v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes);

void _writeAtomic(String dir, String name, List<int> bytes) {
  final tmp = File(p.join(dir, '$name.tmp'));
  tmp.writeAsBytesSync(bytes, flush: true);
  tmp.renameSync(p.join(dir, name));
}

Map<String, dynamic> _build(_Job job, _Report report) {
  final slices = job.slices;
  final n = slices.length;

  RadPixels decode(_Slice s) => decodeRadPixels(
    File(s.path).readAsBytesSync(),
    RadFileKind.dicom,
    frame: s.frame,
  );

  final probe = decode(slices.first);
  final w = probe.width, h = probe.height;
  final f = math.max(1, (math.max(math.max(w, h), n) / _maxAxis).ceil());
  final dx = (w / f).ceil(), dy = (h / f).ceil(), dz = (n / f).ceil();
  final out = Int16List(dx * dy * dz);

  final acc = Float32List(dx * dy);
  final cnt = Int32List(dx * dy);
  for (var z = 0; z < dz; z++) {
    report('Reading slices', 0.6 * z / dz);
    acc.fillRange(0, acc.length, 0);
    cnt.fillRange(0, cnt.length, 0);
    for (var s = z * f; s < math.min(n, z * f + f); s++) {
      final px = s == 0 ? probe : decode(slices[s]);
      if (px.width != w || px.height != h) {
        throw CbctPackException("This scan's slices differ in size. Use the 2D viewer.");
      }
      final v = px.values;
      for (var y = 0; y < h; y++) {
        final row = (y ~/ f) * dx;
        for (var x = 0; x < w; x++) {
          final o = row + x ~/ f;
          acc[o] += v[y * w + x];
          cnt[o]++;
        }
      }
    }
    final base = z * dx * dy;
    for (var i = 0; i < acc.length; i++) {
      final v = (acc[i] / math.max(1, cnt[i])).round();
      out[base + i] = v < -32768 ? -32768 : (v > 32767 ? 32767 : v);
    }
  }

  report('Measuring', 0.62);
  final stats = _landmarks(out);

  final dir = Directory(job.dir)..createSync(recursive: true);
  final spacing = [job.pixelSpacing * f, job.pixelSpacing * f, job.gap * f];
  final ori = job.orientation;
  final normal = _cross(ori.sublist(0, 3), ori.sublist(3, 6));
  final direction = [...ori, ...normal];
  // Averaging f voxels puts the new voxel centre (f-1)/2 old voxels along.
  List<double> shifted(List<double> from, List<double> sp, double shiftVox) => [
    for (var i = 0; i < 3; i++)
      from[i] +
          ori[i] * shiftVox * sp[0] +
          ori[3 + i] * shiftVox * sp[1] +
          normal[i] * shiftVox * sp[2],
  ];
  final origin = shifted(
    job.origin,
    [job.pixelSpacing, job.pixelSpacing, job.gap],
    (f - 1) / 2,
  );
  final fullDims = [dx, dy, dz];

  // Preview: at most about 128 along the longest axis, never below 2.
  report('Preview', 0.66);
  final fp = math.max(2, (math.max(dx, math.max(dy, dz)) / 128).ceil());
  final (prevData, prevDims) = _downsample(out, fullDims, fp);
  final prevSpacing = [for (final s in spacing) s * fp];
  final prevOrigin = shifted(origin, spacing, (fp - 1) / 2);

  // Mid: only when a full axis is over 384.
  Int16List? midData;
  List<int>? midDims;
  List<double>? midSpacing, midOrigin;
  final maxFull = math.max(dx, math.max(dy, dz));
  if (maxFull > 384) {
    final fm = (maxFull / 384).ceil();
    final r = _downsample(out, fullDims, fm);
    midData = r.$1;
    midDims = r.$2;
    midSpacing = [for (final s in spacing) s * fm];
    midOrigin = shifted(origin, spacing, (fm - 1) / 2);
  }

  // 3D LOD levels (coarse to fine):
  // lod0: <=128 per axis (points to preview.i16; same data).
  final lod0 = <String, dynamic>{
    'file': 'preview.i16',
    'factor': fp,
    'dims': prevDims,
    'spacing': prevSpacing,
    'origin': prevOrigin,
  };

  // lod1: <=256 per axis (box average). Only when maxFull > 256.
  Int16List? lod1Data;
  Map<String, dynamic>? lod1;
  if (maxFull > 256) {
    final f1 = math.max(2, (maxFull / 256).ceil());
    final r1 = _downsample(out, fullDims, f1);
    lod1Data = r1.$1;
    final lod1Dims = r1.$2;
    final lod1Spacing = [for (final s in spacing) s * f1];
    final lod1Origin = shifted(origin, spacing, (f1 - 1) / 2);
    lod1 = <String, dynamic>{
      'file': 'lod1.i16',
      'factor': f1,
      'dims': lod1Dims,
      'spacing': lod1Spacing,
      'origin': lod1Origin,
    };
  }

  // last level: full volume (full.i16)
  final lodLast = <String, dynamic>{
    'file': 'full.i16',
    'factor': 1,
    'dims': fullDims,
    'spacing': spacing,
    'origin': origin,
  };

  final lods = <Map<String, dynamic>>[
    lod0,
    ?lod1,
    lodLast,
  ];

  String? manufacturer, model;
  try {
    final d = DicomFile.parse(File(slices.first.path).readAsBytesSync());
    manufacturer = d.string(DicomTag.manufacturer);
    model = d.string(DicomTag.modelName);
  } on Object {
    // Optional.
  }

  final meta = <String, dynamic>{
    'packVersion': cbctPackVersion,
    'seriesKey': job.seriesKey,
    'source': {'fingerprint': job.fingerprint},
    'geometry': {
      'dims': fullDims,
      'spacing': spacing,
      'origin': origin,
      'direction': direction,
    },
    'volumes': {
      'full': {'file': 'full.i16', 'dims': fullDims, 'spacing': spacing, 'origin': origin},
      'mid': midData == null
          ? null
          : {'file': 'mid.i16', 'dims': midDims, 'spacing': midSpacing, 'origin': midOrigin},
      'preview': {
        'file': 'preview.i16',
        'factor': fp,
        'dims': prevDims,
        'spacing': prevSpacing,
        'origin': prevOrigin,
      },
      'lods': lods,
    },
    'posters': {
      'axial': 'poster_axial.png',
      'coronal': 'poster_coronal.png',
      'sagittal': 'poster_sagittal.png',
      'threeD': 'poster_3d.png',
    },
    'values': {
      'min': stats.min,
      'max': stats.max,
      'padValue': stats.pad,
      'valueOffset': 0,
    },
    'landmarks': {
      'air': stats.air,
      'soft': stats.soft,
      'bone': stats.bone,
      'teeth': stats.teeth,
      'metal': stats.metal,
    },
    'presets': {
      'bone': {'low': stats.air, 'high': stats.teeth},
      'teeth': {'low': stats.bone, 'high': stats.metal ?? stats.max},
      'soft': {'low': stats.air, 'high': stats.bone},
      'fineBone': {'low': stats.soft, 'high': stats.teeth},
      'full': {'low': stats.min, 'high': stats.max},
    },
    'device': {'manufacturer': manufacturer ?? '', 'model': model ?? ''},
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  };

  // Posters first (the viewer's first frame), then the volumes, and the
  // meta last: meta.json means "complete". Every file lands by rename.
  report('Posters', 0.7);
  final full = CbctVolume(
    data: out,
    dims: fullDims,
    spacing: spacing,
    origin: origin,
    direction: direction,
  );
  final lo = stats.air, hi = stats.teeth;
  _writeAtomic(dir.path, 'poster_axial.png', renderPlanePoster(full, CbctPlane.axial, lo, hi));
  _writeAtomic(dir.path, 'poster_coronal.png', renderPlanePoster(full, CbctPlane.coronal, lo, hi));
  _writeAtomic(dir.path, 'poster_sagittal.png', renderPlanePoster(full, CbctPlane.sagittal, lo, hi));
  report('3D poster', 0.8);
  final previewVol = CbctVolume(
    data: prevData,
    dims: prevDims,
    spacing: prevSpacing,
    origin: prevOrigin,
    direction: direction,
  );
  _writeAtomic(dir.path, 'poster_3d.png', renderMipPoster(previewVol, stats.soft, stats.max));

  report('Saving', 0.9);
  _writeAtomic(dir.path, 'preview.i16', _bytes(prevData));
  if (midData != null) _writeAtomic(dir.path, 'mid.i16', _bytes(midData));
  if (lod1Data != null) _writeAtomic(dir.path, 'lod1.i16', _bytes(lod1Data));
  _writeAtomic(dir.path, 'full.i16', _bytes(out));
  _writeAtomic(dir.path, 'meta.json', utf8.encode(jsonEncode(meta)));
  report('Done', 1);
  return meta;
}

class _Landmarks {
  const _Landmarks({
    required this.min,
    required this.max,
    required this.pad,
    required this.air,
    required this.soft,
    required this.bone,
    required this.teeth,
    required this.metal,
  });
  final double min, max;
  final double? pad;
  final double air, soft, bone, teeth;
  final double? metal;
}

/// Window landmarks from a 4096-bin histogram of the voxels inside the
/// field of view (guide C3): padding left out, air = lowest peak, soft =
/// highest peak below the 75th percentile, teeth = 99.5th percentile.
_Landmarks _landmarks(Int16List v) {
  var mn = 32767, mx = -32768, cntMin = 0;
  for (final x in v) {
    if (x < mn) {
      mn = x;
      cntMin = 1;
    } else if (x == mn) {
      cntMin++;
    }
    if (x > mx) mx = x;
  }
  final pad = cntMin > v.length * 0.2 ? mn : null;
  var lo = mx;
  for (final x in v) {
    if (x != pad && x < lo) lo = x;
  }
  final hi = mx;
  final span = math.max(1, hi - lo);
  const bins = 4096;
  final hist = Int32List(bins);
  var total = 0;
  for (final x in v) {
    if (x == pad) continue;
    hist[(((x - lo) / span) * (bins - 1)).floor()]++;
    total++;
  }
  double valueAt(int b) => lo + (b + 0.5) / bins * span;
  int binAtPct(double pct) {
    final want = total * pct;
    var run = 0;
    for (var b = 0; b < bins; b++) {
      run += hist[b];
      if (run >= want) return b;
    }
    return bins - 1;
  }

  var airBin = 0;
  for (var b = 1; b < (bins * 0.3).floor(); b++) {
    if (hist[b] > hist[airBin]) airBin = b;
  }
  final p75 = binAtPct(0.75);
  // Look for soft tissue past the air peak's own flank (5 % of the range),
  // or the neighbouring air bins would win.
  final firstSoft = airBin + (bins * 0.05).round();
  var softBin = firstSoft;
  for (var b = firstSoft; b <= p75; b++) {
    if (hist[b] > hist[softBin]) softBin = b;
  }
  final air = valueAt(airBin);
  var soft = p75 > firstSoft ? valueAt(softBin) : air + 0.25 * span;
  var teeth = valueAt(binAtPct(0.995));
  if (teeth <= soft) teeth = hi.toDouble();
  if (soft <= air) soft = air + 0.25 * (teeth - air);
  final bone = soft + 0.35 * (teeth - soft);
  final top = valueAt(binAtPct(0.9999));
  return _Landmarks(
    min: mn.toDouble(),
    max: mx.toDouble(),
    pad: pad?.toDouble(),
    air: air,
    soft: soft,
    bone: bone,
    teeth: teeth,
    metal: top > teeth * 1.15 ? top : null,
  );
}
