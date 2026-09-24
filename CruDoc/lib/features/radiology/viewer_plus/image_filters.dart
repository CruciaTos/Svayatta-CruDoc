import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';

/// Image enhancement the radiologist can turn on in the 2D viewer.
class RadFilterSettings {
  const RadFilterSettings({
    this.gamma = 1.0,
    this.sharpen = 0.0,
    this.clahe = false,
    this.colormap = 'gray',
  });

  /// 0.3–3.0; 1 = none. Applied in the display lookup table (see
  /// [radGammaCurve]).
  final double gamma;

  /// 0–1 unsharp-mask strength; 0 = none. Applied to the values.
  final double sharpen;

  /// Local contrast enhancement (CLAHE). Applied to the values.
  final bool clahe;

  /// 'gray', 'bone', 'hot', 'rainbow'. Applied in the display lookup.
  final String colormap;

  bool get changesValues => sharpen > 0 || clahe;
  bool get isIdentity => gamma == 1.0 && !changesValues && colormap == 'gray';

  RadFilterSettings copyWith({double? gamma, double? sharpen, bool? clahe, String? colormap}) =>
      RadFilterSettings(
        gamma: gamma ?? this.gamma,
        sharpen: sharpen ?? this.sharpen,
        clahe: clahe ?? this.clahe,
        colormap: colormap ?? this.colormap,
      );

  Map<String, dynamic> toJson() =>
      {'gamma': gamma, 'sharpen': sharpen, 'clahe': clahe, 'colormap': colormap};

  factory RadFilterSettings.fromJson(Map<String, dynamic> j) => RadFilterSettings(
        gamma: (j['gamma'] as num?)?.toDouble() ?? 1.0,
        sharpen: (j['sharpen'] as num?)?.toDouble() ?? 0.0,
        clahe: j['clahe'] == true,
        colormap: j['colormap'] as String? ?? 'gray',
      );
}

/// The values with sharpening / CLAHE applied (same length as
/// `px.values`). Runs off the UI thread. Returns `px.values` unchanged
/// when [f] doesn't change values.
Future<Float32List> applyValueFilters(RadPixels px, RadFilterSettings f) async {
  if (!f.changesValues) return px.values;
  final values = px.values;
  final w = px.width, h = px.height;
  // CLAHE bins the display range (the 0.5–99.5th percentiles) so a few
  // burnt-out or metal pixels don't flatten the histogram.
  final lo = px.lowPct, hi = px.highPct;
  final sharpen = f.sharpen.clamp(0.0, 1.0);
  final clahe = f.clahe;
  return Isolate.run(
    () => _filterValues(values, w, h, lo: lo, hi: hi, sharpen: sharpen, clahe: clahe),
  );
}

/// Display value for [t] (0–1 after the window) with [gamma] applied:
/// above 1 lifts the mid-tones, below 1 deepens them.
double radGammaCurve(double t, double gamma) {
  if (gamma == 1.0 || t <= 0 || t >= 1) return t.clamp(0.0, 1.0);
  return math.pow(t, 1 / gamma).toDouble();
}

/// 256 RGB triples (768 bytes) for a colour map; 'gray' is a ramp.
Uint8List colormapLut(String name) {
  final out = Uint8List(768);
  for (var i = 0; i < 256; i++) {
    final t = i / 255;
    final (r, g, b) = switch (name) {
      'bone' => _bone(t),
      'hot' => _hot(t),
      'rainbow' => _rainbow(t),
      _ => (t, t, t),
    };
    out[i * 3] = _byte(r);
    out[i * 3 + 1] = _byte(g);
    out[i * 3 + 2] = _byte(b);
  }
  return out;
}

/// Colour maps offered in the viewer.
const radColormaps = ['gray', 'bone', 'hot', 'rainbow'];

/// "Grey", "Bone", "Hot", "Rainbow".
String radColormapLabel(String name) => switch (name) {
      'bone' => 'Bone',
      'hot' => 'Hot',
      'rainbow' => 'Rainbow',
      _ => 'Grey',
    };

// ───────────────────────────── Colour maps ─────────────────────────────

int _byte(double v) => (v.clamp(0.0, 1.0) * 255).round();

double _unit(double v) => v.clamp(0.0, 1.0);

/// Black → red → yellow → white.
(double, double, double) _hot(double t) =>
    (_unit(t / 0.375), _unit((t - 0.375) / 0.375), _unit((t - 0.75) / 0.25));

/// Grey with a cool blue cast in the shadows (7 parts grey, 1 part
/// reversed hot), the classic bone map.
(double, double, double) _bone(double t) {
  final (hr, hg, hb) = _hot(t);
  return ((7 * t + hb) / 8, (7 * t + hg) / 8, (7 * t + hr) / 8);
}

/// Blue (low) through green to red (high), fading up from dark blue so
/// the background stays dark.
(double, double, double) _rainbow(double t) {
  final (r, g, b) = _hsv((1 - t) * 240, 1, 0.35 + 0.65 * _unit(t * 3));
  return (r, g, b);
}

(double, double, double) _hsv(double hue, double s, double v) {
  final h = (hue % 360) / 60;
  final c = v * s;
  final x = c * (1 - ((h % 2) - 1).abs());
  final m = v - c;
  final (r, g, b) = switch (h.floor()) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  return (r + m, g + m, b + m);
}

// ───────────────────────────── Value filters ─────────────────────────────

/// CLAHE grid: 8 × 8 tiles.
const int _claheTiles = 8;

