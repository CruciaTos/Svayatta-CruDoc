import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:doctor_management_app/features/scan/data/docscan/detector.dart';
import 'package:doctor_management_app/features/scan/data/docscan/geometry.dart';
import 'package:doctor_management_app/features/scan/data/docscan/page_render.dart';
import 'package:doctor_management_app/features/scan/data/docscan/pixels.dart';
import 'package:doctor_management_app/features/scan/data/docscan/quality.dart';
import 'package:doctor_management_app/features/scan/data/docscan/scan_engine.dart';

/// Page texture size (A4 proportions).
const pageW = 840.0, pageH = 1188.0;

/// The printed table box on the page, in page units.
const tableTop = 700.0,
    tableBottom = 1000.0,
    tableLeft = 80.0,
    tableRight = 760.0;

int _hash(int a, int b, int seed) {
  var h = a * 374761393 + b * 668265263 + seed * 2147483647;
  h = (h ^ (h >> 13)) * 1274126177;
  return (h ^ (h >> 16)) & 0x7fffffff;
}

/// Paper with lines of "words", a printed table box, and a margin.
double _paper(double u, double v, int seed) {
  // Table border, 4 units thick.
  final inTableBand =
      v >= tableTop && v <= tableBottom && u >= tableLeft && u <= tableRight;
  if (inTableBand &&
      (v - tableTop < 4 ||
          tableBottom - v < 4 ||
          u - tableLeft < 4 ||
          tableRight - u < 4)) {
    return 40;
  }
  // Different sheets have different amounts of writing.
  final textEnd = seed == 1 ? 660.0 : 360.0;
  if (u > 60 && u < pageW - 60 && v > 80 && v < textEnd) {
    final line = (v - 80) ~/ 30;
    final inLine = (v - 80) % 30;
    if (inLine >= 8 && inLine < 22) {
      final word = (u - 60) ~/ 56;
      final inWord = (u - 60) % 56;
      final wordLen = 24 + _hash(line, word, seed) % 28;
      if (inWord < wordLen) {
        // Letter strokes ~2.5 units with gaps.
        final stroke = ((u * 0.4).floor() + _hash(line, word, seed + 1)) % 3;
        if (stroke == 0) return 35;
      }
    }
  }
  return 232;
}

/// A table top with grain and a couple of stray objects.
double _background(int x, int y, double level) {
  final n = (_hash(x, y, 7) % 21) - 10;
  var v = level + n;
  // A pen and a book edge, partly in view.
  if (y > 40 && y < 52 && x > 20 && x < 300) v = 20;
  if (x > 650 && y > 1050) v = level + 45;
  return v;
}

/// An upright grey scene of [w]×[h] with the page mapped onto [corners].
Uint8List renderScene(
  int w,
  int h,
  Quad corners, {
  int seed = 1,
  double background = 80,
  double blurSigma = 0.7,
}) {
  final toPage = Homography.fromPoints(corners.corners, const [
    Pt(0, 0),
    Pt(pageW, 0),
    Pt(pageW, pageH),
    Pt(0, pageH),
  ])!;
  final f = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = toPage.apply(x + 0.5, y + 0.5);
      f[y * w + x] = (p.x >= 0 && p.y >= 0 && p.x < pageW && p.y < pageH)
          ? _paper(p.x, p.y, seed)
          : _background(x, y, background);
    }
  }
  final out = blurSigma > 0 ? _gaussian(f, w, h, blurSigma) : f;
  return Uint8List.fromList([for (final v in out) v.round().clamp(0, 255)]);
}

Float32List _gaussian(Float32List src, int w, int h, double sigma) {
  final r = (sigma * 3).ceil();
  final k = [
    for (var i = -r; i <= r; i++) math.exp(-i * i / (2 * sigma * sigma)),
  ];
  final sum = k.reduce((a, b) => a + b);
  for (var i = 0; i < k.length; i++) {
    k[i] /= sum;
  }
  final tmp = Float32List(w * h), out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var i = -r; i <= r; i++) {
        s += src[y * w + (x + i).clamp(0, w - 1)] * k[i + r];
      }
      tmp[y * w + x] = s;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var i = -r; i <= r; i++) {
        s += tmp[(y + i).clamp(0, h - 1) * w + x] * k[i + r];
      }
      out[y * w + x] = s;
    }
  }
  return out;
}

