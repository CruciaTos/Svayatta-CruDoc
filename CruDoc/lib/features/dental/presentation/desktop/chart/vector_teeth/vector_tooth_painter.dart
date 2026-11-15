import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'vector_tooth.dart';

/// Paints [VectorTooth] views in the CruDoc look: ivory crowns with a soft
/// highlight band and a rim shade, warm roots, enamel fading into the root
/// along the tooth's own CEJ curve, carved grooves and a thin soft outline.
///
/// Teeth stay light in the dark theme (the colour tokens do that).
abstract final class VectorToothPainter {
  /// The tooth's buccal bounds in px at [scale] px per mm.
  static Size buccalSize(VectorTooth t, double scale) =>
      Size(t.buccal.bounds.width * scale, t.buccal.bounds.height * scale);

  /// Paints the side view. [anchor] is where the model origin lands: the
  /// middle of the biting edge. Roots run down the screen, or up with
  /// [rootsUp] (upper teeth).
  static void paintBuccal(
    Canvas canvas,
    VectorTooth t, {
    required Offset anchor,
    required double scale,
    required CruColors colors,
    bool rootsUp = false,
    bool showPulp = false,
    double opacity = 1,
  }) {
    final c = colors;
    final b = t.buccal;
    final k = scale;
    final m = _matrix(anchor, k, rootsUp);
    Path tp(Path p) => p.transform(m);
    Offset tpt(Offset o) => Offset(anchor.dx + o.dx * k, anchor.dy + (rootsUp ? -o.dy : o.dy) * k);

    final outline = tp(b.outline);
    final crown = tp(b.crown);
    final crownRect = crown.getBounds();
    final outlineRect = outline.getBounds();
    final lineW = math.max(0.8, k * 0.1);

    if (opacity < 1) {
      canvas.saveLayer(
        outlineRect.inflate(k * 3),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: opacity),
      );
    }

