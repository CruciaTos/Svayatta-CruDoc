import 'dart:math' as math;
import 'dart:typed_data';

import 'detector.dart';
import 'geometry.dart';
import 'page_render.dart';
import 'pixels.dart';
import 'quality.dart';

/// Where the scanner is between "nothing in view" and "page saved".
enum ScanPhase {
  /// No page in view.
  searching,

  /// A page is in view; waiting for it to hold still and look good.
  tracking,

  /// Collecting the candidate frames the page will be chosen from.
  capturing,

  /// A page was just saved; waiting for the next one.
  saved,
}

/// What to tell the person.
enum ScanHint {
  findPage,
  fitPage,
  moveCloser,
  holdSteady,
  focusing,
  tooDark,
  glare,
  shadow,
  capturing,
  saved,
  manual,
}

class ScanUpdate {
  const ScanUpdate({
    required this.phase,
    required this.hint,
    this.quad,
    this.progress = 0,
    this.page,
    this.focusAt,
    this.sharpness,
  });

  final ScanPhase phase;
  final ScanHint hint;

  /// The tracked page outline, corners as fractions of the upright frame.
  final Quad? quad;

  /// 0–1 towards an automatic capture.
  final double progress;

  /// Set once, on the frame that finished a capture.
  final CapturedPage? page;

  /// Page centre (fractions) when the camera should refocus there.
  final Pt? focusAt;

  /// This frame's sharpness, for diagnostics.
  final double? sharpness;
}

/// Tuning, gathered in one place.
class ScanTuning {
  const ScanTuning({
    this.stableFramesNeeded = 3,
    this.candidatesWanted = 4,
    this.candidatesMinimum = 3,
    this.steadyMotion = 0.007,
    this.movingMotion = 0.015,
    this.trackJump = 0.06,
    this.candidateAgreement = 0.012,
    this.sharpnessFloor = 0.3,
    this.sharpnessRelative = 0.85,
    this.newPageDistance = 0.45,
  });

  /// Consecutive steady, good frames before collecting starts.
  final int stableFramesNeeded;

  /// Candidate frames to choose the page from.
  final int candidatesWanted;
  final int candidatesMinimum;

  /// Corner movement between frames, as a share of the frame diagonal:
  /// below [steadyMotion] counts as held still; above [movingMotion]
  /// cancels a capture in progress.
  final double steadyMotion;
  final double movingMotion;

  /// A detection further than this from the tracked outline is a different
  /// shape: it must repeat before the outline jumps to it.
  final double trackJump;

  /// Candidates whose corners stray further than this from the consensus
  /// are dropped.
  final double candidateAgreement;

  /// The lowest re-blur sharpness ever accepted. Above it a frame must also
  /// be within [sharpnessRelative] of the sharpest recent view of the same
  /// page, so the bar adapts to the phone, the light and the paper.
  final double sharpnessFloor;
  final double sharpnessRelative;

  /// Signature distance above which the page in view is a new sheet.
  final double newPageDistance;
}

class _Candidate {
  _Candidate(
    this.frame,
    this.quad,
    this.factor,
    this.sharpness,
    this.support,
    this.lighting,
    this.signature,
    this.quarterTurns,
  );

  final PixelSource frame;
  final Quad? quad;
  final int factor;
  final double? sharpness;
  final double support;
  final Lighting? lighting;
  final Float32List? signature;
  final int quarterTurns;
}

/// Watches frames go by and decides when, and which, to keep.
///
/// A page is saved only after its corners have held still for a few frames
/// with good focus and light; then the next few frames are kept in memory
/// as candidates, checked against each other, and the best one is
/// straightened and checked again. Anything doubtful goes back to
/// scanning. After a save, the same sheet is not saved again until it
/// leaves the view or a different sheet takes its place.
class ScanEngine {
  ScanEngine({this.tuning = const ScanTuning(), this.autoCapture = true});

  final ScanTuning tuning;
  bool autoCapture;

  Quad? _smooth;
  Quad? _lastRaw;
  Quad? _pending;
  int _pendingCount = 0;
  int _misses = 0;
  int _steadyFrames = 0;
  int _blurryFrames = 0;
  int _lastFocusMs = -100000;
  final List<double> _recentSharpness = [];

  final List<_Candidate> _candidates = [];
  int _captureStartMs = 0;
  int _captureRejects = 0;

  bool _manual = false;
  bool _cooldown = false;
  Float32List? _savedSignature;

  bool get isCapturing => _manual || _candidates.isNotEmpty;

  /// Capture now (shutter button): the sharpest of the next few frames,
  /// cropped to the page when one is found.
  void captureNow() {
    _manual = true;
    _candidates.clear();
  }

  void reset() {
    _smooth = _lastRaw = _pending = null;
    _pendingCount = _misses = _steadyFrames = _blurryFrames = 0;
    _recentSharpness.clear();
    _candidates.clear();
    _manual = _cooldown = false;
    _savedSignature = null;
  }