/// Stores an upright grey scene the way a phone sensor would (landscape,
/// needing a [rotation] clockwise turn), as a YUV frame.
YuvFrame toFrame(Uint8List upright, int w, int h, {int rotation = 90}) {
  final g = rotateGray(GrayImage(w, h, upright), (360 - rotation) % 360);
  final cw = (g.width + 1) >> 1, ch = (g.height + 1) >> 1;
  final chroma = Uint8List(cw * ch)..fillRange(0, cw * ch, 128);
  return YuvFrame(
    sensorWidth: g.width,
    sensorHeight: g.height,
    rotation: rotation,
    y: g.data,
    yRowStride: g.width,
    u: chroma,
    uOffset: 0,
    uRowStride: cw,
    uPixelStride: 1,
    v: chroma,
    vOffset: 0,
    vRowStride: cw,
    vPixelStride: 1,
  );
}

const fw = 720, fh = 1280;

/// A page held with a little perspective, roughly filling the view.
final tilted = Quad(
  const Pt(118, 230),
  const Pt(612, 262),
  const Pt(648, 1010),
  const Pt(84, 1046),
);

final rotated20 = () {
  final c = const Pt(360, 640);
  Pt r(double x, double y) {
    const a = 20 * math.pi / 180;
    final dx = x - c.x, dy = y - c.y;
    return Pt(
      c.x + dx * math.cos(a) - dy * math.sin(a),
      c.y + dx * math.sin(a) + dy * math.cos(a),
    );
  }

  return Quad(r(150, 330), r(570, 330), r(570, 930), r(150, 930));
}();

double _cornerError(Quad found, Quad truth) =>
    found.maxCornerDistance(truth) / math.sqrt(fw * fw + fh * fh);

Detection _detect(YuvFrame frame) =>
    DocumentDetector.detect(frame.downsample(PageRender.detectFactor(frame)));

Quad _detectFull(YuvFrame frame) {
  final f = PageRender.detectFactor(frame);
  final d = DocumentDetector.detect(frame.downsample(f));
  expect(d.status, DetectionStatus.found);
  return frame.fromSmall(d.quad!, f);
}