    // ---- hidden back root (palatal), darker.
    if (b.backRoot != null) {
      final br = tp(b.backRoot!);
      final back = Color.lerp(c.toothRoot, c.rootShade, 0.24)!;
      canvas.drawPath(br, Paint()..color = back);
      canvas.save();
      canvas.clipPath(br);
      canvas.drawPath(
        br,
        _blur(c.rootShade.withValues(alpha: 0.3), k * 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = k * 1.2,
      );
      canvas.restore();
      canvas.drawPath(
        br,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineW
          ..color = c.rootShade.withValues(alpha: 0.4),
      );
    }

    // ---- roots.
    final neckY = tpt(Offset(0, b.cejPoints[b.cejPoints.length ~/ 2].dy)).dy;
    final apexY = rootsUp ? outlineRect.top : outlineRect.bottom;
    canvas.save();
    canvas.clipPath(outline);
    canvas.drawRect(outlineRect, Paint()..color = c.toothRoot);
    // Warm at the neck, a touch deeper toward the tip.
    canvas.drawRect(
      outlineRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, neckY),
          Offset(0, apexY),
          [
            c.enamelWarm.withValues(alpha: 0.85),
            c.rootLight.withValues(alpha: 0.0),
            c.rootShade.withValues(alpha: 0.28),
          ],
          const [0, 0.35, 1],
        ),
    );
    // Lit from the left, rounding away at both edges.
    canvas.drawRect(
      outlineRect,
      Paint()
        ..shader = ui.Gradient.linear(
          outlineRect.centerLeft,
          outlineRect.centerRight,
          [
            c.rootShade.withValues(alpha: 0.5),
            c.rootLight.withValues(alpha: 0.0),
            c.rootLight.withValues(alpha: 0.55),
            c.rootLight.withValues(alpha: 0.0),
            c.rootShade.withValues(alpha: 0.55),
          ],
          const [0, 0.22, 0.38, 0.58, 1],
        ),
    );
    canvas.drawPath(
      outline,
      _blur(c.rootShade.withValues(alpha: 0.7), k * 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = k * 0.9,
    );
    // Each root's own lit core (so split roots keep their volume).
    final fy = tpt(Offset(0, b.furcationY)).dy;
    for (final rp in b.rootPaths) {
      if (b.rootPaths.length < 2) break;
      final p = tp(rp);
      final r = p.getBounds();
      canvas.save();
      canvas.clipPath(outline);
      // Below the furcation only: the trunk above it stays one solid piece.
      canvas.clipRect(rootsUp
          ? Rect.fromLTRB(-1e5, -1e5, 1e5, fy)
          : Rect.fromLTRB(-1e5, fy, 1e5, 1e5));
      canvas.drawPath(
        p,
        _blur(c.rootShade.withValues(alpha: 0.45), k * 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = k * 0.7,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: r.center.translate(-r.width * 0.1, 0),
          width: r.width * 0.3,
          height: r.height * 0.75,
        ),
        _blur(c.rootLight.withValues(alpha: 0.55), k * 0.5),
      );
      canvas.restore();
    }
    for (final g in b.grooves) {
      if (g.kind != GrooveKind.rootLine) continue;
      canvas.drawPath(
        tp(g.path),
        _blur(c.rootShade.withValues(alpha: 0.38), k * 0.2)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = k * 0.4,
      );
    }
    canvas.restore();

    // ---- crown (a layer so it can fade out into the root at the CEJ).
    canvas.saveLayer(outlineRect.inflate(k * 2), Paint());
    canvas.save();
    canvas.clipPath(crown);
    canvas.drawRect(
      crownRect,
      Paint()
        ..shader = ui.Gradient.linear(
          crownRect.centerLeft,
          crownRect.centerRight,
          [c.enamelShade, c.enamelMid, c.enamel, c.enamel, c.enamelMid, c.enamelShade],
          const [0, 0.16, 0.36, 0.52, 0.82, 1],
        ),
    );
    final edgeY = rootsUp ? crownRect.bottom : crownRect.top;
    final cejY = rootsUp ? crownRect.top : crownRect.bottom;
    final front = t.dims.kind.index <= 1;
    canvas.drawRect(
      crownRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, edgeY),
          Offset(0, cejY),
          [
            c.enamelClear.withValues(alpha: front ? 0.32 : 0.12),
            c.enamelClear.withValues(alpha: 0.0),
            c.enamelWarm.withValues(alpha: 0.0),
            c.enamelWarm.withValues(alpha: 0.55),
          ],
          const [0, 0.22, 0.62, 1],
        ),
    );
    // Rim shade inside the outline.
    canvas.drawPath(
      crown,
      _blur(c.toothShadow.withValues(alpha: 0.2), k * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = k * 1.5,
    );
    // Soft highlight band, upper left.
    final hl = Rect.fromCenter(
      center: Offset(
        crownRect.left + crownRect.width * 0.34,
        crownRect.center.dy + (rootsUp ? 1 : -1) * crownRect.height * 0.04,
      ),
      width: crownRect.width * 0.2,
      height: crownRect.height * 0.62,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(hl, Radius.circular(hl.width / 2)),
      _blur(c.toothGloss.withValues(alpha: 0.85), math.max(1.0, hl.width * 0.28)),
    );
    // Grooves and ridges on the face.
    for (final g in b.grooves) {
      final p = tp(g.path);
      switch (g.kind) {
        case GrooveKind.groove:
          _carved(canvas, p, k * 0.34 * (0.5 + g.weight * 0.6), c, g.weight, k);
        case GrooveKind.ridge:
          canvas.drawPath(
            p,
            _blur(c.toothGloss.withValues(alpha: 0.5 * g.weight + 0.2), k * 0.3)
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = k * 0.55,
          );
        case GrooveKind.rootLine:
        case GrooveKind.pit:
          break;
      }
    }
    canvas.restore();
    // Fade the enamel out into the root across the CEJ curve.
    final erase = tp(b.roots.shift(const Offset(0, -0.22)));
    canvas.drawPath(
      erase,
      _blur(const Color(0xFF000000), k * 0.32)..blendMode = BlendMode.dstOut,
    );
    canvas.restore();

    // ---- thin soft outline (grey on the crown, warm on the root).
    final edgeCol = c.enamelEdge;
    final rootCol = c.rootShade;
    final span = (apexY - edgeY);
    final frac = span == 0 ? 0.5 : ((neckY - edgeY) / span).clamp(0.05, 0.95);
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineW
        ..strokeJoin = StrokeJoin.round
        ..shader = ui.Gradient.linear(
          Offset(0, edgeY),
          Offset(0, apexY),
          [
            edgeCol.withValues(alpha: 0.7),
            edgeCol.withValues(alpha: 0.7),
            rootCol.withValues(alpha: 0.85),
            rootCol.withValues(alpha: 0.85),
          ],
          [0, (frac - 0.05).clamp(0.0, 1.0), (frac + 0.12).clamp(0.0, 1.0), 1],
        ),
    );

    if (showPulp) {
      final pp = tp(b.pulp);
      canvas.drawPath(pp, Paint()..color = c.pulp.withValues(alpha: 0.5));
      for (final cn in b.canals) {
        canvas.drawPath(
          tp(vtSmooth(cn)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = k * 0.25
            ..strokeCap = StrokeCap.round
            ..color = c.pulp.withValues(alpha: 0.8),
        );
      }
    }
    if (opacity < 1) canvas.restore();
  }

  /// Paints the top view centred on [center]; cheek side up unless [flipY].
  static void paintOcclusal(
    Canvas canvas,
    VectorTooth t, {
    required Offset center,
    required double scale,
    required CruColors colors,
    bool flipY = false,
    double opacity = 1,
  }) {
    final c = colors;
    final o = t.occlusal;
    final k = scale;
    final m = _matrix(center, k, flipY);
    Path tp(Path p) => p.transform(m);
    final outline = tp(o.outline);
    final r = outline.getBounds();
    final lineW = math.max(0.8, k * 0.1);

    if (opacity < 1) {
      canvas.saveLayer(
        r.inflate(k * 2),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: opacity),
      );
    }
    canvas.save();
    canvas.clipPath(outline);
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(r.left + r.width * 0.42, r.top + r.height * 0.4),
          r.longestSide * 0.62,
          [c.enamel, c.enamelMid, c.enamelShade],
          const [0, 0.62, 1],
        ),
    );
    // Rim shade, deeper on the lower right.
    canvas.drawPath(
      outline,
      _blur(c.toothShadow.withValues(alpha: 0.22), k * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = k * 1.8,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(r.left + r.width * 0.34, r.top + r.height * 0.3),
        width: r.width * 0.34,
        height: r.height * 0.22,
      ),
      _blur(c.toothGloss.withValues(alpha: 0.7), math.max(1.0, r.shortestSide * 0.07)),
    );
    for (final (cc, cr) in o.cusps) {
      final q = Offset(center.dx + cc.dx * k, center.dy + (flipY ? -cc.dy : cc.dy) * k);
      canvas.drawCircle(
        q.translate(cr * k * 0.22, cr * k * 0.26),
        cr * k * 0.9,
        _blur(c.toothShadow.withValues(alpha: 0.1), cr * k * 0.45),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: q.translate(-cr * k * 0.2, -cr * k * 0.22),
          width: cr * k * 1.15,
          height: cr * k * 0.9,
        ),
        _blur(c.toothGloss.withValues(alpha: 0.95), cr * k * 0.3),
      );
    }
    for (final g in o.grooves) {
      final p = tp(g.path);
      switch (g.kind) {
        case GrooveKind.ridge:
          canvas.drawPath(
            p,
            _blur(c.toothGloss.withValues(alpha: 0.45 * g.weight + 0.15), k * 0.35)
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = k * 0.7,
          );
        case GrooveKind.groove:
          _carved(canvas, p, k * 0.42 * (0.5 + g.weight * 0.6), c, g.weight, k);
        case GrooveKind.pit:
          final pc = p.getBounds().center;
          canvas.drawCircle(
            pc.translate(k * 0.05, k * 0.07),
            k * 0.42,
            _blur(c.toothGloss.withValues(alpha: 0.5), k * 0.12),
          );
          canvas.drawCircle(
            pc,
            k * 0.32 * (0.6 + g.weight * 0.4),
            _blur(c.fissure.withValues(alpha: 0.7), k * 0.14),
          );
        case GrooveKind.rootLine:
          break;
      }
    }
    canvas.restore();
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineW
        ..strokeJoin = StrokeJoin.round
        ..color = c.enamelEdge.withValues(alpha: 0.75),
    );
    if (opacity < 1) canvas.restore();
  }

  // ------------------------------------------------------------- helpers

  static Float64List _matrix(Offset a, double k, bool flip) => Float64List.fromList([
        k, 0, 0, 0, //
        0, flip ? -k : k, 0, 0,
        0, 0, 1, 0,
        a.dx, a.dy, 0, 1,
      ]);

  static Paint _blur(Color color, double sigma) => Paint()
    ..color = color
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.01, sigma));

  /// A groove that looks cut in: a dark taper with a light lip just below.
  static void _carved(
    Canvas canvas,
    Path screenPath,
    double maxW,
    CruColors c,
    double weight,
    double k,
  ) {
    final poly = _taper(screenPath, maxW);
    if (poly == null) return;
    // Light lip, offset toward the lower right.
    canvas.drawPath(
      poly.shift(Offset(k * 0.07, k * 0.09)),
      _blur(c.toothGloss.withValues(alpha: 0.65), k * 0.1),
    );
    canvas.drawPath(
      poly,
      _blur(c.fissure.withValues(alpha: 0.42 + 0.4 * weight), k * 0.1),
    );
  }

  /// A closed polygon around [p] that is thin at both ends and widest in the
  /// middle.
  static Path? _taper(Path p, double maxW) {
    final left = <Offset>[];
    final right = <Offset>[];
    for (final m in p.computeMetrics()) {
      final n = math.max(6, (m.length / 1.2).ceil());
      final pts = <Offset>[
        for (var i = 0; i <= n; i++) m.getTangentForOffset(m.length * i / n)!.position,
      ];
      for (var i = 0; i <= n; i++) {
        final a = pts[math.max(0, i - 1)];
        final b = pts[math.min(n, i + 1)];
        final d = b - a;
        final l = d.distance;
        if (l == 0) continue;
        final nrm = Offset(-d.dy, d.dx) / l;
        final s = i / n;
        final w = maxW * (0.12 + 0.88 * math.pow(math.sin(math.pi * s), 0.7)) / 2;
        left.add(pts[i] + nrm * w);
        right.add(pts[i] - nrm * w);
      }
    }
    if (left.length < 3) return null;
    final pts = [...left, ...right.reversed];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    return path..close();
  }
}
