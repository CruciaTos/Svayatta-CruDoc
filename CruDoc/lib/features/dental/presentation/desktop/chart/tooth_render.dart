import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One tooth's outlines at [k] px per mm, in the tooth's own frame: the
/// biting edge on y = 0, the roots going down (+y) and the mesial side
/// (towards the midline) on the left (-x). Callers flip and mirror the
/// canvas to place it.
class ToothShape {
  ToothShape(this.spec, this.k) {
    final s = spec;
    mw = s.md * k / 2;
    ch = s.crown * k;
    rl = s.root * k;
    cw =
        mw *
        switch (s.kind) {
          ToothKind.centralIncisor => 0.7,
          ToothKind.lateralIncisor => 0.68,
          ToothKind.canine => 0.66,
          ToothKind.premolar => 0.7,
          ToothKind.molar => 0.8,
        };
    final occlusal = switch (s.kind) {
      ToothKind.centralIncisor || ToothKind.lateralIncisor => [
        Offset(-mw * 0.95, ch * 0.08),
        Offset(-mw * 0.5, ch * 0.01),
        Offset(0, 0),
        Offset(mw * 0.5, ch * 0.015),
        Offset(mw * 0.93, ch * 0.1),
      ],
      ToothKind.canine => [
        Offset(-mw * 0.9, ch * 0.3),
        Offset(-mw * 0.42, ch * 0.12),
        Offset(0, 0),
        Offset(mw * 0.42, ch * 0.13),
        Offset(mw * 0.9, ch * 0.32),
      ],
      ToothKind.premolar => [
        Offset(-mw * 0.9, ch * 0.22),
        Offset(-mw * 0.48, ch * 0.05),
        Offset(0, 0),
        Offset(mw * 0.48, ch * 0.05),
        Offset(mw * 0.9, ch * 0.22),
      ],
      ToothKind.molar => [
        Offset(-mw * 0.93, ch * 0.18),
        Offset(-mw * 0.5, ch * 0.01),
        Offset(-mw * 0.04, ch * 0.11),
        Offset(mw * 0.42, 0),
        Offset(mw * 0.9, ch * 0.17),
      ],
    };
    crown = smoothClosed([
      Offset(-cw, ch),
      Offset(-mw * 0.97, ch * 0.62),
      Offset(-mw, ch * 0.34),
      ...occlusal,
      Offset(mw, ch * 0.34),
      Offset(mw * 0.97, ch * 0.62),
      Offset(cw, ch),
      Offset(cw * 0.45, ch * 1.07),
      Offset(0, ch * 1.09),
      Offset(-cw * 0.45, ch * 1.07),
    ]);

    // Roots: one tapering root, or two (three for upper molars: the
    // palatal one shows faintly between them).
    final top = ch * 0.92;
    if (s.roots == 1) {
      roots = [
        smoothClosed([
          Offset(-cw * 0.98, top),
          Offset(-cw * 0.86, ch + rl * 0.35),
          Offset(-cw * 0.55, ch + rl * 0.76),
          Offset(-cw * 0.14, ch + rl * 0.985),
          Offset(0, ch + rl),
          Offset(cw * 0.14, ch + rl * 0.985),
          Offset(cw * 0.55, ch + rl * 0.76),
          Offset(cw * 0.86, ch + rl * 0.35),
          Offset(cw * 0.98, top),
          Offset(0, ch * 0.8),
        ]),
      ];
      canals = [
        [
          Offset(0, ch * 0.55),
          Offset(0, ch + rl * 0.5),
          Offset(0, ch + rl * 0.94),
        ],
      ];
    } else {
      final splay = s.kind == ToothKind.molar ? 1.0 : 0.6;
      final l = -cw * 0.52 * splay;
      final r = cw * 0.52 * splay;
      Path rootAt(double ax, double lean) => smoothClosed([
        Offset(ax - cw * 0.5, top),
        Offset(ax - cw * 0.46 + lean * 0.3, ch + rl * 0.45),
        Offset(ax - cw * 0.22 + lean, ch + rl * 0.9),
        Offset(ax + lean, ch + rl),
        Offset(ax + cw * 0.2 + lean, ch + rl * 0.9),
        Offset(ax + cw * 0.34 + lean * 0.3, ch + rl * 0.45),
        Offset(ax + cw * 0.42, top),
      ]);
      roots = [
        if (s.roots == 3) rootAt(0, 0),
        rootAt(l, -cw * 0.12 * splay),
        rootAt(r, cw * 0.12 * splay),
      ];
      canals = [
        [
          Offset(l * 0.6, ch * 0.6),
          Offset(l - cw * 0.05, ch + rl * 0.5),
          Offset(l - cw * 0.12 * splay, ch + rl * 0.93),
        ],
        [
          Offset(r * 0.6, ch * 0.6),
          Offset(r + cw * 0.05, ch + rl * 0.5),
          Offset(r + cw * 0.12 * splay, ch + rl * 0.93),
        ],
      ];
    }

    implant = Path()
      ..moveTo(-cw * 0.78, top)
      ..lineTo(-cw * 0.62, ch + rl * 0.86)
      ..quadraticBezierTo(0, ch + rl * 1.02, cw * 0.62, ch + rl * 0.86)
      ..lineTo(cw * 0.78, top)
      ..close();
    implantThreads = [
      for (var i = 1; i <= 7; i++)
        () {
          final y = top + (ch + rl * 0.84 - top) * i / 8;
          final t = (y - top) / (ch + rl * 0.86 - top);
          final half = cw * (0.78 - 0.16 * t);
          return (Offset(-half, y), Offset(half, y + rl * 0.03));
        }(),
    ];

    grooves = switch (s.kind) {
      ToothKind.centralIncisor || ToothKind.lateralIncisor => [
        [
          Offset(-mw * 0.36, ch * 0.08),
          Offset(-mw * 0.31, ch * 0.42),
          Offset(-mw * 0.22, ch * 0.74),
        ],
        [
          Offset(mw * 0.36, ch * 0.08),
          Offset(mw * 0.31, ch * 0.42),
          Offset(mw * 0.22, ch * 0.74),
        ],
      ],
      ToothKind.molar => [
        [
          Offset(-mw * 0.04, ch * 0.11),
          Offset(-mw * 0.02, ch * 0.34),
          Offset(mw * 0.03, ch * 0.56),
        ],
      ],
      _ => const [],
    };
    ridge = s.kind == ToothKind.canine || s.kind == ToothKind.premolar;

    final crownMid =
        ch *
        (s.kind == ToothKind.molar || s.kind == ToothKind.premolar
            ? 0.3
            : 0.32);
    decay = Rect.fromCenter(
      center: Offset(-mw * 0.18, crownMid),
      width: mw * 0.62,
      height: ch * 0.2,
    );
    filling = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, crownMid),
        width: mw * 0.95,
        height: ch * 0.26,
      ),
      Radius.circular(mw * 0.25),
    );
    crack = [
      Offset(-mw * 0.55, ch * 0.08),
      Offset(-mw * 0.2, ch * 0.24),
      Offset(-mw * 0.35, ch * 0.34),
      Offset(mw * 0.05, ch * 0.5),
    ];
  }

  final ToothSpec spec;

  /// Pixels per millimetre.
  final double k;

  /// Half the crown's width, and half its width at the neck.
  late final double mw;
  late final double cw;

  /// Crown height and root length.
  late final double ch;
  late final double rl;

  late final Path crown;
  late final List<Path> roots;
  late final List<List<Offset>> canals;
  late final Path implant;
  late final List<(Offset, Offset)> implantThreads;
  late final Rect decay;
  late final RRect filling;
  late final List<Offset> crack;

  /// Soft developmental grooves on the crown's face.
  late final List<List<Offset>> grooves;

  /// Canines and premolars: a lit ridge down the middle of the crown.
  late final bool ridge;

  Rect get crownBounds => Rect.fromLTRB(-mw, 0, mw, ch * 1.09);

  /// The whole tooth with [rootShown] of the root.
  Rect bounds([double rootShown = 1]) =>
      Rect.fromLTRB(-mw, 0, mw, ch + rl * rootShown);

  /// A smooth closed outline through [p] (Catmull-Rom).
  static Path smoothClosed(List<Offset> p) {
    final path = Path()..moveTo(p[0].dx, p[0].dy);
    final n = p.length;
    for (var i = 0; i < n; i++) {
      final p0 = p[(i - 1 + n) % n];
      final p1 = p[i];
      final p2 = p[(i + 1) % n];
      final p3 = p[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path..close();
  }
}

/// How much of a tooth shows and how it is lit in one place of the UI.
class ToothLook {
  const ToothLook({
    this.rootShown = 1,
    this.fadeRoots = false,
    this.turn = 0,
    this.shadow = true,
    this.planMode = false,
    this.down = 1,
  });

  /// Share of the root drawn (0 to 1).
  final double rootShown;

  /// Roots melt away towards their cut end instead of stopping.
  final bool fadeRoots;

  /// 0 facing the viewer, 1 turned away along the arch: the distal side
  /// darkens.
  final double turn;
  final bool shadow;

  /// Planned work stands out (plan view of the chart).
  final bool planMode;

  /// +1 when the frame's +y is screen-down, -1 when the tooth is drawn
  /// flipped (upper teeth). The drop shadow always falls screen-down.
  final double down;
}

/// Paints [v] on [p]: a lit, rounded tooth (enamel crown, roots, and what
/// was found or done), in the tooth's own frame.
void paintTooth(
  Canvas canvas,
  ToothShape p,
  ToothVisual v,
  CruColors c, {
  ToothLook look = const ToothLook(),
}) {
  if (v.missing) {
    _paintGhost(canvas, p, v, c, look);
    return;
  }
  final sunk = v.state == ToothState.notErupted;
  if (sunk) {
    // Still under the gum: sits back from the bite and shows faintly.
    canvas.save();
    canvas.translate(0, p.ch * 0.42);
    canvas.saveLayer(null, Paint()..color = const Color(0x8C000000));
  }
  if (look.shadow) {
    canvas.drawPath(
      p.crown.shift(Offset(0, look.down * p.k * 0.8)),
      Paint()
        ..color = Colors.black.withValues(alpha: c.isEvening ? 0.42 : 0.14)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(1.5, p.mw * 0.24),
        ),
    );
  }
  if (look.rootShown > 0) _paintRoots(canvas, p, v, c, look);
  _paintCrown(canvas, p, v, c, look);
  _paintFindings(canvas, p, v, c);
  if (look.planMode && v.isPlanned) {
    canvas.drawPath(
      p.crown,
      Paint()..color = c.accentTint.withValues(alpha: 0.7),
    );
    dashPath(
      canvas,
      p.crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = c.accentText,
    );
  }
  if (sunk) {
    canvas.restore();
    canvas.restore();
  }
}

