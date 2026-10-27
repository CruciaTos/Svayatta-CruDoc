import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/services/local_storage_manager.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_previews.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// [file]'s thumbnail bytes, or null when it has none (or it can't be read,
/// e.g. still encrypted because the clinic key hasn't loaded).
Uint8List? fileThumbBytes(PatientFile file) {
  if (file.thumb.isEmpty) return null;
  try {
    return base64Decode(file.thumb);
  } catch (_) {
    return null;
  }
}

/// A picture that is never blank and never locked. The record's thumbnail
/// shows at once (softened), then the full picture sharpens over it chunk
/// by chunk as it downloads: each newer frame slides in top to bottom
/// behind a soft gradient edge. Zoom and pan work from the first frame,
/// and stay put as the quality steps up.
class ProgressivePicture extends StatefulWidget {
  const ProgressivePicture({super.key, required this.file});

  final PatientFile file;

  @override
  State<ProgressivePicture> createState() => _ProgressivePictureState();
}

class _ProgressivePictureState extends State<ProgressivePicture>
    with TickerProviderStateMixin {
  /// Longest edge of the full-quality frame.
  static const int _fullEdge = FilePreviews.viewEdge;

  /// Draw a newer partial frame at most this often, and only once this
  /// much more has arrived.
  static const Duration _minGap = Duration(milliseconds: 140);
  static const int _minStep = 12 * 1024;

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: CruMotion.pane,
    value: 1,
  )..addStatusListener(_onSlideStatus);

  /// The soft light that drifts over the thumbnail until real pixels land.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  ui.Image? _thumb;
  ui.Image? _back;
  ui.Image? _front;
  ui.Image? _pending;

  /// True once a frame has fully covered the thumbnail.
  bool _covered = false;
  bool _done = false;
  String? _error;

  int _gen = 0;
  Uint8List? _latest;
  int _drawnLength = 0;
  bool _decoding = false;
  bool? _progressive;
  Timer? _wait;
  final Stopwatch _sinceDraw = Stopwatch();
  int _previewEdge = 2048;

  @override
  void initState() {
    super.initState();
    _loadThumb();
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Partial frames only need the screen's sharpness; the last one is full.
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    _previewEdge = math.min(
      _fullEdge,
      (math.max(size.width, size.height) * dpr).round(),
    );
    if (!_done && _error == null) {
      _syncSweep();
    }
  }

  @override
  void dispose() {
    _gen++;
    _wait?.cancel();
    _slide.dispose();
    _sweep.dispose();
    for (final i in [_thumb, _back, _front, _pending]) {
      i?.dispose();
    }
    super.dispose();
  }

  // ───────────────────────────── Loading ─────────────────────────────

  Future<void> _loadThumb() async {
    final bytes = fileThumbBytes(widget.file);
    if (bytes == null) return;
    final image = await _decode(bytes);
    if (!mounted || image == null) {
      image?.dispose();
      return;
    }
    setState(() => _thumb = image);
    _syncSweep();
  }

  Future<void> _start() async {
    final gen = ++_gen;
    final f = widget.file;
    final repo = FilesRepository.instance;
    try {
      final here =
          await repo.existingLocalCopy(f) ?? await repo.existingViewCopy(f);
      if (here != null) {
        await LocalStorageManager.touch(here);
        unawaited(repo.ensurePreviews(f));
        await _finish(await here.readAsBytes(), gen);
        return;
      }
      final file = await repo.streamPicture(
        f,
        onBytes: (soFar, _) => _onBytes(soFar, gen),
      );
      await _finish(await file.readAsBytes(), gen);
    } on FilesException catch (e) {
      _fail(e.message, gen);
    } catch (_) {
      _fail(
        "Couldn't download this picture. Check the connection and try again.",
        gen,
      );
    }
  }

  void _retry() {
    setState(() => _error = null);
    _syncSweep();
    _start();
  }

  void _onBytes(Uint8List soFar, int gen) {
    if (gen != _gen || _done) return;
    _latest = soFar;
    _progressive ??= jpegIsProgressive(soFar);
    _drawPartial(gen);
  }

  /// Draws the newest bytes, throttled: one decode at a time, at most every
  /// [_minGap], and only after [_minStep] more bytes.
  Future<void> _drawPartial(int gen) async {
    final bytes = _latest;
    if (_decoding || _progressive != true || bytes == null) return;
    if (bytes.length - _drawnLength < _minStep) return;
    if (_sinceDraw.isRunning && _sinceDraw.elapsed < _minGap) {
      _wait ??= Timer(_minGap - _sinceDraw.elapsed, () {
        _wait = null;
        _drawPartial(gen);
      });
      return;
    }
    _decoding = true;
    _drawnLength = bytes.length;
    final image = await _decode(bytes, maxEdge: _previewEdge);
    _decoding = false;
    _sinceDraw
      ..reset()
      ..start();
    if (gen != _gen || _done || !mounted) {
      image?.dispose();
      return;
    }
    if (image != null) _show(image);
    _drawPartial(gen);
  }

  Future<void> _finish(Uint8List bytes, int gen) async {
    final image = await _decode(bytes, maxEdge: _fullEdge);
    if (gen != _gen || !mounted) {
      image?.dispose();
      return;
    }
    if (image == null) {
      _fail("This picture can't be shown here.", gen);
      return;
    }
    _done = true;
    _wait?.cancel();
    _show(image);
    _syncSweep();
  }

  void _fail(String message, int gen) {
    if (gen != _gen || !mounted) return;
    setState(() => _error = message);
    _syncSweep();
  }

  static Future<ui.Image?> _decode(Uint8List bytes, {int? maxEdge}) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (w, h) {
          final longest = math.max(w, h);
          if (maxEdge == null || longest <= maxEdge) {
            return const ui.TargetImageSize();
          }
          return ui.TargetImageSize(width: (w * maxEdge / longest).round());
        },
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────────── Frames ─────────────────────────────

  void _show(ui.Image image) {
    if (_slide.isAnimating) {
      // Keep only the newest; it slides in when this one has.
      _pending?.dispose();
      _pending = image;
      return;
    }
    _slideIn(image);
  }

  void _slideIn(ui.Image image) {
    setState(() {
      if (_front != null) {
        _back?.dispose();
        _back = _front;
      }
      _front = image;
    });
    _syncSweep();
    _slide.duration = CruMotion.of(context, CruMotion.pane);
    _slide.forward(from: 0);
  }

  void _onSlideStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final next = _pending;
    _pending = null;
    if (next != null) {
      _slideIn(next);
      return;
    }
    // The front covers everything now.
    setState(() {
      _back?.dispose();
      _back = null;
      _covered = true;
    });
  }

  /// The drifting light runs only while nothing but the thumbnail (or
  /// nothing at all) is on screen.
  void _syncSweep() {
    final waiting = _front == null && _error == null && !_done;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (waiting && !reduced) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else if (_sweep.isAnimating) {
      _sweep.stop();
    }
  }

  // ───────────────────────────── Painting ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final shape = _front ?? _back ?? _thumb;
    Widget picture;
    if (shape == null) {
      picture = AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(
          color: c.inset,
          child: _error == null ? LoadingSweep(animation: _sweep) : null,
        ),
      );
    } else {
      final front = _front;
      picture = AspectRatio(
        aspectRatio: shape.width / shape.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_thumb != null && !_covered)
              ClipRect(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 6,
                    sigmaY: 6,
                    tileMode: TileMode.clamp,
                  ),
                  child: RawImage(
                    image: _thumb,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            if (_back != null)
              RawImage(
                image: _back,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            if (front != null)
              AnimatedBuilder(
                animation: _slide,
                builder: (context, child) {
                  if (_slide.isCompleted) return child!;
                  // Each sharper frame fades in from blurred to sharp.
                  final t = CruMotion.curve.transform(_slide.value);
                  return Opacity(
                    opacity: t,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: (1 - t) * 8,
                        sigmaY: (1 - t) * 8,
                        tileMode: TileMode.clamp,
                      ),
                      child: child,
                    ),
                  );
                },
                child: RawImage(
                  image: front,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            if (front == null && _error == null)
              LoadingSweep(animation: _sweep),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(maxScale: 8, child: Center(child: picture)),
        ),
        if (_error != null)
          Positioned(
            left: CruSpace.s16,
            right: CruSpace.s16,
            bottom: CruSpace.s24,
            child: _ErrorBar(message: _error!, onRetry: _retry),
          ),
      ],
    );
  }
}

