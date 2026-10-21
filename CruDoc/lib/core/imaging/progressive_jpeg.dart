import 'dart:typed_data';

/// Encodes premultiplied RGBA pixels (as `ImageByteFormat.rawRgba` gives
/// them) as a progressive JPEG, flattened onto white.
///
/// A progressive JPEG sends a blurry whole picture first and then sharpens
/// it scan by scan, so a viewer can show any prefix of the file: every
/// extra chunk that arrives sharpens one more band of the picture. Scans use
/// spectral selection only (no successive approximation) with Huffman
/// tables built for each scan. 4:2:0 chroma, JFIF colours.
///
/// Pure Dart and synchronous: run it in an isolate.
Uint8List encodeProgressiveJpeg(
  Uint8List rgba,
  int width,
  int height, {
  int quality = 85,
}) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    throw ArgumentError('Not enough pixels for $width x $height.');
  }
  return _Encoder(rgba, width, height, quality.clamp(1, 95)).encode();
}

/// Natural (row-major) index of each zigzag position.
const List<int> _zigzag = [
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, //
  12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
];

/// ITU T.81 Annex K quantisation tables, natural order.
const List<int> _lumaBase = [
  16, 11, 10, 16, 24, 40, 51, 61, //
  12, 12, 14, 19, 26, 58, 60, 55,
  14, 13, 16, 24, 40, 57, 69, 56,
  14, 17, 22, 29, 51, 87, 80, 62,
  18, 22, 37, 56, 68, 109, 103, 77,
  24, 35, 55, 64, 81, 104, 113, 92,
  49, 64, 78, 87, 103, 121, 120, 101,
  72, 92, 95, 98, 112, 100, 103, 99,
];

const List<int> _chromaBase = [
  17, 18, 24, 47, 99, 99, 99, 99, //
  18, 21, 26, 66, 99, 99, 99, 99,
  24, 26, 56, 99, 99, 99, 99, 99,
  47, 66, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
];

/// AAN DCT scale factors.
const List<double> _aasf = [
  1.0,
  1.387039845,
  1.306562965,
  1.175875602,
  1.0,
  0.785694958,
  0.541196100,
  0.275899379,
];

/// The scan script: (component, first, last coefficient). Component -1 is
/// the DC scan of all three. Luma low frequencies come early, so the shape
/// of everything is there after a small share of the bytes.
const List<(int, int, int)> _scans = [
  (-1, 0, 0),
  (0, 1, 2),
  (0, 3, 5),
  (1, 1, 63),
  (2, 1, 63),
  (0, 6, 9),
  (0, 10, 20),
  (0, 21, 63),
];