void _paintRoots(
  Canvas canvas,
  ToothShape p,
  ToothVisual v,
  CruColors c,
  ToothLook look,
) {
  final end = p.ch + p.rl * look.rootShown;
  final layer = Rect.fromLTRB(
    -p.mw * 1.6,
    p.ch * 0.5,
    p.mw * 1.6,
    p.ch + p.rl + 4,
  );
  canvas.saveLayer(layer, Paint());
  if (v.implant) {
    _paintImplant(canvas, p, c);
  } else {
    final base = c.toothRoot;
    final deep = Color.lerp(base, c.enamelShade, 0.6)!;
    for (var i = 0; i < p.roots.length; i++) {
      final r = p.roots[i];
      final b = r.getBounds();
      final back = p.spec.roots == 3 && i == 0;
      canvas.drawPath(
        r,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, p.ch),
            Offset(0, p.ch + p.rl),
            back ? [deep, deep] : [base, deep],
          ),
      );
      canvas.drawPath(
        r,
        Paint()
          ..shader = ui.Gradient.linear(
            b.centerLeft,
            b.centerRight,
            [
              Colors.black.withValues(alpha: 0.12),
              Colors.white.withValues(alpha: c.isEvening ? 0.08 : 0.4),
              Colors.white.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.16),
            ],
            [0, 0.32, 0.6, 1],
          ),
      );
      canvas.drawPath(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = c.enamelEdge.withValues(alpha: 0.5),
      );
    }
    if (v.rootCanal) {
      final canal = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, p.k * 0.32)
        ..strokeCap = StrokeCap.round
        ..color = c.greenText;
      for (final line in p.canals) {
        final path = Path()..moveTo(line[0].dx, line[0].dy);
        path.quadraticBezierTo(line[1].dx, line[1].dy, line[2].dx, line[2].dy);
        canvas.drawPath(path, canal);
      }
    }
  }
  if (look.fadeRoots) {
    canvas.drawRect(
      layer,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(
          Offset(0, p.ch + p.rl * look.rootShown * 0.2),
          Offset(0, end),
          [Colors.black, Colors.black.withValues(alpha: 0)],
        ),
    );
  } else if (look.rootShown < 1) {
    canvas.drawRect(
      Rect.fromLTRB(layer.left, end, layer.right, layer.bottom),
      Paint()..blendMode = BlendMode.clear,
    );
  }
  canvas.restore();
}

