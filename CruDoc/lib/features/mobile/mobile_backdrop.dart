import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// How the Day (light mode) background looks behind the tabs. Evening
/// has its own and does not change with this.
enum MobileDayLook {
  /// A cobalt masthead across the top third, fine rings printed from the
  /// top right; the white cards ride over its edge onto porcelain.
  masthead,

  /// Pale periwinkle, lilac and peach light over porcelain, soft enough
  /// for dark text.
  aurora,

  /// One cobalt field from top to bottom, the white cards on it.
  cobalt,

  /// White, with fine light blue rings from the top right across the
  /// whole screen.
  rings,

  /// Soft light blue clouds on white under a fine dot grid whose dots
  /// slowly gather, drift and fade.
  dots;

  /// Text and glyphs straight on this background (headers, the week
  /// strip) are white.
  bool get darkHeader =>
      this == MobileDayLook.masthead || this == MobileDayLook.cobalt;
}

/// The Day background in use.
const MobileDayLook kMobileDayLook = MobileDayLook.dots;

/// Phone background colours for pushed pages.
abstract final class MobileCanvas {
  /// Pushed pages keep their own dark headers, so they sit on the same
  /// off-white the tabs fade into.
  static Color wash(bool eve) =>
      eve ? const Color(0xFF111214) : const Color(0xFFE6ECFB);
  static Color bottom(bool eve) =>
      eve ? const Color(0xFF111214) : const Color(0xFFEFF2F8);
}

/// The background behind the tabs: in light mode the Day look above; in
/// dark mode the deep blue across the top fading into the canvas.
class MobileBackdrop extends StatelessWidget {
  const MobileBackdrop({super.key, this.pages});

  /// The tabs' pages, for backgrounds that move with a swipe.
  final PageController? pages;

  static const _eve = [
    Color(0xFF111B45),
    Color(0xFF142155),
    Color(0xFF172764),
    Color(0xFF192B6E),
    Color(0xFF172350),
    Color(0xFF141A33),
  ];
  static const _stops = [0.0, 0.10, 0.18, 0.24, 0.32, 0.40, 0.50];

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final eve = c.isEvening;
    if (!eve) {
      return RepaintBoundary(
        child: switch (kMobileDayLook) {
          MobileDayLook.masthead => const _Masthead(),
          MobileDayLook.aurora => const CustomPaint(painter: _AuroraPainter()),
          MobileDayLook.cobalt => const CustomPaint(
            painter: _CobaltPainter(full: true),
          ),
          MobileDayLook.rings => const CustomPaint(painter: _RingsPainter()),
          MobileDayLook.dots => _DotsBackdrop(pages: pages),
        },
      );
    }
    const light = Color(0xFF2A47B0);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [..._eve, c.canvas],
              stops: _stops,
            ),
          ),
        ),
        // The soft light at the top right.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.6, -1),
              radius: 0.6,
              colors: [
                for (final a in const [1.0, 0.95, 0.85, 0.44, 0.17, 0.07, 0.0])
                  light.withValues(alpha: a * 0.6),
              ],
              stops: const [0, 0.19, 0.40, 0.66, 0.77, 0.885, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// Porcelain under a cobalt masthead a third of the screen tall, its
/// lower edge blurred into the porcelain.
class _Masthead extends StatelessWidget {
  const _Masthead();

  /// Where the masthead's edge sits: about a third down, so every tab's
  /// header (and Home's quick actions title) is on solid cobalt.
  static double edge(BuildContext context) =>
      (MediaQuery.sizeOf(context).height * 0.36).clamp(260.0, 360.0);

  @override
  Widget build(BuildContext context) {
    final edge = _Masthead.edge(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEFF2F8), Color(0xFFE6EAF2)],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          // Room below the edge for the blur to fade out in.
          height: edge + _CobaltPainter.soft * 3,
          child: CustomPaint(painter: _CobaltPainter(full: false, edge: edge)),
        ),
      ],
    );
  }
}