  ScanUpdate process(
    PixelSource frame, {
    required int nowMs,
    int quarterTurns = 0,
  }) {
    final f = PageRender.detectFactor(frame);
    final small = frame.downsample(f);
    final det = DocumentDetector.detect(small);
    final diag = math.sqrt(
      frame.width * frame.width + frame.height * frame.height.toDouble(),
    );
    final raw = det.found ? frame.fromSmall(det.quad!, f) : null;

    // ---- Track the outline -------------------------------------------
    var motion = double.infinity;
    var onTrack = false;
    if (raw != null) {
      _misses = 0;
      if (_lastRaw != null) motion = raw.maxCornerDistance(_lastRaw!) / diag;
      final smooth = _smooth;
      if (smooth == null) {
        // A first sighting must repeat before it is shown.
        if (motion < tuning.trackJump) {
          _smooth = raw;
          onTrack = true;
        }
      } else {
        final jump = raw.maxCornerDistance(smooth) / diag;
        if (jump < tuning.trackJump) {
          // Follow quickly when it moves, average out jitter when it rests.
          final alpha = (0.4 + jump * 15).clamp(0.4, 0.9);
          _smooth = smooth.lerp(raw, alpha);
          onTrack = true;
          _pending = null;
          _pendingCount = 0;
        } else {
          // A different shape: one stray frame is not enough to jump.
          final p = _pending;
          if (p != null && raw.maxCornerDistance(p) / diag < tuning.trackJump) {
            _pendingCount++;
          } else {
            _pending = raw;
            _pendingCount = 1;
          }
          if (_pendingCount >= 2) {
            _smooth = raw;
            _pending = null;
            _pendingCount = 0;
            _recentSharpness.clear();
            onTrack = true;
          }
        }
      }
      _lastRaw = raw;
    } else {
      _misses++;
      _lastRaw = null;
      if (_misses > 4) {
        _smooth = null;
        _recentSharpness.clear();
      }
    }
    final steady = onTrack && motion < tuning.steadyMotion;
    _steadyFrames = steady ? _steadyFrames + 1 : 0;

    // ---- Judge the frame ---------------------------------------------
    Lighting? light;
    double? sharp;
    Float32List? signature;
    if (raw != null && onTrack) {
      light = PageQuality.lighting(small, det.quad!);
      sharp = PageQuality.sharpness(frame, raw);
      signature = PageQuality.signature(small, det.quad!);
      if (sharp != null) {
        _recentSharpness.add(sharp);
        if (_recentSharpness.length > 24) _recentSharpness.removeAt(0);
      }
    }
    final sharpOk = sharp == null || _sharpEnough(sharp);
    _blurryFrames = steady && !sharpOk ? _blurryFrames + 1 : 0;

    // ---- A different sheet after a save? ------------------------------
    if (_cooldown) {
      if (_misses >= 3) {
        _cooldown = false;
      } else if (steady && signature != null && _savedSignature != null) {
        final d = PageQuality.signatureDistance(signature, _savedSignature!);
        if (d > tuning.newPageDistance) _cooldown = false;
      }
    }

    final good =
        raw != null &&
        steady &&
        sharpOk &&
        !(light?.tooDark ?? false) &&
        !(light?.badGlare ?? false);

    // ---- Capture -------------------------------------------------------
    CapturedPage? page;
    var progress = 0.0;
    if (_manual) {
      _candidates.add(
        _Candidate(
          frame,
          raw ?? _smoothIfFits(frame),
          f,
          sharp,
          det.support,
          light,
          signature,
          quarterTurns,
        ),
      );
      progress = _candidates.length / tuning.candidatesMinimum;
      if (_candidates.length >= tuning.candidatesMinimum) {
        page = _finish(diag, manual: true);
      }
    } else if (autoCapture && !_cooldown) {
      if (_candidates.isEmpty) {
        if (good && _steadyFrames >= tuning.stableFramesNeeded) {
          _captureStartMs = nowMs;
          _captureRejects = 0;
          _candidates.add(
            _Candidate(
              frame,
              raw,
              f,
              sharp,
              det.support,
              light,
              signature,
              quarterTurns,
            ),
          );
        } else if (good) {
          progress = 0.35 * _steadyFrames / tuning.stableFramesNeeded;
        }
      } else {
        final elapsed = nowMs - _captureStartMs;
        if (raw == null || !onTrack || motion > tuning.movingMotion) {
          _candidates.clear(); // moved: start over
        } else if (good) {
          _candidates.add(
            _Candidate(
              frame,
              raw,
              f,
              sharp,
              det.support,
              light,
              signature,
              quarterTurns,
            ),
          );
        } else if (++_captureRejects > 5 ||
            (elapsed > 1500 && _candidates.length < 2)) {
          _candidates.clear();
        }
        final n = _candidates.length;
        if (n >= tuning.candidatesWanted ||
            (n >= tuning.candidatesMinimum && elapsed >= 700)) {
          page = _finish(diag, manual: false);
        }
      }
      if (_candidates.isNotEmpty) {
        progress = 0.35 + 0.65 * _candidates.length / tuning.candidatesWanted;
      }
    }
    if (page != null) {
      _cooldown = true;
      _steadyFrames = 0;
      progress = 1;
    }

    // ---- Refocus when it will not sharpen on its own -----------------
    Pt? focusAt;
    if (_blurryFrames >= 6 && nowMs - _lastFocusMs > 2000 && raw != null) {
      _lastFocusMs = nowMs;
      _blurryFrames = 0;
      final c = raw.centroid;
      focusAt = Pt(c.x / frame.width, c.y / frame.height);
    }

    final shown = _smooth?.scale(1 / frame.width, 1 / frame.height);
    return ScanUpdate(
      phase: page != null || _cooldown
          ? ScanPhase.saved
          : isCapturing
          ? ScanPhase.capturing
          : _smooth != null
          ? ScanPhase.tracking
          : ScanPhase.searching,
      hint: _hint(det, onTrack, motion, light, sharpOk, page != null),
      quad: shown,
      progress: progress.clamp(0.0, 1.0),
      page: page,
      focusAt: focusAt,
      sharpness: sharp,
    );
  }