class _Encoder {
  _Encoder(this.rgba, this.width, this.height, int quality)
    : mcuX = (width + 15) >> 4,
      mcuY = (height + 15) >> 4 {
    final scale = quality < 50 ? 5000 ~/ quality : 200 - quality * 2;
    for (var i = 0; i < 64; i++) {
      qLuma[i] = ((_lumaBase[i] * scale + 50) ~/ 100).clamp(1, 255);
      qChroma[i] = ((_chromaBase[i] * scale + 50) ~/ 100).clamp(1, 255);
    }
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        final i = row * 8 + col;
        final s = _aasf[row] * _aasf[col] * 8;
        fLuma[i] = 1 / (qLuma[i] * s);
        fChroma[i] = 1 / (qChroma[i] * s);
      }
    }
  }

  final Uint8List rgba;
  final int width;
  final int height;
  final int mcuX;
  final int mcuY;

  final Int32List qLuma = Int32List(64);
  final Int32List qChroma = Int32List(64);
  final Float64List fLuma = Float64List(64);
  final Float64List fChroma = Float64List(64);

  /// Quantised coefficients in zigzag order, 64 per block. Luma blocks sit
  /// on a grid of (mcuX * 2) x (mcuY * 2), chroma on mcuX x mcuY.
  late final Int16List yCoef = Int16List(mcuX * 2 * mcuY * 2 * 64);
  late final Int16List cbCoef = Int16List(mcuX * mcuY * 64);
  late final Int16List crCoef = Int16List(mcuX * mcuY * 64);

  final _BitWriter out = _BitWriter();

  Uint8List encode() {
    _transform();
    _headers();
    for (final (comp, ss, se) in _scans) {
      if (comp < 0) {
        _dcScan();
      } else {
        _acScan(comp, ss, se);
      }
    }
    out.marker(0xD9);
    return out.bytes();
  }

  // ─────────────────────────── Pixels → coefficients ───────────────────────────

  void _transform() {
    final y16 = Float64List(256);
    final cb8 = Float64List(64);
    final cr8 = Float64List(64);
    final block = Float64List(64);
    final yGridW = mcuX * 2;
    for (var my = 0; my < mcuY; my++) {
      for (var mx = 0; mx < mcuX; mx++) {
        cb8.fillRange(0, 64, 0);
        cr8.fillRange(0, 64, 0);
        for (var py = 0; py < 16; py++) {
          var sy = my * 16 + py;
          if (sy >= height) sy = height - 1;
          final rowBase = sy * width;
          final ci = (py >> 1) * 8;
          for (var px = 0; px < 16; px++) {
            var sx = mx * 16 + px;
            if (sx >= width) sx = width - 1;
            final i = (rowBase + sx) * 4;
            // Premultiplied over white: c + (255 - a).
            final cover = 255 - rgba[i + 3];
            var r = rgba[i] + cover;
            var g = rgba[i + 1] + cover;
            var b = rgba[i + 2] + cover;
            if (r > 255) r = 255;
            if (g > 255) g = 255;
            if (b > 255) b = 255;
            y16[py * 16 + px] = 0.299 * r + 0.587 * g + 0.114 * b - 128;
            final c = ci + (px >> 1);
            cb8[c] += -0.168736 * r - 0.331264 * g + 0.5 * b;
            cr8[c] += 0.5 * r - 0.418688 * g - 0.081312 * b;
          }
        }
        for (var by = 0; by < 2; by++) {
          for (var bx = 0; bx < 2; bx++) {
            for (var r = 0; r < 8; r++) {
              final src = (by * 8 + r) * 16 + bx * 8;
              for (var c = 0; c < 8; c++) {
                block[r * 8 + c] = y16[src + c];
              }
            }
            final b = (my * 2 + by) * yGridW + mx * 2 + bx;
            _fdctQuant(block, fLuma, yCoef, b * 64);
          }
        }
        final cb = (my * mcuX + mx) * 64;
        for (var i = 0; i < 64; i++) {
          block[i] = cb8[i] * 0.25;
        }
        _fdctQuant(block, fChroma, cbCoef, cb);
        for (var i = 0; i < 64; i++) {
          block[i] = cr8[i] * 0.25;
        }
        _fdctQuant(block, fChroma, crCoef, cb);
      }
    }
  }

  /// AAN forward DCT of [d] (natural order, level shifted), quantised into
  /// [dst] at [at] in zigzag order.
  static void _fdctQuant(
    Float64List d,
    Float64List fdtbl,
    Int16List dst,
    int at,
  ) {
    for (var pass = 0; pass < 2; pass++) {
      // Rows first (step 1, stride 8), then columns (step 8, stride 1).
      final step = pass == 0 ? 1 : 8;
      final stride = pass == 0 ? 8 : 1;
      for (var n = 0; n < 8; n++) {
        final o = n * stride;
        final d0 = d[o], d1 = d[o + step], d2 = d[o + 2 * step];
        final d3 = d[o + 3 * step], d4 = d[o + 4 * step];
        final d5 = d[o + 5 * step], d6 = d[o + 6 * step];
        final d7 = d[o + 7 * step];
        final t0 = d0 + d7, t7 = d0 - d7;
        final t1 = d1 + d6, t6 = d1 - d6;
        final t2 = d2 + d5, t5 = d2 - d5;
        final t3 = d3 + d4, t4 = d3 - d4;
        // Even part.
        final t10 = t0 + t3, t13 = t0 - t3;
        final t11 = t1 + t2, t12 = t1 - t2;
        d[o] = t10 + t11;
        d[o + 4 * step] = t10 - t11;
        final z1 = (t12 + t13) * 0.707106781;
        d[o + 2 * step] = t13 + z1;
        d[o + 6 * step] = t13 - z1;
        // Odd part.
        final o10 = t4 + t5, o11 = t5 + t6, o12 = t6 + t7;
        final z5 = (o10 - o12) * 0.382683433;
        final z2 = 0.541196100 * o10 + z5;
        final z4 = 1.306562965 * o12 + z5;
        final z3 = o11 * 0.707106781;
        final z11 = t7 + z3, z13 = t7 - z3;
        d[o + 5 * step] = z13 + z2;
        d[o + 3 * step] = z13 - z2;
        d[o + step] = z11 + z4;
        d[o + 7 * step] = z11 - z4;
      }
    }
    for (var k = 0; k < 64; k++) {
      final n = _zigzag[k];
      final v = d[n] * fdtbl[n];
      var q = v > 0 ? (v + 0.5).toInt() : (v - 0.5).toInt();
      final limit = k == 0 ? 2047 : 1023;
      if (q > limit) q = limit;
      if (q < -limit) q = -limit;
      dst[at + k] = q;
    }
  }

  // ─────────────────────────────── Headers ───────────────────────────────

  void _headers() {
    out.marker(0xD8);
    // JFIF APP0.
    out.marker(0xE0);
    out.u16(16);
    for (final b in const [0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1]) {
      out.byte(b);
    }
    out.byte(0);
    out.byte(0);
    // Quantisation tables, zigzag order.
    out.marker(0xDB);
    out.u16(2 + 65 * 2);
    for (final (id, table) in [(0, qLuma), (1, qChroma)]) {
      out.byte(id);
      for (var k = 0; k < 64; k++) {
        out.byte(table[_zigzag[k]]);
      }
    }
    // Progressive frame: Y 2x2, Cb and Cr 1x1.
    out.marker(0xC2);
    out.u16(17);
    out.byte(8);
    out.u16(height);
    out.u16(width);
    out.byte(3);
    for (final (id, sampling, q) in const [
      (1, 0x22, 0),
      (2, 0x11, 1),
      (3, 0x11, 1),
    ]) {
      out.byte(id);
      out.byte(sampling);
      out.byte(q);
    }
  }

  void _dht(int tableClass, int id, _Huffman h) {
    out.marker(0xC4);
    out.u16(2 + 1 + 16 + h.values.length);
    out.byte((tableClass << 4) | id);
    for (var len = 1; len <= 16; len++) {
      out.byte(h.counts[len]);
    }
    for (final v in h.values) {
      out.byte(v);
    }
  }

  void _sos(List<(int, int)> comps, int ss, int se) {
    out.marker(0xDA);
    out.u16(6 + comps.length * 2);
    out.byte(comps.length);
    for (final (id, tables) in comps) {
      out.byte(id);
      out.byte(tables);
    }
    out.byte(ss);
    out.byte(se);
    out.byte(0); // Ah = Al = 0.
  }

  // ──────────────────────────────── Scans ────────────────────────────────

  /// DC of all three components, interleaved by MCU. Table 0 luma, 1 chroma.
  void _dcScan() {
    final coder = _Coder(out, 2);
    void run() {
      final pred = Int32List(3);
      final yGridW = mcuX * 2;
      void dc(int table, int comp, int v) {
        final diff = v - pred[comp];
        pred[comp] = v;
        final s = diff.abs().bitLength;
        coder.symbol(table, s);
        if (s > 0) coder.bits(diff < 0 ? diff - 1 : diff, s);
      }

      for (var my = 0; my < mcuY; my++) {
        for (var mx = 0; mx < mcuX; mx++) {
          for (var by = 0; by < 2; by++) {
            for (var bx = 0; bx < 2; bx++) {
              final b = (my * 2 + by) * yGridW + mx * 2 + bx;
              dc(0, 0, yCoef[b * 64]);
            }
          }
          final c = (my * mcuX + mx) * 64;
          dc(1, 1, cbCoef[c]);
          dc(1, 2, crCoef[c]);
        }
      }
    }

    run();
    coder.buildTables();
    _dht(0, 0, coder.tables[0]);
    _dht(0, 1, coder.tables[1]);
    _sos(const [(1, 0x00), (2, 0x10), (3, 0x10)], 0, 0);
    coder.emitting = true;
    run();
    out.flushBits();
  }

  /// Coefficients [ss]..[se] of one component, block by block over the
  /// component's own size (not the MCU-padded grid).
  void _acScan(int comp, int ss, int se) {
    final Int16List coef;
    final int gridW, blocksW, blocksH;
    if (comp == 0) {
      coef = yCoef;
      gridW = mcuX * 2;
      blocksW = (width + 7) >> 3;
      blocksH = (height + 7) >> 3;
    } else {
      coef = comp == 1 ? cbCoef : crCoef;
      gridW = mcuX;
      blocksW = (((width + 1) >> 1) + 7) >> 3;
      blocksH = (((height + 1) >> 1) + 7) >> 3;
    }
    final coder = _Coder(out, 1);
    void run() {
      var eobRun = 0;
      void flushEob() {
        if (eobRun == 0) return;
        final r = eobRun.bitLength - 1;
        coder.symbol(0, r << 4);
        if (r > 0) coder.bits(eobRun, r);
        eobRun = 0;
      }

      for (var by = 0; by < blocksH; by++) {
        for (var bx = 0; bx < blocksW; bx++) {
          final base = (by * gridW + bx) * 64;
          var zeros = 0;
          for (var k = ss; k <= se; k++) {
            final v = coef[base + k];
            if (v == 0) {
              zeros++;
              continue;
            }
            flushEob();
            while (zeros > 15) {
              coder.symbol(0, 0xF0);
              zeros -= 16;
            }
            final s = v.abs().bitLength;
            coder.symbol(0, (zeros << 4) | s);
            coder.bits(v < 0 ? v - 1 : v, s);
            zeros = 0;
          }
          if (zeros > 0) {
            eobRun++;
            if (eobRun == 0x7FFF) flushEob();
          }
        }
      }
      flushEob();
    }

    run();
    coder.buildTables();
    _dht(1, 0, coder.tables[0]);
    _sos([(comp + 1, 0x00)], ss, se);
    coder.emitting = true;
    run();
    out.flushBits();
  }
}