/// Cobalt from deep at the top left to bright at the bottom right, the
/// Evening light at the top right, and fine rings from that corner.
class _CobaltPainter extends CustomPainter {
  const _CobaltPainter({required this.full, this.edge});

  /// The whole screen (the cobalt look) rather than the masthead band.
  final bool full;

  /// The masthead's edge, blurred into what is below it (null: no edge).
  final double? edge;

  /// How soft that edge is: the spread (standard deviation) of the blur,
  /// so the cobalt melts away over about four times this.
  static const double soft = 34;

  /// 1 above the edge, 0 below, along a step blurred by a Gaussian:
  /// [x] is the distance below the edge in standard deviations.
  static double _blurredStep(double x) => 0.5 * (1 - _erf(x / math.sqrt2));

  /// The error function (Abramowitz and Stegun 7.1.26, to 1.5e-7).
  static double _erf(double x) {
    final a = x.abs();
    final t = 1 / (1 + 0.3275911 * a);
    final y =
        1 -
        (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                        0.284496736) *
                    t +
                0.254829592) *
            t *
            math.exp(-a * a);
    return x < 0 ? -y : y;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final edge = this.edge;
    // Everything is drawn into a layer, then the layer is faded out below
    // the edge, so the glow and rings melt away with the cobalt.
    if (edge != null) canvas.saveLayer(rect, Paint());
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: full
              ? const [
                  Color(0xFF0F1A57),
                  Color(0xFF172B86),
                  Color(0xFF2443C2),
                  Color(0xFF4766E8),
                ]
              : const [Color(0xFF101C5E), Color(0xFF1A3090), Color(0xFF2B4CD3)],
          stops: full ? const [0, 0.3, 0.68, 1] : null,
        ).createShader(rect),
    );

    // The light at the top right, as in Evening.
    final glow = Offset(w * 0.9, -w * 0.12);
    final glowR = w * (full ? 1.05 : 0.9);
    canvas.drawCircle(
      glow,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF7E98FF).withValues(alpha: 0.5),
            const Color(0xFF7E98FF).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: glow, radius: glowR)),
    );

    // Fine rings from the same corner, fading out: the printed detail.
    canvas.save();
    canvas.clipRect(rect);
    final centre = Offset(w * 1.02, -w * 0.06);
    final reach = math.sqrt(w * w + h * h);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = 26.0; r < reach; r += 14) {
      final t = r / (full ? reach * 0.75 : reach);
      final a = 0.12 * (1 - t) * (1 - t);
      if (t >= 1 || a < 0.004) break;
      canvas.drawCircle(
        centre,
        r,
        ring..color = Colors.white.withValues(alpha: a),
      );
    }
    canvas.restore();

    if (edge != null) {
      // Lighter towards the edge, so the melt runs through periwinkle
      // into the porcelain rather than through grey.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x003D5FEA), Color(0x003D5FEA), Color(0x8C4A6BF0)],
            stops: [0, 0.5, 1],
          ).createShader(rect),
      );
      // The blurred edge: keep the layer where the step is 1, let it go
      // where it falls to 0.
      final stops = <double>[];
      final colors = <Color>[];
      for (var i = 0; i <= 24; i++) {
        final y = edge - 3 * soft + i * soft / 4;
        stops.add((y / h).clamp(0.0, 1.0));
        colors.add(
          const Color(
            0xFF000000,
          ).withValues(alpha: _blurredStep((y - edge) / soft)),
        );
      }
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
            stops: stops,
          ).createShader(rect),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CobaltPainter old) =>
      old.full != full || old.edge != edge;
}

