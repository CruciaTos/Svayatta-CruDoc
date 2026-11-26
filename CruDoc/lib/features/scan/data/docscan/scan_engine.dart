import 'dart:math' as math;
import 'dart:typed_data';

import 'corner_set.dart';
import 'corner_tracker.dart';
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
  setCorners,
}

/// What is known of one hand-set corner, as bits.
abstract final class CornerFlag {
  /// Found by the scanner or set by finger.
  static const placed = 1;

  /// Sitting on a corner sensed in the picture.
  static const sensed = 2;
}

/// Where a corner ended up after the finger put it somewhere, as fractions
/// of the upright frame.
class CornerReply {
  const CornerReply(this.at, this.flags, {this.page});

  final Pt at;
  final List<int> flags;

  /// All four corners, when a press found the page under it.
  final Quad? page;

  bool sensed(int i) => flags[i] & CornerFlag.sensed != 0;
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
    this.corners,
  });

  /// [CornerFlag]s for the four corners while they are set by hand; null
  /// while the scanner finds them itself.
  final List<int>? corners;

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
    this.steadyMsNeeded = 700,
    this.captureMs = 900,
    this.candidatesWanted = 6,
    this.candidatesMinimum = 4,
    this.steadyMotion = 0.0055,
    this.movingMotion = 0.015,
    this.trackJump = 0.06,
    this.candidateAgreement = 0.012,
    this.sharpnessFloor = 0.3,
    this.sharpnessRelative = 0.9,
    this.newPageDistance = 0.45,
    this.merged = 3,
  });

  /// How long the page must have been held still and good, and how long the
  /// candidates are gathered over, before an automatic capture. Unhurried on
  /// purpose: a moment longer is worth a sharp page.
  final int steadyMsNeeded;
  final int captureMs;

  /// Frames besides the sharpest averaged into the page to remove grain.
  final int merged;

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
    this.exact,
  );

  final PixelSource frame;
  final Quad? quad;
  final int factor;
  final double? sharpness;
  final double support;
  final Lighting? lighting;
  final Float32List? signature;
  final int quarterTurns;

  /// The corners were set by hand: cut exactly along them.
  final bool exact;
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
  int _steadySinceMs = 0;
  bool _shaking = false;
  int _blurryFrames = 0;
  int _lastFocusMs = -100000;

  /// The last judgement of a frame, reused on the frames in between while
  /// hand-set corners are only being followed.
  (Lighting?, double?, Float32List?)? _judged;
  int _frames = 0;
  final List<double> _recentSharpness = [];

  final List<_Candidate> _candidates = [];
  int _captureStartMs = 0;
  int _captureRejects = 0;

  bool _manual = false;
  bool _cooldown = false;
  Float32List? _savedSignature;

  /// The saved sheet is about to be looked at differently (hand-set corners
  /// let go): take its next sighting as the one to compare with.
  bool _adoptSignature = false;

  /// Corners were moved on a sheet already saved: its next capture is a new
  /// cut of that page, not another page.
  bool _redo = false;

  bool get isCapturing => _manual || _candidates.isNotEmpty;

  PixelSource? _lastFrame;
  bool _held = false;

  /// Non-null once a corner has been set by hand.
  CornerTracker? _tracker;
  int _touchedMs = -100000;

  /// After the last touch, before capturing along hand-set corners.
  static const _settleMs = 1200;

  /// The phone itself says it is moving (its gyroscope): frames taken now
  /// would be smeared, so none are gathered for an automatic capture.
  set shaking(bool on) {
    _shaking = on;
    if (on && !_manual) {
      _candidates.clear();
      _steadyFrames = 0;
    }
  }

  /// A finger is on the screen: nothing is captured on its own while this
  /// is on.
  set held(bool on) {
    _held = on;
    if (on) _candidates.clear();
  }

  /// Corner [index] goes to [at] (fractions of the upright frame). [start]
  /// is the outline on screen, used when no corner has been set yet;
  /// [sure] says it was found in the picture rather than made up. With a
  /// [reach] (a fraction of the frame's width) the corner settles onto one
  /// sensed that close; while [holding], that pull carries on from frame to
  /// frame around [at]. Null before the first frame.
  CornerReply? setCorner({
    required Quad start,
    required bool sure,
    required int index,
    required Pt at,
    required double reach,
    required bool holding,
    required int nowMs,
  }) {
    final frame = _lastFrame;
    if (frame == null) return null;
    final w = frame.width.toDouble(), h = frame.height.toDouble();
    final tracker = _tracker ??= CornerTracker(
      start.scale(w, h),
      sure: sure,
      frame: frame,
    );
    final to = Pt((at.x * w).clamp(0.0, w), (at.y * h).clamp(0.0, h));
    if (holding) {
      tracker.hold(frame, index, to, reach * w);
    } else {
      tracker.release();
      // A corner only let go of, not moved, stays sensed.
      if (tracker.points[index].distanceTo(to) > 0.5 ||
          !tracker.placed[index]) {
        tracker.set(index, to);
      }
      if (reach > 0) tracker.snap(frame, index, reach * w);
    }
    _touched(nowMs);
    final p = tracker.points[index];
    return CornerReply(Pt(p.x / w, p.y / h), _flags(tracker));
  }

  /// A long press at [at] (fractions of the upright frame): a corner when
  /// the finger is on one, else the whole page under it, else corner
  /// [index] goes there. See [setCorner] for the rest.
  CornerReply? press({
    required Quad start,
    required bool sure,
    required int index,
    required Pt at,
    required double reach,
    required int nowMs,
  }) {
    final frame = _lastFrame;
    if (frame == null) return null;
    final w = frame.width.toDouble(), h = frame.height.toDouble();
    final spot = Pt(at.x * w, at.y * h);
    final pixels = reach * w;
    // Right on a corner means that corner.
    final onCorner =
        DocumentDetector.cornerNear(
          frame,
          spot,
          radius: 0.4 * pixels,
          inward: spot + Quad.inward[index] * (2 * pixels),
        ) !=
        null;
    if (!onCorner) {
      final page = PageRender.pageAt(frame, spot);
      if (page != null &&
          page.corners.every((c) => c.distanceTo(spot) > 1.5 * pixels)) {
        final tracker = _tracker = CornerTracker(
          page,
          sure: true,
          frame: frame,
        );
        for (var i = 0; i < 4; i++) {
          tracker.snap(frame, i, 0.012 * math.max(w, h));
        }
        _touched(nowMs);
        final c = [for (final p in tracker.points) Pt(p.x / w, p.y / h)];
        return CornerReply(
          c[index],
          _flags(tracker),
          page: Quad(c[0], c[1], c[2], c[3]),
        );
      }
    }
    return setCorner(
      start: start,
      sure: sure,
      index: index,
      at: at,
      reach: reach,
      holding: false,
      nowMs: nowMs,
    );
  }

  /// Corners have just been set by hand.
  void _touched(int nowMs) {
    _touchedMs = nowMs;
    _candidates.clear();
    if (_cooldown) {
      _cooldown = false;
      _redo = true;
    }
    _pending = null;
  }

  /// Follows the outline the scanner found, for drawing.
  CornerTracker? _glued;
  Quad? _rival;
  int _disagreed = 0;
  int _unseen = 0;

  /// The outline to draw while the scanner finds the page itself.
  ///
  /// Detection starts from nothing on every frame, so its corners shimmer
  /// and now and then jump to another edge. What is drawn is instead glued
  /// to the page like hand-set corners are: followed from frame to frame,
  /// leaned gently towards what detection sees, and moved to another shape
  /// only once detection has insisted on it. Capture still judges the
  /// detections themselves.
  Quad? _drawn(PixelSource frame, double diag, Quad? seen) {
    var glued = _glued;
    if (glued != null && !glued.follow(frame)) glued = _glued = null;
    if (seen != null) {
      _unseen = 0;
      if (glued == null) {
        glued = _glued = CornerTracker(seen, sure: true, frame: frame);
        _disagreed = 0;
      } else {
        final apart = seen.maxCornerDistance(glued.quad) / diag;
        if (apart > 0.025) {
          // Another shape: it takes over only by being seen again and again.
          final rival = _rival;
          final same =
              rival != null && seen.maxCornerDistance(rival) / diag < 0.03;
          _disagreed = same ? _disagreed + 1 : 1;
          _rival = seen;
          if (_disagreed >= 8) {
            glued = _glued = CornerTracker(seen, sure: true, frame: frame);
            _disagreed = 0;
          }
        } else {
          _disagreed = 0;
          if (apart > 0.004) glued.lean(seen, 0.07);
        }
      }
    } else if (glued != null && ++_unseen > 12) {
      glued = _glued = null;
    }
    return glued?.quad ?? _smooth;
  }

  /// Back to finding the corners itself.
  void releaseCorners() {
    if (_tracker == null) return;
    _tracker = null;
    _judged = null;
    _redo = false;
    if (_cooldown) {
      _savedSignature = null;
      _adoptSignature = true;
    }
    _candidates.clear();
    _smooth = _lastRaw = _pending = null;
    _steadyFrames = 0;
  }

  static List<int> _flags(CornerTracker t) => [
    for (var i = 0; i < 4; i++)
      (t.placed[i] ? CornerFlag.placed : 0) |
          (t.sensed[i] ? CornerFlag.sensed : 0),
  ];

  /// A page was cut by hand along [quad]: treat that sheet as saved, so it
  /// is not captured a second time.
  void pageTaken(PageSource source) {
    final frame = source.frame, quad = source.quad;
    _candidates.clear();
    _manual = false;
    _tracker = null;
    _redo = _adoptSignature = false;
    if (frame == null || quad == null) return;
    final f = PageRender.detectFactor(frame);
    _savedSignature = PageQuality.signature(
      frame.downsample(f),
      quad.scale(1 / f),
    );
    _cooldown = true;
    _steadyFrames = 0;
  }

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
    _tracker = null;
    _manual = _cooldown = _redo = _adoptSignature = false;
    _judged = null;
    _glued = null;
    _savedSignature = null;
  }

  ScanUpdate process(
    PixelSource frame, {
    required int nowMs,
    int quarterTurns = 0,
  }) {
    _lastFrame = frame;
    final f = PageRender.detectFactor(frame);
    // A small copy, made only when something needs it.
    GrayImage? small;
    // Hand-set corners are followed; otherwise they are looked for.
    if (_tracker != null && !_tracker!.follow(frame)) releaseCorners();
    final tracker = _tracker;
    // Crossed while being dragged about, they make no page.
    final byHand = tracker != null && CornerSet(tracker.points).valid
        ? tracker.quad
        : null;
    final det = tracker == null
        ? DocumentDetector.detect(small = frame.downsample(f))
        : Detection(
            DetectionStatus.found,
            quad: byHand?.scale(1 / f),
            support: 1,
          );
    final diag = math.sqrt(
      frame.width * frame.width + frame.height * frame.height.toDouble(),
    );
    final raw = tracker != null
        ? byHand
        : det.found
        ? frame.fromSmall(det.quad!, f)
        : null;

    // ---- Track the outline -------------------------------------------
    var motion = double.infinity;
    var onTrack = false;
    if (tracker != null) {
      _misses = 0;
      if (raw != null && _lastRaw != null) {
        motion = raw.maxCornerDistance(_lastRaw!) / diag;
      }
      _smooth = tracker.quad;
      onTrack = raw != null;
      _lastRaw = raw;
    } else if (raw != null) {
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
          // Follow quickly when it moves, average out the tremble of a
          // held phone when it rests.
          final alpha = (0.25 + jump * 25).clamp(0.25, 0.95);
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
    final steady = onTrack && motion < tuning.steadyMotion && !_shaking;
    if (steady && _steadyFrames == 0) _steadySinceMs = nowMs;
    _steadyFrames = steady ? _steadyFrames + 1 : 0;

    // ---- Judge the frame ---------------------------------------------
    Lighting? light;
    double? sharp;
    Float32List? signature;
    if (raw != null && onTrack) {
      // Following hand-set corners should keep pace with the camera: unless
      // a capture is near, judge only every third frame.
      final capturing =
          _manual ||
          _candidates.isNotEmpty ||
          (autoCapture &&
              !_cooldown &&
              !_held &&
              (tracker?.complete ?? true) &&
              nowMs - _touchedMs >= _settleMs);
      final last = _judged;
      if (tracker != null && !capturing && last != null && ++_frames % 3 != 0) {
        (light, sharp, signature) = last;
      } else {
        small ??= frame.downsample(f);
        light = PageQuality.lighting(small, det.quad!);
        sharp = PageQuality.sharpness(frame, raw);
        signature = PageQuality.signature(small, det.quad!);
        _judged = (light, sharp, signature);
        if (sharp != null) {
          _recentSharpness.add(sharp);
          if (_recentSharpness.length > 24) _recentSharpness.removeAt(0);
        }
      }
    }
    final sharpOk = sharp == null || _sharpEnough(sharp);
    _blurryFrames = steady && !sharpOk ? _blurryFrames + 1 : 0;

    // ---- A different sheet after a save? ------------------------------
    if (_cooldown) {
      if (_misses >= 3) {
        _cooldown = false;
      } else if (steady && signature != null) {
        final saved = _savedSignature;
        if (saved == null) {
          if (_adoptSignature) _savedSignature = signature;
          _adoptSignature = false;
        } else if (PageQuality.signatureDistance(signature, saved) >
            tuning.newPageDistance) {
          _cooldown = false;
          // Corners set for the old sheet say nothing about this one.
          releaseCorners();
        }
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
          raw ?? (tracker == null ? _smoothIfFits(frame) : null),
          f,
          sharp,
          det.support,
          light,
          signature,
          quarterTurns,
          tracker != null,
        ),
      );
      progress = _candidates.length / tuning.candidatesMinimum;
      if (_candidates.length >= tuning.candidatesMinimum) {
        page = _finish(diag, manual: true);
      }
    } else if (autoCapture &&
        !_cooldown &&
        !_held &&
        identical(tracker, _tracker) &&
        (tracker == null ||
            (tracker.complete && nowMs - _touchedMs >= _settleMs))) {
      if (_candidates.isEmpty) {
        final held = nowMs - _steadySinceMs;
        if (good &&
            _steadyFrames >= tuning.stableFramesNeeded &&
            held >= tuning.steadyMsNeeded) {
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
              tracker != null,
            ),
          );
        } else if (good) {
          progress =
              0.35 *
              math.min(
                _steadyFrames / tuning.stableFramesNeeded,
                held / math.max(1, tuning.steadyMsNeeded),
              );
        }
      } else {
        final elapsed = nowMs - _captureStartMs;
        if (raw == null ||
            !onTrack ||
            _shaking ||
            motion > tuning.movingMotion) {
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
              tracker != null,
            ),
          );
        } else if (++_captureRejects > 8 ||
            (elapsed > 2500 && _candidates.length < 2)) {
          _candidates.clear();
        }
        final n = _candidates.length;
        if (elapsed >= tuning.captureMs && n >= tuning.candidatesMinimum ||
            n >= 2 * tuning.candidatesWanted) {
          page = _finish(diag, manual: false);
        }
      }
      if (_candidates.isNotEmpty) {
        progress = 0.35 + 0.65 * _candidates.length / tuning.candidatesWanted;
      }
    }
    if (page != null) {
      // Hand-set corners stay on the sheet until it is gone, so it is not
      // captured again from a different outline.
      _cooldown = true;
      _redo = _adoptSignature = false;
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

    final hands = _tracker;
    final Quad? outline;
    if (_tracker != null) {
      _glued = null;
      outline = _smooth;
    } else {
      outline = _drawn(frame, diag, onTrack ? _smooth : null);
    }
    final shown = outline?.scale(1 / frame.width, 1 / frame.height);
    return ScanUpdate(
      phase: page != null || _cooldown
          ? ScanPhase.saved
          : isCapturing
          ? ScanPhase.capturing
          : _smooth != null
          ? ScanPhase.tracking
          : ScanPhase.searching,
      hint: hands != null && !hands.complete && !_manual
          ? ScanHint.setCorners
          : _hint(det, onTrack, motion, light, sharpOk, page != null),
      quad: shown,
      corners: hands == null ? null : _flags(hands),
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

    final quad = best.quad == null || best.exact
        ? best.quad
        : PageRender.finalCorners(best.frame, best.quad!, best.factor);
    // The next sharpest views of it, to average the grain away.
    final others = [
      for (final c in pool)
        if (!identical(c, best) &&
            c.quad != null &&
            (c.sharpness ?? maxSharp) >= 0.85 * maxSharp)
          c,
    ]..sort((a, b) => (b.sharpness ?? 0).compareTo(a.sharpness ?? 0));
    final page = PageRender.render(
      best.frame,
      quad,
      quarterTurns: best.quarterTurns,
      more: quad == null
          ? const []
          : [
              for (final c in others.take(tuning.merged))
                (
                  c.frame,
                  c.exact
                      ? c.quad!
                      : PageRender.finalCorners(c.frame, c.quad!, c.factor),
                ),
            ],
    );
    // Last check, on the straightened page itself.
    if (!manual &&
        page.sharpness != null &&
        page.sharpness! < tuning.sharpnessFloor * 0.9) {
      return null;
    }
    _savedSignature = best.signature;
    return page.withSource(
      PageSource(
        frame: best.frame,
        quad: quad,
        quarterTurns: best.quarterTurns,
      ),
      redo: _redo && !manual,
    );
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
    // With the shutter in charge, small movements are nothing to report.
    if (!autoCapture && !(light?.tooDark ?? false)) return ScanHint.manual;
    if (!onTrack || motion >= tuning.steadyMotion) return ScanHint.holdSteady;
    if (light != null && light.tooDark) return ScanHint.tooDark;
    if (light != null && light.someGlare) return ScanHint.glare;
    if (!sharpOk) return ScanHint.focusing;
    if (_candidates.isNotEmpty) return ScanHint.capturing;
    if (light != null && light.shadowed) return ScanHint.shadow;
    return ScanHint.holdSteady;
  }
}