/// Histogram bins per tile. 1024 keeps 12–16-bit radiographs smooth.
const int _claheBins = 1024;

/// A tile's histogram may reach this many times the average bin count
/// before the excess is spread out: lifts faint detail without turning
/// noise into texture.
const double _claheClip = 2.5;

Float32List _filterValues(
  Float32List values,
  int w,
  int h, {
  required double lo,
  required double hi,
  required double sharpen,
  required bool clahe,
}) {
  var out = values;
  if (clahe && hi > lo && w >= _claheTiles * 4 && h >= _claheTiles * 4) {
    out = _clahe(out, w, h, lo, hi);
  }
  if (sharpen > 0) out = _unsharp(out, w, h, sharpen);
  return out;
}

/// Contrast-limited adaptive histogram equalisation. The result is mapped
/// back into [lo]..[hi] so the viewer's default window still fits.
Float32List _clahe(Float32List v, int w, int h, double lo, double hi) {
  const tiles = _claheTiles;
  const bins = _claheBins;
  final range = hi - lo;
  final toBin = (bins - 1) / range;

  final idx = Uint16List(v.length);
  for (var i = 0; i < v.length; i++) {
    final b = ((v[i] - lo) * toBin).round();
    idx[i] = b < 0 ? 0 : (b >= bins ? bins - 1 : b);
  }

  // One clipped, equalised mapping (0–1) per tile.
  final maps = Float32List(tiles * tiles * bins);
  final hist = Int32List(bins);
  for (var ty = 0; ty < tiles; ty++) {
    final y0 = (ty * h / tiles).floor();
    final y1 = ((ty + 1) * h / tiles).floor();
    for (var tx = 0; tx < tiles; tx++) {
      final x0 = (tx * w / tiles).floor();
      final x1 = ((tx + 1) * w / tiles).floor();
      hist.fillRange(0, bins, 0);
      for (var y = y0; y < y1; y++) {
        final row = y * w;
        for (var x = x0; x < x1; x++) {
          hist[idx[row + x]]++;
        }
      }
      final count = (x1 - x0) * (y1 - y0);
      final limit = math.max(1, (_claheClip * count / bins).round());
      var excess = 0;
      for (var b = 0; b < bins; b++) {
        if (hist[b] > limit) {
          excess += hist[b] - limit;
          hist[b] = limit;
        }
      }
      final spread = excess ~/ bins;
      final rest = excess - spread * bins;
      final base = (ty * tiles + tx) * bins;
      var acc = 0;
      for (var b = 0; b < bins; b++) {
        acc += hist[b] + spread + (b < rest ? 1 : 0);
        maps[base + b] = acc / count;
      }
    }
  }

  // Blend the four nearest tile mappings (bilinear across tile centres).
  final tx0 = Int32List(w), tx1 = Int32List(w);
  final ax = Float32List(w);
  for (var x = 0; x < w; x++) {
    final (a, b, f) = _tileBlend((x + 0.5) * tiles / w - 0.5, tiles);
    tx0[x] = a;
    tx1[x] = b;
    ax[x] = f;
  }
  final out = Float32List(v.length);
  for (var y = 0; y < h; y++) {
    final (ty0, ty1, ay) = _tileBlend((y + 0.5) * tiles / h - 0.5, tiles);
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final b = idx[row + x];
      final fx = ax[x];
      final top = maps[(ty0 * tiles + tx0[x]) * bins + b] * (1 - fx) +
          maps[(ty0 * tiles + tx1[x]) * bins + b] * fx;
      final bottom = maps[(ty1 * tiles + tx0[x]) * bins + b] * (1 - fx) +
          maps[(ty1 * tiles + tx1[x]) * bins + b] * fx;
      out[row + x] = lo + (top * (1 - ay) + bottom * ay) * range;
    }
  }
  return out;
}

/// The two tiles around fractional tile position [f] and the weight of
/// the second one (edges use one tile).
(int, int, double) _tileBlend(double f, int tiles) {
  if (f <= 0) return (0, 0, 0);
  if (f >= tiles - 1) return (tiles - 1, tiles - 1, 0);
  final a = f.floor();
  return (a, a + 1, f - a);
}

/// Unsharp mask: adds back the detail a ~2.5 px Gaussian blur removes.
Float32List _unsharp(Float32List v, int w, int h, double strength) {
  // Three box blurs approximate a Gaussian.
  final blur = _boxBlur(_boxBlur(_boxBlur(v, w, h, 2), w, h, 2), w, h, 2);
  final amount = strength * 1.5;
  final out = Float32List(v.length);
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] + amount * (v[i] - blur[i]);
  }
  return out;
}

/// Separable box blur of radius [r] with clamped edges.
Float32List _boxBlur(Float32List src, int w, int h, int r) {
  final n = 2 * r + 1;
  final tmp = Float32List(src.length);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    var sum = 0.0;
    for (var k = -r; k <= r; k++) {
      sum += src[row + k.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[row + x] = sum / n;
      sum += src[row + (x + r + 1).clamp(0, w - 1)] - src[row + (x - r).clamp(0, w - 1)];
    }
  }
  final out = Float32List(src.length);
  for (var x = 0; x < w; x++) {
    var sum = 0.0;
    for (var k = -r; k <= r; k++) {
      sum += tmp[k.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      out[y * w + x] = sum / n;
      sum += tmp[(y + r + 1).clamp(0, h - 1) * w + x] - tmp[(y - r).clamp(0, h - 1) * w + x];
    }
  }
  return out;
}