/// A very light blue, with fine light blue rings from just past the top right corner
/// out to the far corner, a little fainter as they go.
class _RingsPainter extends CustomPainter {
  const _RingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEFF4FF),
    );
    final centre = Offset(w * 1.02, -w * 0.06);
    // Far enough to reach the bottom left corner.
    final reach = (Offset(0, h) - centre).distance + 14;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = 26.0; r < reach; r += 14) {
      final t = r / reach;
      canvas.drawCircle(
        centre,
        r,
        ring..color = const Color(0xFF7F9BFF).withValues(alpha: 0.42 - 0.2 * t),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => false;
}

/// Touches on the tabs, for the Day dots to answer: a tap sends out a
/// shockwave, a hold gathers the dots round the finger (the rest fade), a
/// drag leaves a short trail. It only listens: buttons, scrolls and
/// swipes work as before.
class MobileDotsFx {
  MobileDotsFx._();

  /// The one the tabs feed and the dots read.
  static final instance = MobileDotsFx._();

  /// On while the dots are on screen with animations allowed.
  bool enabled = false;

  final _clock = Stopwatch()..start();

  /// Seconds on the effects' own clock.
  double get now => _clock.elapsedMicroseconds / 1e6;

  /// Shockwaves: where and when each started.
  final waves = <(Offset, double)>[];

  /// The trail of a drag: points and when the finger passed them.
  final trail = <(Offset, double)>[];

  /// The finger being held still, and since when; after release, where
  /// it was and when it let go (the halo fades out).
  Offset? holdAt;
  double holdSince = 0;
  Offset? lastHold;
  double holdEnded = -10;

  int? _pointer;
  Offset _start = Offset.zero;
  double _startAt = 0;
  bool _moved = false;
  Timer? _holdTimer;
  double _lastEvent = -10;

  static const _slop = 12.0;
  static const _holdDelay = Duration(milliseconds: 320);

  /// Something is still playing (the dots then run at full frame rate).
  bool get busy => holdAt != null || now - _lastEvent < 1.6;

  void down(PointerDownEvent e) {
    if (!enabled || _pointer != null) return;
    _pointer = e.pointer;
    _start = e.localPosition;
    _startAt = now;
    _lastEvent = now;
    _moved = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDelay, () {
      if (_pointer == null || _moved) return;
      holdAt = _start;
      holdSince = now;
    });
  }

  void move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final p = e.localPosition;
    _lastEvent = now;
    if (holdAt != null) {
      holdAt = p;
      return;
    }
    if (!_moved && (p - _start).distance > _slop) {
      _moved = true;
      _holdTimer?.cancel();
    }
    if (_moved && (trail.isEmpty || (trail.last.$1 - p).distance > 14)) {
      trail.add((p, now));
      if (trail.length > 16) trail.removeAt(0);
    }
  }

  void up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    if (holdAt == null && !_moved && now - _startAt < 0.32) {
      waves.add((e.localPosition, now));
      if (waves.length > 6) waves.removeAt(0);
    }
    _release();
  }

  void cancel(PointerCancelEvent e) {
    if (e.pointer == _pointer) _release();
  }

  void _release() {
    _holdTimer?.cancel();
    if (holdAt != null) {
      lastHold = holdAt;
      holdEnded = now;
      holdAt = null;
    }
    _pointer = null;
    _lastEvent = now;
  }

  /// Drops what has finished playing.
  void prune() {
    final t = now;
    waves.removeWhere((w) => t - w.$2 > _wave);
    trail.removeWhere((p) => t - p.$2 > _trailLife);
  }

  static const _wave = 1.4;
  static const _trailLife = 0.7;
}

/// Light blue clouds on pale blue, and over them a dot grid in which
/// random, branching patches of dots form, travel and break up, and
/// which answers touches (see [MobileDotsFx]).
class _DotsBackdrop extends StatefulWidget {
  const _DotsBackdrop({this.pages});

  /// The tabs' pages: the dots and clouds slide a little with a swipe.
  final PageController? pages;

  @override
  State<_DotsBackdrop> createState() => _DotsBackdropState();
}