void _paintCrown(
  Canvas canvas,
  ToothShape p,
  ToothVisual v,
  CruColors c,
  ToothLook look,
) {
  final eve = c.isEvening;
  final b = p.crownBounds;
  // Enamel: a cool, slightly translucent biting edge, warmer at the neck.
  final edge = Color.lerp(
    c.enamel,
    eve ? const Color(0xFFB8C1CA) : const Color(0xFFDCE4EB),
    0.6,
  )!;
  final neck = Color.lerp(c.enamel, c.toothRoot, 0.65)!;
  canvas.drawPath(
    p.crown,
    Paint()
      ..shader = ui.Gradient.linear(
        b.topCenter,
        b.bottomCenter,
        [edge, c.enamel, c.enamel, neck],
        [0, 0.24, 0.6, 1],
      ),
  );
  // Roundness: lit from the front, the distal side turning away.
  canvas.drawPath(
    p.crown,
    Paint()
      ..shader = ui.Gradient.linear(
        b.centerLeft,
        b.centerRight,
        [
          Colors.black.withValues(alpha: 0.1),
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: eve ? 0.12 : 0.55),
          Colors.white.withValues(alpha: 0),
          Colors.black.withValues(alpha: 0.05 + 0.08 * look.turn),
          Colors.black.withValues(alpha: 0.16 + 0.16 * look.turn),
        ],
        [0, 0.14, 0.34, 0.56, 0.8, 1],
      ),
  );
  if (v.capped) {
    canvas.drawPath(
      p.crown,
      Paint()..color = c.greenTint.withValues(alpha: 0.62),
    );
  } else if (v.treatment == ToothTreatment.scaling) {
    canvas.drawPath(
      p.crown,
      Paint()..color = c.greenTint.withValues(alpha: 0.38),
    );
  }

  canvas.save();
  canvas.clipPath(p.crown);
  // Soft shade inside the rim.
  canvas.drawPath(
    p.crown,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = p.mw * 0.42
      ..color = c.enamelEdge.withValues(alpha: eve ? 0.5 : 0.36)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        math.max(1, p.mw * 0.16),
      ),
  );
  final blur = MaskFilter.blur(BlurStyle.normal, math.max(0.8, p.mw * 0.06));
  for (final g in p.grooves) {
    final path = Path()..moveTo(g[0].dx, g[0].dy);
    path.quadraticBezierTo(g[1].dx, g[1].dy, g[2].dx, g[2].dy);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, p.mw * 0.09)
        ..strokeCap = StrokeCap.round
        ..color = c.enamelEdge.withValues(alpha: 0.28)
        ..maskFilter = blur,
    );
  }
  if (p.ridge) {
    canvas.drawLine(
      Offset(0, p.ch * 0.05),
      Offset(0, p.ch * 0.66),
      Paint()
        ..strokeWidth = p.mw * 0.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: eve ? 0.12 : 0.5)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(1, p.mw * 0.1),
        ),
    );
  }
  // Gloss.
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(-p.mw * 0.3, p.ch * 0.42),
      width: p.mw * 0.42,
      height: p.ch * 0.5,
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: eve ? 0.16 : 0.7)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        math.max(1, p.mw * 0.13),
      ),
  );
  canvas.drawCircle(
    Offset(-p.mw * 0.36, p.ch * 0.3),
    math.max(0.8, p.mw * 0.07),
    Paint()
      ..color = Colors.white.withValues(alpha: eve ? 0.3 : 0.9)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        math.max(0.5, p.mw * 0.035),
      ),
  );
  canvas.restore();

  canvas.drawPath(
    p.crown,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c.enamelEdge.withValues(alpha: 0.62),
  );
  if (v.capped) {
    canvas.drawPath(
      p.crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = c.greenText,
    );
  }
}

