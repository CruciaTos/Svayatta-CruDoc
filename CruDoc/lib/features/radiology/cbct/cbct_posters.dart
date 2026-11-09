import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A volume in memory: int16 voxels, x fastest, with its geometry. The
/// direction holds the row, column and slice unit vectors (9 numbers, LPS).
class CbctVolume {
  const CbctVolume({
    required this.data,
    required this.dims,
    required this.spacing,
    required this.origin,
    required this.direction,
  });

  final Int16List data;
  final List<int> dims;
  final List<double> spacing;
  final List<double> origin;
  final List<double> direction;
}

/// The three plane posters: which LPS axis runs to the right of the picture,
/// which runs up (negative = the picture's top is the axis' low end) and
/// which one the plane cuts through.
enum CbctPlane {
  axial(right: 0, up: 1, upSign: -1, normal: 2),
  coronal(right: 0, up: 2, upSign: 1, normal: 1),
  sagittal(right: 1, up: 2, upSign: 1, normal: 0);

  const CbctPlane({
    required this.right,
    required this.up,
    required this.upSign,
    required this.normal,
  });
  final int right, up, upSign, normal;
}

/// For each LPS axis k: the voxel axis that runs along it and the sign
/// (+1 when the voxel index grows with the LPS coordinate).
List<(int, int)> _lpsMap(List<double> dir) {
  final map = List<(int, int)>.filled(3, (0, 1));
  final used = <int>{};
  for (var a = 0; a < 3; a++) {
    var k = 0;
    for (var i = 1; i < 3; i++) {
      if (dir[a * 3 + i].abs() > dir[a * 3 + k].abs()) k = i;
    }
    if (!used.add(k)) return [(0, 1), (1, 1), (2, 1)];
    map[k] = (a, dir[a * 3 + k] >= 0 ? 1 : -1);
  }
  return map;
}

int _grey(double v, double low, double high) {
  final t = (v - low) / (high - low <= 0 ? 1 : high - low);
  return t <= 0 ? 0 : (t >= 1 ? 255 : (t * 255).round());
}

Uint8List _png(Uint8List grey, int w, int h) {
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: grey.buffer,
    numChannels: 1,
  );
  return Uint8List.fromList(img.encodePng(image));
}

/// The plane through the volume centre, trilinearly sampled over its FULL
/// extent, windowed [low]..[high] to 8-bit grey; long side <= [maxSide].
Uint8List renderPlanePoster(
  CbctVolume v,
  CbctPlane plane,
  double low,
  double high, {
  int maxSide = 1024,
}) {
  final map = _lpsMap(v.direction);
  final (ar, sr) = map[plane.right];
  final (au, su) = map[plane.up];
  final (an, _) = map[plane.normal];
  final uExt = v.dims[ar] * v.spacing[ar];
  final vExt = v.dims[au] * v.spacing[au];
  final scale = maxSide / math.max(uExt, vExt);
  final w = math.max(1, (uExt * scale).round());
  final h = math.max(1, (vExt * scale).round());

  // Voxel coordinate along the right axis for each column, along the up
  // axis for each row.
  final cx = Float64List(w), cy = Float64List(h);
  for (var i = 0; i < w; i++) {
    final t = (i + 0.5) / w;
    cx[i] = (sr > 0 ? t : 1 - t) * v.dims[ar] - 0.5;
  }
  for (var j = 0; j < h; j++) {
    final f = (j + 0.5) / h; // top to bottom
    final t = plane.upSign > 0 ? 1 - f : f; // along the LPS axis, low to high
    cy[j] = (su > 0 ? t : 1 - t) * v.dims[au] - 0.5;
  }
  final cn = v.dims[an] / 2 - 0.5;

  final out = Uint8List(w * h);
  final c = List<double>.filled(3, 0);
  c[an] = cn;
  for (var j = 0; j < h; j++) {
    c[au] = cy[j];
    for (var i = 0; i < w; i++) {
      c[ar] = cx[i];
      out[j * w + i] = _grey(_trilinear(v, c[0], c[1], c[2]), low, high);
    }
  }
  return _png(out, w, h);
}

double _trilinear(CbctVolume v, double x, double y, double z) {
  final nx = v.dims[0], ny = v.dims[1], nz = v.dims[2];
  x = x < 0 ? 0 : (x > nx - 1 ? nx - 1.0 : x);
  y = y < 0 ? 0 : (y > ny - 1 ? ny - 1.0 : y);
  z = z < 0 ? 0 : (z > nz - 1 ? nz - 1.0 : z);
  final x0 = x.floor(), y0 = y.floor(), z0 = z.floor();
  final x1 = math.min(nx - 1, x0 + 1);
  final y1 = math.min(ny - 1, y0 + 1);
  final z1 = math.min(nz - 1, z0 + 1);
  final fx = x - x0, fy = y - y0, fz = z - z0;
  final d = v.data;
  double at(int xx, int yy, int zz) => d[(zz * ny + yy) * nx + xx].toDouble();
  final c00 = at(x0, y0, z0) * (1 - fx) + at(x1, y0, z0) * fx;
  final c10 = at(x0, y1, z0) * (1 - fx) + at(x1, y1, z0) * fx;
  final c01 = at(x0, y0, z1) * (1 - fx) + at(x1, y0, z1) * fx;
  final c11 = at(x0, y1, z1) * (1 - fx) + at(x1, y1, z1) * fx;
  return (c00 * (1 - fy) + c10 * fy) * (1 - fz) + (c01 * (1 - fy) + c11 * fy) * fz;
}