class _DotsBackdropState extends State<_DotsBackdrop>
    with SingleTickerProviderStateMixin {
  final _fx = MobileDotsFx.instance;

  /// Seconds since start: about 15 steps a second at rest, 30
  /// while a touch effect plays.
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((elapsed) {
    final t = elapsed.inMilliseconds / 1000;
    // About 15 steps a second at rest, 30 while a touch effect plays.
    if (t - _time.value >= (_fx.busy ? 0.033 : 0.066)) _time.value = t;
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Still, and no touch effects, for people who turn animations off.
    final still = MediaQuery.disableAnimationsOf(context);
    _fx.enabled = !still;
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _fx.enabled = false;
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _DotsPainter(_time, widget.pages)),
  );
}

/// Paints the clouds and the dots, and the touch effects on the dots.
/// Kept light: the grid and each dot's random threshold are worked out
/// once per screen size, two noise lookups per dot, the cloud shading only
/// for dots that show, and the draw buffers are reused frame to frame.
class _DotsPainter extends CustomPainter {
  _DotsPainter(this.time, this.pages) : super(repaint: time);

  final ValueNotifier<double> time;

  /// Read at each tick (not listened to), so a swipe adds no repaints.
  final PageController? pages;

  /// (x, y, radius as a share of the width, colour, strength).
  static const _clouds = [
    (0.85, 0.06, 0.95, Color(0xFF8FBBFF), 0.68),
    (0.05, 0.38, 0.85, Color(0xFFA8CAFF), 0.58),
    (0.70, 0.62, 0.80, Color(0xFF9CC3FF), 0.52),
    (0.15, 0.95, 0.75, Color(0xFFADCDFF), 0.54),
  ];

  static const double _gap = 13;
  static const Color _blue = Color(0xFF4F7BF7);

  /// The size of a patch of dots, in logical pixels.
  static const double _scale = 70;
  static const int _steps = 5;

  // The grid for the last size: positions and thresholds, and one
  // reusable buffer per alpha step (quiet dots, then touched ones).
  static Size? _gridSize;
  static int _count = 0;
  static Float32List _gx = Float32List(0);
  static Float32List _gy = Float32List(0);
  static Float32List _threshold = Float32List(0);
  static final List<Float32List> _buffers = [];
  static final List<int> _fill = List.filled(_steps * 2, 0);