/// Counts symbols on the first pass, writes them on the second.
class _Coder {
  _Coder(this.out, int tableCount)
    : freq = List.generate(tableCount, (_) => Int32List(257));

  final _BitWriter out;
  final List<Int32List> freq;
  late final List<_Huffman> tables;
  bool emitting = false;

  void symbol(int table, int s) {
    if (emitting) {
      final h = tables[table];
      out.bits(h.codes[s], h.sizes[s]);
    } else {
      freq[table][s]++;
    }
  }

  void bits(int value, int count) {
    if (emitting) out.bits(value, count);
  }

  void buildTables() {
    tables = [for (final f in freq) _Huffman.optimal(f)];
  }
}

/// A Huffman table built from symbol counts (ITU T.81 Annex K.2), at most
/// 16 bits per code and no all-ones code.
class _Huffman {
  _Huffman._(this.counts, this.values) {
    var code = 0;
    var k = 0;
    for (var len = 1; len <= 16; len++) {
      for (var n = 0; n < counts[len]; n++) {
        final sym = values[k++];
        codes[sym] = code;
        sizes[sym] = len;
        code++;
      }
      code <<= 1;
    }
  }

  factory _Huffman.optimal(Int32List counted) {
    final freq = List<int>.generate(257, (i) => i < 256 ? counted[i] : 1);
    final codeSize = Int32List(257);
    final others = Int32List(257)..fillRange(0, 257, -1);
    while (true) {
      var c1 = -1;
      var v = 1 << 62;
      for (var i = 0; i <= 256; i++) {
        if (freq[i] != 0 && freq[i] <= v) {
          v = freq[i];
          c1 = i;
        }
      }
      var c2 = -1;
      v = 1 << 62;
      for (var i = 0; i <= 256; i++) {
        if (freq[i] != 0 && freq[i] <= v && i != c1) {
          v = freq[i];
          c2 = i;
        }
      }
      if (c2 < 0) break;
      freq[c1] += freq[c2];
      freq[c2] = 0;
      codeSize[c1]++;
      while (others[c1] >= 0) {
        c1 = others[c1];
        codeSize[c1]++;
      }
      others[c1] = c2;
      codeSize[c2]++;
      while (others[c2] >= 0) {
        c2 = others[c2];
        codeSize[c2]++;
      }
    }
    var maxLen = 0;
    for (final s in codeSize) {
      if (s > maxLen) maxLen = s;
    }
    final bits = Int32List(maxLen < 17 ? 18 : maxLen + 1);
    for (var i = 0; i <= 256; i++) {
      if (codeSize[i] > 0) bits[codeSize[i]]++;
    }
    for (var i = bits.length - 1; i > 16; i--) {
      while (bits[i] > 0) {
        var j = i - 2;
        while (bits[j] == 0) {
          j--;
        }
        bits[i] -= 2;
        bits[i - 1]++;
        bits[j + 1] += 2;
        bits[j]--;
      }
    }
    // Drop the reserved symbol 256, which holds one of the longest codes.
    var i = 16;
    while (bits[i] == 0) {
      i--;
    }
    bits[i]--;
    final values = <int>[];
    for (var len = 1; len <= maxLen; len++) {
      for (var j = 0; j < 256; j++) {
        if (codeSize[j] == len) values.add(j);
      }
    }
    return _Huffman._(Int32List.fromList(bits.sublist(0, 17)), values);
  }