void main() {
  group('geometry', () {
    test('homography maps corners exactly', () {
      final h = Homography.fromPoints(const [
        Pt(0, 0),
        Pt(100, 0),
        Pt(100, 50),
        Pt(0, 50),
      ], tilted.corners)!;
      final p = h.apply(100, 50);
      expect(p.x, closeTo(tilted.br.x, 1e-6));
      expect(p.y, closeTo(tilted.br.y, 1e-6));
    });

    test('corners are ordered tl, tr, br, bl whatever the input order', () {
      final q = Quad.ordered([tilted.br, tilted.tl, tilted.bl, tilted.tr]);
      expect(q.maxCornerDistance(tilted), 0);
      expect(q.isConvex, isTrue);
    });

    test('a bow-tie is not convex', () {
      final q = Quad(tilted.tl, tilted.br, tilted.tr, tilted.bl);
      expect(q.isConvex, isFalse);
    });
  });

  group('detector', () {
    test('finds a tilted page in a rotated sensor frame', () {
      final frame = toFrame(renderScene(fw, fh, tilted), fw, fh);
      expect(frame.width, fw);
      expect(_cornerError(_detectFull(frame), tilted), lessThan(0.006));
    });

    test('finds a page turned 20 degrees', () {
      final frame = toFrame(renderScene(fw, fh, rotated20), fw, fh);
      final q = _detectFull(frame);
      // Ordering may start at a different corner for a turned page.
      final err = [
        for (var s = 0; s < 4; s++)
          q.maxCornerDistance(
            Quad(
              rotated20.corners[s],
              rotated20.corners[(s + 1) % 4],
              rotated20.corners[(s + 2) % 4],
              rotated20.corners[(s + 3) % 4],
            ),
          ),
      ].reduce(math.min);
      expect(err / math.sqrt(fw * fw + fh * fh), lessThan(0.006));
    });

    test('picks the page, not the table printed on it', () {
      final frame = toFrame(renderScene(fw, fh, tilted), fw, fh);
      final q = _detectFull(frame);
      expect(q.area, greaterThan(tilted.area * 0.95));
    });

    test('white page on a light table', () {
      final frame = toFrame(
        renderScene(fw, fh, tilted, background: 185),
        fw,
        fh,
      );
      expect(_cornerError(_detectFull(frame), tilted), lessThan(0.008));
    });

    test('works in sensor orientations 0, 180 and 270 too', () {
      final scene = renderScene(fw, fh, tilted);
      for (final r in const [0, 180, 270]) {
        final frame = toFrame(scene, fw, fh, rotation: r);
        expect(frame.width, fw, reason: 'rotation $r');
        expect(
          _cornerError(_detectFull(frame), tilted),
          lessThan(0.006),
          reason: 'rotation $r',
        );
      }
    });

    test('a page off the edge is partial, not found', () {
      final off = Quad(
        const Pt(-120, 200),
        const Pt(500, 230),
        const Pt(530, 1000),
        const Pt(-150, 1030),
      );
      final frame = toFrame(renderScene(fw, fh, off), fw, fh);
      expect(_detect(frame).status, isNot(DetectionStatus.found));
    });

    test('an empty table finds nothing', () {
      final empty = Quad(
        const Pt(-5000, -5000),
        const Pt(-4990, -5000),
        const Pt(-4990, -4990),
        const Pt(-5000, -4990),
      );
      final frame = toFrame(renderScene(fw, fh, empty), fw, fh);
      expect(_detect(frame).found, isFalse);
    });
  });

  group('quality', () {
    test('sharpness falls as blur grows', () {
      final values = <double>[];
      for (final sigma in const [0.7, 1.5, 2.5, 4.0]) {
        final frame = toFrame(
          renderScene(fw, fh, tilted, blurSigma: sigma),
          fw,
          fh,
        );
        values.add(PageQuality.sharpness(frame, tilted)!);
      }
      // ignore: avoid_print
      print('sharpness by blur: $values');
      for (var i = 1; i < values.length; i++) {
        expect(values[i], lessThan(values[i - 1]));
      }
      expect(values.first, greaterThan(const ScanTuning().sharpnessFloor));
      expect(values.last, lessThan(const ScanTuning().sharpnessFloor));
    });

    test('lighting sees a dark page and a shadow', () {
      final frame = toFrame(renderScene(fw, fh, tilted), fw, fh);
      final f = PageRender.detectFactor(frame);
      final small = frame.downsample(f);
      final q = tilted.scale(1 / f);
      final ok = PageQuality.lighting(small, q);
      expect(ok.tooDark, isFalse);
      expect(ok.shadowed, isFalse);

      final dark = Uint8List.fromList([for (final v in small.data) v ~/ 4]);
      expect(
        PageQuality.lighting(
          GrayImage(small.width, small.height, dark),
          q,
        ).tooDark,
        isTrue,
      );

      final shade = Uint8List.fromList([
        for (var i = 0; i < small.data.length; i++)
          (i % small.width) < small.width ~/ 2
              ? small.data[i] ~/ 2
              : small.data[i],
      ]);
      expect(
        PageQuality.lighting(
          GrayImage(small.width, small.height, shade),
          q,
        ).shadowed,
        isTrue,
      );
    });
  });

  group('render', () {
    test('straightens with true perspective and keeps the whole page', () {
      final strong = Quad(
        const Pt(200, 260),
        const Pt(540, 250),
        const Pt(690, 1180),
        const Pt(40, 1200),
      );
      final frame = toFrame(renderScene(fw, fh, strong), fw, fh);
      final q = PageRender.finalCorners(
        frame,
        _detectFull(frame),
        PageRender.detectFactor(frame),
      );
      final page = PageRender.render(frame, q);
      final out = img.decodeJpg(page.jpeg)!;

      // Where the printed table's top rule lands, down the middle column.
      int? ruleRow;
      final x = out.width ~/ 2;
      // Start below the writing (it ends at 660 / 1188).
      for (var y = (out.height * 0.57).round(); y < out.height * 0.7; y++) {
        if (out.getPixel(x, y).luminance < 90) {
          ruleRow = y;
          break;
        }
      }
      expect(ruleRow, isNotNull);
      // A corner blend (not a projective map) puts it several % off here.
      expect(ruleRow! / out.height, closeTo(tableTop / pageH, 0.012));

      // The page edge is inside the picture: the outermost rows and columns
      // are mostly paper, and the margin is thin.
      double band(int x0, int y0, int x1, int y1) {
        var s = 0.0, n = 0;
        for (var y = y0; y < y1; y++) {
          for (var xx = x0; xx < x1; xx++) {
            s += out.getPixel(xx, y).luminance;
            n++;
          }
        }
        return s / n;
      }

      final inset = (out.width * 0.03).round();
      expect(
        band(inset, inset, out.width - inset, inset + 4),
        greaterThan(200),
      );
      expect(
        band(
          inset,
          out.height - inset - 4,
          out.width - inset,
          out.height - inset,
        ),
        greaterThan(200),
      );
    });
  });

  group('engine', () {
    YuvFrame frameOf(Quad q, {int seed = 1, double blur = 0.7}) =>
        toFrame(renderScene(fw, fh, q, seed: seed, blurSigma: blur), fw, fh);

    test('a steady sharp page is saved once, from several candidates', () {
      final engine = ScanEngine();
      final frame = frameOf(tilted);
      final pages = <CapturedPage>[];
      final phases = <ScanPhase>[];
      for (var i = 0; i < 14; i++) {
        final u = engine.process(frame, nowMs: i * 80);
        phases.add(u.phase);
        if (u.page != null) pages.add(u.page!);
      }
      expect(pages, hasLength(1));
      expect(phases, contains(ScanPhase.capturing));
      final aspect = pages.single.width / pages.single.height;
      expect(aspect, closeTo(pageW / pageH, 0.04));
    });

    test('a different sheet in the same place is saved again', () {
      final engine = ScanEngine();
      final a = frameOf(tilted, seed: 1), b = frameOf(tilted, seed: 99);
      var saved = 0;
      for (var i = 0; i < 12; i++) {
        if (engine.process(a, nowMs: i * 80).page != null) saved++;
      }
      for (var i = 12; i < 26; i++) {
        if (engine.process(b, nowMs: i * 80).page != null) saved++;
      }
      expect(saved, 2);
    });

    test('the same sheet is saved again only after it leaves the view', () {
      final engine = ScanEngine();
      final page = frameOf(tilted);
      final empty = toFrame(
        renderScene(
          fw,
          fh,
          Quad(
            const Pt(-5000, -5000),
            const Pt(-4990, -5000),
            const Pt(-4990, -4990),
            const Pt(-5000, -4990),
          ),
        ),
        fw,
        fh,
      );
      var saved = 0, t = 0;
      for (var i = 0; i < 24; i++) {
        if (engine.process(page, nowMs: t += 80).page != null) saved++;
      }
      expect(saved, 1, reason: 'held in view: one save');
      for (var i = 0; i < 4; i++) {
        engine.process(empty, nowMs: t += 80);
      }
      for (var i = 0; i < 14; i++) {
        if (engine.process(page, nowMs: t += 80).page != null) saved++;
      }
      expect(saved, 2);
    });

    test('a blurry page is never saved automatically', () {
      final engine = ScanEngine();
      final frame = frameOf(tilted, blur: 4);
      ScanUpdate? last;
      for (var i = 0; i < 16; i++) {
        last = engine.process(frame, nowMs: i * 80);
        expect(last.page, isNull);
      }
      expect(last!.hint, ScanHint.focusing);
    });

    test('a moving page is never saved', () {
      final engine = ScanEngine();
      for (var i = 0; i < 12; i++) {
        final dx = (i.isEven ? 1 : -1) * 14.0;
        final q = Quad(
          tilted.tl + Pt(dx, 0),
          tilted.tr + Pt(dx, 4),
          tilted.br + Pt(dx, 0),
          tilted.bl + Pt(dx, -4),
        );
        expect(engine.process(frameOf(q), nowMs: i * 80).page, isNull);
      }
    });

    test('the shutter saves even without a steady page', () {
      final engine = ScanEngine(autoCapture: false);
      final frame = frameOf(tilted);
      engine.process(frame, nowMs: 0);
      engine.captureNow();
      CapturedPage? page;
      for (var i = 1; i < 6 && page == null; i++) {
        page = engine.process(frame, nowMs: i * 80).page;
      }
      expect(page, isNotNull);
    });
  });
}
