import 'dart:math' as math;

import 'package:doctor_management_app/features/scan/data/docscan/geometry.dart';

/// How the drawn outline answers the scanner's reports. Speeds are fractions
/// of the frame a second, distances fractions of the frame.
class OutlineTune {
  const OutlineTune({
    this.minCutoff = 1.5,
    this.beta = 12,
    this.speedCutoff = 6,
    this.trust = 1,
    this.calmSpeed = 0.03,
    this.leave = 0.0022,
    this.easeMs = 34,
    this.shape = 0.7,
  });

  /// How much of the reports' trembling gets through when slow (lower:
  /// smoother), and how fast that opens up as the page moves.
  final double minCutoff;
  final double beta;

  /// How quickly the estimate of speed follows.
  final double speedCutoff;

  /// How much of the predicted movement to draw.
  final double trust;

  /// Below this speed the page counts as still: nothing is predicted.
  final double calmSpeed;

  /// A resting outline moves again only once the page is this far from it.
  final double leave;
  final double easeMs;

  /// On a rigid sheet, how much of each corner's own speed is believed
  /// beyond the sheet's: its turning and nearing, without its noise.
  final double shape;

  @override
  String toString() =>
      'OutlineTune(minCutoff: $minCutoff, beta: $beta, speedCutoff: '
      '$speedCutoff, trust: $trust, calmSpeed: $calmSpeed, leave: $leave, '
      'easeMs: $easeMs, shape: $shape)';
}

/// Where to draw the outline between and ahead of the scanner's reports, so
/// that it looks laid on the page: calm when the phone is calm, keeping up
/// when it moves.
///
/// Every report trembles by a few pixels. Slow movement is therefore
/// smoothed heavily and fast movement hardly at all (a "one euro" filter);
/// once nothing is really moving the outline comes to rest and stays
/// exactly where it is; and only real movement is carried ahead to the
/// present, as a report describes a moment already past.
///
/// Positions are fractions of the camera frame; times are milliseconds on
/// one clock.
class OutlineMotion {
  OutlineMotion({this.tune = const OutlineTune()});

  final OutlineTune tune;

  /// The outline to draw now.
  Quad? get shown => _shown;
  Quad? _shown;

  /// The reports, smoothed; and the latest one as it came.
  Quad? _smooth;
  Quad? _raw;

  /// Where a resting outline stays; null while moving.
  Quad? _rest;
  int _seenMs = 0;
  int _tickMs = 0;
  List<Pt> _speed = _none;
  static const _none = [Pt(0, 0), Pt(0, 0), Pt(0, 0), Pt(0, 0)];

  /// A change bigger than this is another shape, not a movement.
  static const _leap = 0.2;
  static const _maxLeadMs = 160;

  /// How long the filter's own delay may be made up for.
  static const _maxMakeUpMs = 60.0;

  double _makeUpMs = 0;
  bool _rigid = false;

  /// Until when the outline moves over gently: it has been given another
  /// shape, and glides to it instead of snapping.
  int _gentleUntil = 0;

  static double _share(double cutoff, double dt) =>
      1 / (1 + 1 / (2 * math.pi * cutoff * dt));

  /// A new report: the outline [q] as it was in the frame taken at
  /// [takenMs]. [rigid] when its corners move as one sheet by construction:
  /// they are then smoothed alike, so the shape does not wobble.
  void observe(
    Quad q, {
    required int takenMs,
    required int nowMs,
    bool rigid = false,
  }) {
    _rigid = rigid;
    final raw = _raw, smooth = _smooth;
    final since = takenMs - _seenMs;
    _seenMs = takenMs;
    if (raw == null ||
        smooth == null ||
        _shown == null ||
        q.maxCornerDistance(smooth) > _leap ||
        since <= 0 ||
        since > 500) {
      _gentleUntil = nowMs + 300;
      _smooth = _raw = q;
      _speed = _none;
      _rest = null;
      _makeUpMs = 0;
      if (_shown == null) {
        _shown = q;
        _tickMs = nowMs;
      }
      return;
    }
    _raw = q;
    final dt = since / 1000;
    final a = _share(tune.speedCutoff, dt);
    final c = q.corners, was = raw.corners;
    _speed = [
      for (var i = 0; i < 4; i++)
        _speed[i] + ((c[i] - was[i]) * (1 / dt) - _speed[i]) * a,
    ];
    // The speed of the sheet as a whole: corner noise averages out of it.
    final whole = (_speed[0] + _speed[1] + _speed[2] + _speed[3]) * 0.25;
    final fastest = _speed.map((v) => v.length).reduce(math.max);
    final cutoffs = [
      for (var i = 0; i < 4; i++)
        tune.minCutoff +
            tune.beta *
                (rigid
                    ? math.max(whole.length, 0.6 * fastest)
                    : _speed[i].length),
    ];
    final old = smooth.corners;
    final next = [
      for (var i = 0; i < 4; i++)
        old[i] + (c[i] - old[i]) * _share(cutoffs[i], dt),
    ];
    final filtered = Quad(next[0], next[1], next[2], next[3]);
    _smooth = filtered;
    _makeUpMs = math.min(
      _maxMakeUpMs,
      1000 / (2 * math.pi * cutoffs.reduce(math.min)),
    );

    final rest = _rest;
    if (rest != null) {
      if (filtered.maxCornerDistance(rest) > tune.leave) _rest = null;
    } else if (fastest < tune.calmSpeed &&
        filtered.maxCornerDistance(_shown!) < tune.leave) {
      _rest = _shown;
    }
  }

  /// Puts the outline at [q] at once (set by finger, or taken away).
  void jump(Quad? q) {
    _shown = _smooth = _raw = _rest = q;
    _speed = _none;
    _makeUpMs = 0;
  }

  /// Advances to [nowMs]. False once there is nothing left to move.
  bool tick(int nowMs) {
    final smooth = _smooth, shown = _shown;
    if (smooth == null || shown == null) return false;
    final lead = math.max(0, math.min(nowMs - _seenMs, _maxLeadMs)) + _makeUpMs;
    var target = _rest;
    if (target == null) {
      final c = <Pt>[];
      final whole = (_speed[0] + _speed[1] + _speed[2] + _speed[3]) * 0.25;
      for (var i = 0; i < 4; i++) {
        final v = _rigid ? whole + (_speed[i] - whole) * tune.shape : _speed[i];
        // Nothing is predicted for a crawl; all of it for real movement.
        final real = ((v.length - tune.calmSpeed) / (3 * tune.calmSpeed)).clamp(
          0.0,
          1.0,
        );
        c.add(smooth.corners[i] + v * (lead / 1000 * tune.trust * real));
      }
      target = Quad(c[0], c[1], c[2], c[3]);
    }
    final dt = math.max(1, nowMs - _tickMs);
    _tickMs = nowMs;
    final ease = nowMs < _gentleUntil
        ? math.max(tune.easeMs, 80.0)
        : tune.easeMs;
    final next = shown.lerp(target, 1 - math.exp(-dt / ease));
    final settled =
        next.maxCornerDistance(target) < 0.0003 &&
        (_rest != null || nowMs - _seenMs >= _maxLeadMs);
    _shown = settled ? target : next;
    return !settled;
  }
}