  static void _layout(Size size) {
    if (_gridSize == size) return;
    _gridSize = size;
    final cols = (size.width / _gap).ceil() + 1;
    final rows = (size.height / _gap).ceil() + 1;
    _count = cols * rows;
    _gx = Float32List(_count);
    _gy = Float32List(_count);
    _threshold = Float32List(_count);
    var k = 0;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        _gx[k] = i * _gap + _gap / 2;
        _gy[k] = j * _gap + _gap / 2;
        _threshold[k] = 0.42 + 0.22 * _hash(i, j);
        k++;
      }
    }
    _buffers
      ..clear()
      ..addAll([for (var b = 0; b < _steps * 2; b++) Float32List(_count * 2)]);
  }

  /// A steady random number in [0, 1) for a pair of integers.
  static double _hash(int i, int j) {
    var n = (i * 374761393 + j * 668265263) & 0x7fffffff;
    n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff;
    return (n & 0xffff) / 0x10000;
  }

  /// Smooth random values in [0, 1] (value noise).
  static double _noise(double x, double y) {
    final xi = x.floor();
    final yi = y.floor();
    final xf = x - xi;
    final yf = y - yi;
    final u = xf * xf * (3 - 2 * xf);
    final v = yf * yf * (3 - 2 * yf);
    final a = _hash(xi, yi);
    final b = _hash(xi + 1, yi);
    final c = _hash(xi, yi + 1);
    final d = _hash(xi + 1, yi + 1);
    final top = a + (b - a) * u;
    final bottom = c + (d - c) * u;
    return top + (bottom - top) * v;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final t = time.value;
    final fx = MobileDotsFx.instance;
    final now = fx.now;
    fx.prune();
    _layout(size);
    var page = 0.0;
    final pos = pages != null && pages!.hasClients
        ? pages!.positions.last
        : null;
    if (pos != null && pos.hasContentDimensions && pos.hasPixels) {
      page = pos.pixels / math.max(1.0, pos.viewportDimension);
    }

    // Pale blue, and the clouds on their wide, slow loops (sliding a
    // little with the tabs).
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF1F6FF),
    );
    final cx = Float64List(4);
    final cy = Float64List(4);
    final cr = Float64List(4);
    for (var k = 0; k < _clouds.length; k++) {
      final (dx, dy, r, color, a) = _clouds[k];
      cx[k] = w * (dx + 0.32 * math.sin(t * 0.23 + k * 1.9) - page * 0.06);
      cy[k] = h * (dy + 0.14 * math.cos(t * 0.19 + k * 2.6));
      cr[k] = w * r;
      final centre = Offset(cx[k], cy[k]);
      canvas.drawCircle(
        centre,
        cr[k],
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: a),
              color.withValues(alpha: a * 0.45),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: centre, radius: cr[k])),
      );
    }
    final haze = Offset(
      w * (0.3 + 0.25 * math.sin(t * 0.15)),
      h * (0.25 + 0.15 * math.cos(t * 0.12)),
    );
    canvas.drawCircle(
      haze,
      w * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.7),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: haze, radius: w * 0.55)),
    );

    // The hold's halo: in while held, out after release.
    final Offset? holdPos = fx.holdAt ?? fx.lastHold;
    final hold = fx.holdAt != null
        ? ((now - fx.holdSince) / 0.25).clamp(0.0, 1.0)
        : (1 - (now - fx.holdEnded) / 0.35).clamp(0.0, 1.0);
    final waves = fx.waves;
    final trail = fx.trail;
    final effects = waves.isNotEmpty || trail.isNotEmpty || hold > 0;

    for (var b = 0; b < _fill.length; b++) {
      _fill[b] = 0;
    }
    final driftX = t * 0.32 + page * 0.9;
    final driftY = -t * 0.18;
    final warpT1 = t * 0.21;
    final warpT2 = t * 0.13;
    for (var k = 0; k < _count; k++) {
      final x = _gx[k];
      final y = _gy[k];
      final px = x / _scale;
      final py = y / _scale;
      // One warp lookup bends the field both ways; one lookup reads it.
      final warp = _noise(px * 0.5 + 3.1 + warpT1, py * 0.5 + warpT2) - 0.5;
      final n = _noise(px + warp * 1.8 + driftX, py - warp * 1.3 + driftY);
      final ridge = 1 - (2 * n - 1).abs() * 2.6;
      var base = (ridge - _threshold[k]) / 0.2;
      if (base > 0) {
        if (base > 1) base = 1;
        // How blue the clouds are here, only for dots that show.
        var cloud = 0.0;
        for (var c = 0; c < 4; c++) {
          final ox = x - cx[c];
          final oy = y - cy[c];
          final d2 = ox * ox + oy * oy;
          final r = cr[c];
          if (d2 < r * r) {
            cloud += _clouds[c].$5 * (1 - math.sqrt(d2) / r) * 1.6;
          }
        }
        base *= (0.4 + 0.6 * (cloud > 1 ? 1 : cloud)) * 0.8;
      } else {
        base = 0;
      }

      var touch = 0.0;
      var dx = 0.0;
      var dy = 0.0;
      if (effects) {
        // Shockwaves: a ring racing out, pushing the dots it passes.
        for (final (o, start) in waves) {
          final age = now - start;
          final ox = x - o.dx;
          final oy = y - o.dy;
          final r = 30 + age * 640;
          if ((ox.abs() > r + 90) || (oy.abs() > r + 90)) continue;
          final d = math.sqrt(ox * ox + oy * oy);
          final band = (d - r) / 30;
          if (band.abs() > 3) continue;
          final kk =
              math.exp(-band * band) *
              math.pow(1 - age / MobileDotsFx._wave, 1.3);
          if (kk > touch) touch = kk.toDouble();
          if (d > 0) {
            dx += ox / d * 7 * kk;
            dy += oy / d * 7 * kk;
          }
        }
        // The hold: dots gather round the finger in a pulsing halo, the
        // rest fade away.
        if (hold > 0 && holdPos != null) {
          base *= 1 - 0.92 * hold;
          final ox = x - holdPos.dx;
          final oy = y - holdPos.dy;
          if (ox.abs() < 150 && oy.abs() < 150) {
            final d = math.sqrt(ox * ox + oy * oy);
            if (d < 150) {
              final inner = math.pow(1 - d / 150, 1.4).toDouble();
              final pulse = 52 + 14 * math.sin(now * 5);
              final q = (d - pulse) / 12;
              final ring = math.exp(-q * q);
              final kk = hold * math.max(inner * 0.75, ring);
              if (kk > touch) touch = kk;
            }
          }
        }
        // The trail of a drag, fading behind the finger.
        for (final (p, at) in trail) {
          final ox = x - p.dx;
          final oy = y - p.dy;
          if (ox.abs() > 50 || oy.abs() > 50) continue;
          final kk =
              math.exp(-(ox * ox + oy * oy) / (22 * 22)) *
              (1 - (now - at) / MobileDotsFx._trailLife);
          if (kk > touch) touch = kk;
        }
      }

      int bucket;
      if (touch > base && touch > 0.05) {
        bucket = _steps + (touch * _steps).floor().clamp(0, _steps - 1);
      } else if (base > 0) {
        bucket = (base * _steps).floor().clamp(0, _steps - 1);
      } else {
        continue;
      }
      final buf = _buffers[bucket];
      final at = _fill[bucket];
      buf[at] = x + dx;
      buf[at + 1] = y + dy;
      _fill[bucket] = at + 2;
    }

    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var b = 0; b < _steps * 2; b++) {
      if (_fill[b] == 0) continue;
      final lit = b >= _steps;
      final step = b % _steps;
      // Touched dots are a little bigger and stronger.
      paint
        ..strokeWidth = lit ? 2.8 : 2.1
        ..color = _blue.withValues(
          alpha: 0.14 + (lit ? 0.62 : 0.4) * (step + 1) / _steps,
        );
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.sublistView(_buffers[b], 0, _fill[b]),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.time != time || old.pages != pages;
}