/// A soft band of light drifting down, so a waiting picture reads as
/// loading without a spinner.
class LoadingSweep extends StatelessWidget {
  const LoadingSweep({super.key, required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final glow = context.cru.surface;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final y = -1.6 + 3.2 * CruMotion.curve.transform(animation.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(0, y - 0.6),
                end: Alignment(0, y + 0.6),
                colors: [
                  glow.withValues(alpha: 0),
                  glow.withValues(alpha: 0.28),
                  glow.withValues(alpha: 0),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Center(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surface,
          shape: cruShape(CruRadius.card),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s16,
            CruSpace.s12,
            CruSpace.s12,
            CruSpace.s12,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(message, style: CruType.subhead.tint(c.label2)),
              ),
              const SizedBox(width: CruSpace.s12),
              CruButton(
                label: 'Try again',
                kind: CruButtonKind.secondary,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pixel size of a baseline or progressive JPEG, read from its frame
/// header without decoding; null when [bytes] isn't one.
Size? jpegSize(Uint8List? bytes) {
  if (bytes == null || bytes.length < 4) return null;
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var i = 2;
  while (i + 8 < bytes.length) {
    if (bytes[i] != 0xFF) return null;
    final marker = bytes[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
      final h = (bytes[i + 5] << 8) | bytes[i + 6];
      final w = (bytes[i + 7] << 8) | bytes[i + 8];
      return w > 0 && h > 0 ? Size(w.toDouble(), h.toDouble()) : null;
    }
    i += 2 + ((bytes[i + 2] << 8) | bytes[i + 3]);
  }
  return null;
}