  /// How many codes of each length, index 1..16.
  final Int32List counts;
  final List<int> values;
  final Int32List codes = Int32List(256);
  final Int32List sizes = Int32List(256);
}

class _BitWriter {
  Uint8List _buf = Uint8List(1 << 16);
  int _len = 0;
  int _acc = 0;
  int _count = 0;

  void byte(int b) {
    if (_len == _buf.length) {
      _buf = Uint8List(_buf.length * 2)..setRange(0, _len, _buf);
    }
    _buf[_len++] = b;
  }

  void u16(int v) {
    byte((v >> 8) & 0xFF);
    byte(v & 0xFF);
  }

  void marker(int m) {
    byte(0xFF);
    byte(m);
  }

  /// The low [count] bits of [value], most significant first, with 0xFF
  /// stuffed as 0xFF 0x00.
  void bits(int value, int count) {
    _acc = (_acc << count) | (value & ((1 << count) - 1));
    _count += count;
    while (_count >= 8) {
      final b = (_acc >> (_count - 8)) & 0xFF;
      byte(b);
      if (b == 0xFF) byte(0);
      _count -= 8;
    }
    _acc &= (1 << _count) - 1;
  }

  /// Pads the last byte with ones, as T.81 asks.
  void flushBits() {
    if (_count > 0) bits((1 << (8 - _count)) - 1, 8 - _count);
  }

  Uint8List bytes() => Uint8List.sublistView(_buf, 0, _len);
}