  bool _sharpEnough(double s) {
    if (s < tuning.sharpnessFloor) return false;
    var best = 0.0;
    for (final v in _recentSharpness) {
      best = math.max(best, v);
    }
    return s >= tuning.sharpnessRelative * best;
  }

  Quad? _smoothIfFits(PixelSource frame) {
    final s = _smooth;
    if (s == null) return null;
    return s.insideRect(frame.width.toDouble(), frame.height.toDouble())
        ? s
        : null;
  }

  /// Picks the best candidate and turns it into a page; null when none of
  /// them is good enough (scanning simply continues).
  CapturedPage? _finish(double diag, {required bool manual}) {
    final all = List.of(_candidates);
    _candidates.clear();
    _manual = false;
    if (all.isEmpty) return null;

    var pool = all;
    if (!manual) {
      // The corners must agree across frames: one odd detection is dropped,
      // a disagreeing set is thrown away.
      final consensus = Quad.median([for (final c in all) c.quad!]);
      pool = [
        for (final c in all)
          if (c.quad!.maxCornerDistance(consensus) <=
              tuning.candidateAgreement * diag)
            c,
      ];
      if (pool.length < math.max(2, (all.length * 0.6).ceil())) return null;
    }

    var maxSharp = 0.0;
    for (final c in pool) {
      maxSharp = math.max(maxSharp, c.sharpness ?? 0);
    }
    _Candidate best = pool.first;
    var bestScore = -1.0;
    for (final c in pool) {
      final rel = maxSharp <= 0 || c.sharpness == null
          ? 1.0
          : c.sharpness! / maxSharp;
      final score =
          0.6 * rel + 0.25 * c.support + 0.15 * (c.lighting?.score ?? 0.5);
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }

    final quad = best.quad == null
        ? null
        : PageRender.finalCorners(best.frame, best.quad!, best.factor);
    final page = PageRender.render(
      best.frame,
      quad,
      quarterTurns: best.quarterTurns,
    );
    // Last check, on the straightened page itself.
    if (!manual &&
        page.sharpness != null &&
        page.sharpness! < tuning.sharpnessFloor * 0.9) {
      return null;
    }
    _savedSignature = best.signature;
    return page;
  }

  ScanHint _hint(
    Detection det,
    bool onTrack,
    double motion,
    Lighting? light,
    bool sharpOk,
    bool justSaved,
  ) {
    if (justSaved || (_cooldown && !_manual)) return ScanHint.saved;
    if (_manual) return ScanHint.capturing;
    switch (det.status) {
      case DetectionStatus.none:
        return ScanHint.findPage;
      case DetectionStatus.partial:
        return ScanHint.fitPage;
      case DetectionStatus.tooSmall:
        return ScanHint.moveCloser;
      case DetectionStatus.found:
        break;
    }
    if (!onTrack || motion >= tuning.steadyMotion) return ScanHint.holdSteady;
    if (light != null && light.tooDark) return ScanHint.tooDark;
    if (light != null && light.someGlare) return ScanHint.glare;
    if (!sharpOk) return ScanHint.focusing;
    if (!autoCapture) return ScanHint.manual;
    if (_candidates.isNotEmpty) return ScanHint.capturing;
    if (light != null && light.shadowed) return ScanHint.shadow;
    return ScanHint.holdSteady;
  }
}