void _paintFindings(Canvas canvas, ToothShape p, ToothVisual v, CruColors c) {
  if (v.filled) {
    canvas.drawRRect(
      p.filling,
      Paint()..color = c.greenText.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      p.filling,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = c.greenText,
    );
    final r = p.filling.outerRect;
    canvas.drawLine(
      Offset(r.left + r.width * 0.22, r.top + r.height * 0.3),
      Offset(r.left + r.width * 0.5, r.top + r.height * 0.3),
      Paint()
        ..strokeWidth = math.max(1, r.height * 0.12)
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }
  if (v.decay) {
    canvas.drawOval(
      p.decay.inflate(p.decay.shortestSide * 0.15),
      Paint()
        ..color = c.amberText.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(1, p.decay.shortestSide * 0.25),
        ),
    );
    canvas.drawOval(
      p.decay.deflate(p.decay.shortestSide * 0.2),
      Paint()..color = c.amberText.withValues(alpha: 0.9),
    );
  }
  if (v.fractured) {
    final crack = Path()..addPolygon(p.crack, false);
    canvas.drawPath(
      crack.shift(const Offset(0.8, 0.6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.drawPath(
      crack,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = c.amberText,
    );
  }
  if (v.condition == ToothCondition.impacted && v.treatment == null) {
    canvas.drawPath(
      p.crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = c.amberText,
    );
  }
}

/// A missing tooth: the faint outline of what was there.
void _paintGhost(
  Canvas canvas,
  ToothShape p,
  ToothVisual v,
  CruColors c,
  ToothLook look,
) {
  final ghost = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = c.label3;
  if (v.implant) {
    _paintRoots(canvas, p, v, c, look);
  } else if (look.rootShown > 0 && !look.fadeRoots) {
    for (final r in p.roots) {
      dashPath(canvas, r, ghost);
    }
  }
  canvas.drawPath(p.crown, Paint()..color = c.label3.withValues(alpha: 0.04));
  dashPath(canvas, p.crown, ghost..color = c.label3.withValues(alpha: 0.8));
}

void _paintImplant(Canvas canvas, ToothShape p, CruColors c) {
  final b = p.implant.getBounds();
  canvas.drawPath(
    p.implant,
    Paint()
      ..shader = ui.Gradient.linear(
        b.centerLeft,
        b.centerRight,
        [
          c.implantMetal,
          Color.lerp(c.implantMetal, Colors.white, 0.5)!,
          c.implantMetal,
        ],
        [0, 0.38, 1],
      ),
  );
  final thread = Paint()
    ..strokeWidth = 1
    ..color = Color.lerp(c.implantMetal, Colors.black, 0.35)!;
  for (final (a, b) in p.implantThreads) {
    canvas.drawLine(a, b, thread);
  }
}

/// [path] drawn as short dashes.
void dashPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  double dash = 4,
  double gap = 3,
}) {
  for (final m in path.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      d += dash + gap;
    }
  }
}