double _dot(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

/// Maximum-intensity projection of [v] along the viewer's first 3D camera
/// (parallel projection), windowed [low]..[high]; long side <= [maxSide].
Uint8List renderMipPoster(
  CbctVolume v,
  double low,
  double high, {
  int maxSide = 768,
}) {
  final s30 = math.sin(30 * math.pi / 180), c30 = math.cos(30 * math.pi / 180);
  final s20 = math.sin(20 * math.pi / 180), c20 = math.cos(20 * math.pi / 180);
  final n = <double>[-s30 * c20, -c30 * c20, s20];
  final nz = n[2];
  var up = <double>[-nz * n[0], -nz * n[1], 1 - nz * n[2]];
  final ul = math.sqrt(_dot(up, up));
  up = [for (final e in up) e / ul];
  // right = up x n
  final right = <double>[
    up[1] * n[2] - up[2] * n[1],
    up[2] * n[0] - up[0] * n[2],
    up[0] * n[1] - up[1] * n[0],
  ];

  final dir = [
    v.direction.sublist(0, 3),
    v.direction.sublist(3, 6),
    v.direction.sublist(6, 9),
  ];
  final ext = [for (var a = 0; a < 3; a++) v.dims[a] * v.spacing[a]];
  // Centre of the volume's box in LPS.
  final centre = <double>[
    for (var k = 0; k < 3; k++)
      v.origin[k] +
          dir[0][k] * (v.dims[0] - 1) / 2 * v.spacing[0] +
          dir[1][k] * (v.dims[1] - 1) / 2 * v.spacing[1] +
          dir[2][k] * (v.dims[2] - 1) / 2 * v.spacing[2],
  ];
  final radius = 0.5 * math.sqrt(_dot(ext, ext));

  // Projected bounds of the box.
  var umin = double.infinity, umax = -double.infinity;
  var vmin = double.infinity, vmax = -double.infinity;
  for (var m = 0; m < 8; m++) {
    final p = <double>[
      for (var k = 0; k < 3; k++)
        dir[0][k] * ((m & 1) == 1 ? 0.5 : -0.5) * ext[0] +
            dir[1][k] * ((m & 2) == 2 ? 0.5 : -0.5) * ext[1] +
            dir[2][k] * ((m & 4) == 4 ? 0.5 : -0.5) * ext[2],
    ];
    final pu = _dot(p, right), pv = _dot(p, up);
    umin = math.min(umin, pu);
    umax = math.max(umax, pu);
    vmin = math.min(vmin, pv);
    vmax = math.max(vmax, pv);
  }
  final scale = maxSide / math.max(umax - umin, vmax - vmin);
  final w = math.max(1, ((umax - umin) * scale).round());
  final h = math.max(1, ((vmax - vmin) * scale).round());

  final step = v.spacing.reduce(math.min);
  final steps = (2 * radius / step).ceil();
  final dn = [for (var a = 0; a < 3; a++) _dot(n, dir[a]) * step / v.spacing[a]];
  final nx = v.dims[0], ny = v.dims[1], nzv = v.dims[2];
  final data = v.data;
  final out = Uint8List(w * h);

  for (var j = 0; j < h; j++) {
    final pv = vmax - (j + 0.5) / scale;
    for (var i = 0; i < w; i++) {
      final pu = umin + (i + 0.5) / scale;
      // Ray start: the box centre moved across the view plane, back by R.
      final rel = <double>[
        for (var k = 0; k < 3; k++)
          centre[k] + right[k] * pu + up[k] * pv - n[k] * radius - v.origin[k],
      ];
      var i0 = _dot(rel, dir[0]) / v.spacing[0];
      var i1 = _dot(rel, dir[1]) / v.spacing[1];
      var i2 = _dot(rel, dir[2]) / v.spacing[2];
      var best = -32768;
      for (var s = 0; s < steps; s++) {
        final x = i0.round(), y = i1.round(), z = i2.round();
        if (x >= 0 && y >= 0 && z >= 0 && x < nx && y < ny && z < nzv) {
          final val = data[(z * ny + y) * nx + x];
          if (val > best) best = val;
        }
        i0 += dn[0];
        i1 += dn[1];
        i2 += dn[2];
      }
      out[j * w + i] = best == -32768 ? 0 : _grey(best.toDouble(), low, high);
    }
  }
  return _png(out, w, h);
}