/// Pale coloured light over porcelain: periwinkle and lilac across the
/// top, a little sky and peach lower down.
class _AuroraPainter extends CustomPainter {
  const _AuroraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEDF0FA), Color(0xFFF3F4F8)],
        ).createShader(rect),
    );
    for (final (dx, dy, r, color, a) in const [
      (0.0, 0.0, 0.95, Color(0xFF8EA5FF), 0.62),
      (1.0, 0.04, 0.8, Color(0xFFC6A3FF), 0.5),
      (0.08, 0.48, 0.6, Color(0xFF94D4FF), 0.26),
      (0.98, 0.66, 0.65, Color(0xFFFFBFA0), 0.28),
      (0.45, 1.02, 0.7, Color(0xFFAEBDFF), 0.24),
    ]) {
      final centre = Offset(w * dx, h * dy);
      final radius = w * r;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: a),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => false;
}

/// A pushed phone page: in light mode a pale periwinkle wash at the top
/// fading into porcelain (its text stays dark); in dark mode the canvas.
class MobileBackdropPage extends StatelessWidget {
  const MobileBackdropPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final eve = context.cru.isEvening;
    // Dark status bar icons on the light page in Day; light in Evening.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (eve ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    MobileCanvas.wash(eve),
                    MobileCanvas.bottom(eve),
                    MobileCanvas.bottom(eve),
                  ],
                  stops: const [0, 0.4, 1],
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
