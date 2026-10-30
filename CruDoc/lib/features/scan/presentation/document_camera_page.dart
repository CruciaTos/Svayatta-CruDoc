import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/scan/data/docscan/geometry.dart';
import 'package:doctor_management_app/features/scan/data/docscan/page_render.dart';
import 'package:doctor_management_app/features/scan/data/docscan/scan_engine.dart';
import 'package:doctor_management_app/features/scan/data/docscan/scan_worker.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// How the document camera ended.
class CameraScanResult {
  const CameraScanResult.pages(this.pages) : fallback = false, error = null;
  const CameraScanResult.fallback()
    : pages = const [],
      fallback = true,
      error = null;
  const CameraScanResult.error(this.error) : pages = const [], fallback = false;

  final List<CapturedPage> pages;

  /// The camera could not be opened here; use the system scanner instead.
  final bool fallback;

  /// Something to tell the person (camera permission refused).
  final String? error;
}

/// The live document camera: outlines the page as it is found, and saves
/// it on its own once it has been held still, in focus and well lit for a
/// moment. Several pages can be scanned in a row.
class DocumentCameraPage extends StatefulWidget {
  const DocumentCameraPage({super.key, this.maxPages = 10});

  final int maxPages;

  static Future<CameraScanResult> open(
    BuildContext context, {
    int maxPages = 10,
  }) async {
    final result = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<CameraScanResult>(
        fullscreenDialog: true,
        builder: (_) => DocumentCameraPage(maxPages: maxPages),
      ),
    );
    return result ?? const CameraScanResult.pages([]);
  }

  @override
  State<DocumentCameraPage> createState() => _DocumentCameraPageState();
}

class _DocumentCameraPageState extends State<DocumentCameraPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _minFrameGapMs = 66; // at most ~15 analysed frames a second

  CameraController? _camera;
  ScanWorker? _worker;
  StreamSubscription<WorkerUpdate>? _updatesSub;
  StreamSubscription<AccelerometerEvent>? _tiltSub;
  bool _opening = false;
  bool _done = false;

  int _sensorRotation = 90;
  int _turns = 0; // how the phone is held, for the finished page
  int _lastOfferMs = 0;

  WorkerUpdate? _update;
  final List<CapturedPage> _pages = [];
  bool _auto = true;
  bool _torch = false;
  bool _manualPending = false;
  bool _finishing = false;
  bool _importing = false;
  Timer? _manualTimeout;

  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: CruMotion.standard,
  );

  /// The outline glides between worker updates instead of jumping.
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );
  Quad? _fromQuad;
  Quad? _toQuad;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The outline is drawn in portrait; keep the screen there.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _tiltSub = accelerometerEventStream().listen(_onTilt, onError: (_) {});
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const []);
    _manualTimeout?.cancel();
    _tiltSub?.cancel();
    _updatesSub?.cancel();
    _closeCamera();
    _worker?.dispose();
    _flash.dispose();
    _glide.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _closeCamera();
    } else if (state == AppLifecycleState.resumed && !_done && !_importing) {
      _open();
    }
  }

  // ---- Camera ----------------------------------------------------------

  Future<void> _open() async {
    if (_opening || _camera != null || _done) return;
    _opening = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return _leave(const CameraScanResult.fallback());
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();
      // Optional controls: not every camera has them.
      await _try(
        () => ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp),
      );
      await _try(() => ctrl.setFocusMode(FocusMode.auto));
      await _try(
        () => ctrl.setFlashMode(_torch ? FlashMode.torch : FlashMode.off),
      );
      _worker ??= await ScanWorker.start(autoCapture: _auto);
      _updatesSub ??= _worker!.updates.listen(_onUpdate);
      _sensorRotation = back.sensorOrientation;
      if (!mounted || _done) {
        await ctrl.dispose();
        return;
      }
      await ctrl.startImageStream(_onFrame);
      setState(() => _camera = ctrl);
    } on CameraException catch (e) {
      const denied = {
        'CameraAccessDenied',
        'CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted',
      };
      if (denied.contains(e.code)) {
        _leave(
          const CameraScanResult.error(
            'CruDoc needs the camera to scan. Allow it in Settings and try again.',
          ),
        );
      } else if (e.code != 'CameraPermissionsRequestOngoing') {
        debugPrint('[Scanner] camera failed: ${e.code} ${e.description}');
        _leave(const CameraScanResult.fallback());
      }
    } catch (e) {
      debugPrint('[Scanner] camera failed: $e');
      _leave(const CameraScanResult.fallback());
    } finally {
      _opening = false;
    }
  }

  Future<void> _closeCamera() async {
    final ctrl = _camera;
    if (ctrl == null) return;
    _camera = null;
    if (mounted) setState(() {});
    await _try(() async {
      if (ctrl.value.isStreamingImages) await ctrl.stopImageStream();
    });
    await _try(ctrl.dispose);
  }

  static Future<void> _try(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  void _onFrame(CameraImage image) {
    final worker = _worker;
    if (worker == null || _done) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastOfferMs < _minFrameGapMs) return;
    // Sensors store frames landscape; turn them to match the portrait view.
    final rotation = image.width > image.height ? _sensorRotation : 0;
    if (worker.offer(
      image,
      rotation: rotation,
      quarterTurns: _turns,
      // Android hands over full-range YUV; iOS uses video range.
      fullRange: Platform.isAndroid,
    )) {
      _lastOfferMs = now;
    }
  }

  /// Which way up the phone is held, from gravity. Lying flat over the page
  /// tells nothing, so the last clear reading is kept.
  void _onTilt(AccelerometerEvent e) {
    final x = e.x, y = e.y;
    if (math.sqrt(x * x + y * y) < 3.5) return; // about flat
    final int turns;
    if (y.abs() > 1.5 * x.abs()) {
      turns = y > 0 ? 0 : 2;
    } else if (x.abs() > 1.5 * y.abs()) {
      // Top of the phone to the left: the page's top is at the screen's
      // right, so the picture turns three quarters clockwise.
      turns = x > 0 ? 3 : 1;
    } else {
      return;
    }
    _turns = turns;
  }

  // ---- Worker updates --------------------------------------------------

  void _onUpdate(WorkerUpdate u) {
    if (!mounted) return;
    if (u.focusAt != null) {
      // The page is near the middle; refocusing there is orientation-safe.
      _try(
        () => _camera?.setFocusPoint(const Offset(0.5, 0.5)) ?? Future.value(),
      );
    }
    if (u.page != null) _addPage(u.page!);
    final next = u.quad;
    if (next != null) {
      _fromQuad = _currentQuad ?? next;
      _toQuad = next;
      _glide.forward(from: 0);
    } else {
      _fromQuad = _toQuad = null;
    }
    setState(() => _update = u);
    if (_finishing && u.phase != ScanPhase.capturing) _finish();
  }

  Quad? get _currentQuad {
    final a = _fromQuad, b = _toQuad;
    if (a == null || b == null) return b;
    return a.lerp(b, Curves.easeOut.transform(_glide.value));
  }

  void _addPage(CapturedPage page) {
    _manualPending = false;
    _manualTimeout?.cancel();
    if (_pages.length >= widget.maxPages) return;
    setState(() => _pages.add(page));
    HapticFeedback.mediumImpact();
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _flash.forward(from: 0);
    }
    if (_pages.length >= widget.maxPages) _finish();
  }

  // ---- Actions -----------------------------------------------------------

  void _shutter() {
    final worker = _worker;
    if (worker == null || _manualPending || _camera == null) return;
    MobileHaptics.commit();
    setState(() => _manualPending = true);
    worker.captureNow();
    _manualTimeout = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _manualPending = false);
    });
  }

  void _toggleAuto() {
    MobileHaptics.select();
    setState(() => _auto = !_auto);
    _worker?.setAutoCapture(_auto);
  }

  Future<void> _toggleTorch() async {
    MobileHaptics.select();
    setState(() => _torch = !_torch);
    await _try(
      () =>
          _camera?.setFlashMode(_torch ? FlashMode.torch : FlashMode.off) ??
          Future.value(),
    );
  }

  Future<void> _importPhotos() async {
    if (_importing) return;
    setState(() => _importing = true);
    await _closeCamera();
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      for (final f in result?.files ?? const <PlatformFile>[]) {
        if (_pages.length >= widget.maxPages) break;
        final bytes =
            f.bytes ??
            (f.path == null ? null : await File(f.path!).readAsBytes());
        if (bytes == null) continue;
        final page = await processStillPhoto(bytes);
        if (page != null && mounted) setState(() => _pages.add(page));
      }
    } catch (e) {
      debugPrint('[Scanner] import failed: $e');
    } finally {
      if (mounted) {
        setState(() => _importing = false);
        if (_pages.length >= widget.maxPages) {
          _finish();
        } else {
          _open();
        }
      }
    }
  }

  /// Done. A capture already under way is allowed to land first.
  void _finish() {
    if (_done) return;
    if (_update?.phase == ScanPhase.capturing && !_finishing) {
      setState(() => _finishing = true);
      Timer(const Duration(seconds: 2), _finish);
      return;
    }
    _leave(CameraScanResult.pages(List.of(_pages)));
  }

  void _leave(CameraScanResult result) {
    if (_done) return;
    _done = true;
    _closeCamera();
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _close() async {
    if (_pages.isEmpty) return _leave(const CameraScanResult.pages([]));
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard the scan?'),
        content: Text(
          _pages.length == 1
              ? 'The page you scanned will not be kept.'
              : 'The ${_pages.length} pages you scanned will not be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep scanning'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true) _leave(const CameraScanResult.pages([]));
  }

  // ---- UI ----------------------------------------------------------------

  String get _guidance {
    if (_importing) return 'Reading the photos…';
    if (_finishing) return 'Finishing the page…';
    if (_camera == null) return 'Opening the camera…';
    if (_manualPending) return 'Capturing…';
    final u = _update;
    if (u == null) return 'Point the camera at a page';
    return switch (u.hint) {
      ScanHint.findPage => 'Point the camera at a page',
      ScanHint.fitPage => 'Fit the whole page in view',
      ScanHint.moveCloser => 'Move closer to the page',
      ScanHint.holdSteady => 'Hold steady',
      ScanHint.focusing => 'Focusing — hold steady',
      ScanHint.tooDark => 'Too dark — find more light',
      ScanHint.glare => 'Glare on the page — tilt the phone a little',
      ScanHint.shadow => 'Shadow on the page — hold steady',
      ScanHint.capturing => 'Capturing — hold still',
      ScanHint.saved =>
        _pages.isEmpty
            ? 'Saved'
            : 'Page ${_pages.length} saved — show the next page',
      ScanHint.manual => 'Tap the shutter to capture',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final u = _update;
    final phase = u?.phase ?? ScanPhase.searching;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _preview(c, phase),
              IgnorePointer(
                child: FadeTransition(
                  opacity: ReverseAnimation(_flash),
                  child: AnimatedBuilder(
                    animation: _flash,
                    builder: (context, _) => _flash.isAnimating
                        ? ColoredBox(color: Colors.white.withValues(alpha: 0.6))
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _topBar(),
                    const SizedBox(height: CruSpace.s12),
                    _GuidancePill(text: _guidance),
                    const Spacer(),
                    _bottomBar(c, u),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(CruColors c, ScanPhase phase) {
    final ctrl = _camera;
    final size = ctrl?.value.previewSize;
    if (ctrl == null || size == null || !ctrl.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final w = math.min(size.width, size.height);
    final h = math.max(size.width, size.height);
    final color = switch (phase) {
      ScanPhase.saved => c.green,
      ScanPhase.capturing => c.accent,
      _ => Colors.white,
    };
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(ctrl),
              // Same box as the preview, so the outline lines up with it.
              AnimatedBuilder(
                animation: _glide,
                builder: (context, _) => CustomPaint(
                  painter: _OutlinePainter(
                    quad: _currentQuad,
                    color: color,
                    strokeWidth: w / 160,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s8,
        CruSpace.s12,
        0,
      ),
      child: Row(
        children: [
          _RoundButton(
            semanticLabel: 'Close',
            onTap: _close,
            child: const CruIcon(CruIcons.close, color: Colors.white),
          ),
          const Spacer(),
          _RoundButton(
            semanticLabel: _torch ? 'Turn the light off' : 'Turn the light on',
            onTap: _camera == null ? null : _toggleTorch,
            selected: _torch,
            child: Icon(
              _torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _torch ? Colors.black : Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          CruPressable(
            onTap: _toggleAuto,
            semanticLabel: _auto
                ? 'Automatic capture on. Tap for manual.'
                : 'Manual capture. Tap for automatic.',
            builder: (context, _) => Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _auto
                    ? Colors.white
                    : Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(CruRadius.full),
              ),
              child: Text(
                _auto ? 'Auto' : 'Manual',
                style: MobileType.subhead.tint(
                  _auto ? Colors.black : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(CruColors c, WorkerUpdate? u) {
    final busy = _manualPending || _finishing || _importing;
    final progress = _manualPending
        ? null
        : (u?.phase == ScanPhase.capturing ? u!.progress : 0.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s12,
        CruSpace.s20,
        CruSpace.s20,
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _RoundButton(
                semanticLabel: 'Add from photos',
                onTap: busy ? null : _importPhotos,
                size: 48,
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          _Shutter(
            progress: progress,
            ringColor: c.accent,
            onTap: busy || _camera == null ? null : _shutter,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _pages.isEmpty
                  ? const SizedBox(width: 48)
                  : _DoneButton(
                      page: _pages.last,
                      count: _pages.length,
                      onTap: busy && !_finishing ? null : _finish,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.quad,
    required this.color,
    required this.strokeWidth,
  });

  final Quad? quad;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null) return;
    final pts = [
      for (final p in q.corners) Offset(p.x * size.width, p.y * size.height),
    ];
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = color;
    for (final p in pts) {
      canvas.drawCircle(p, strokeWidth * 2.2, dot);
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
      old.quad != quad || old.color != color || old.strokeWidth != strokeWidth;
}

class _GuidancePill extends StatelessWidget {
  const _GuidancePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: AnimatedSwitcher(
        duration: CruMotion.of(context, CruMotion.fast),
        switchInCurve: CruMotion.curve,
        child: Container(
          key: ValueKey(text),
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s16,
            vertical: CruSpace.s8,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(CruRadius.full),
          ),
          child: Text(text, style: MobileType.subhead.tint(Colors.white)),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.size = 40,
    this.selected = false,
  });

  final String semanticLabel;
  final VoidCallback? onTap;
  final Widget child;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return CruPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder: (context, _) => Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? Colors.white
                : Colors.black.withValues(alpha: 0.45),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The shutter, with a ring that fills as the automatic capture gathers its
/// frames. [progress] null spins (a manual capture under way).
class _Shutter extends StatelessWidget {
  const _Shutter({
    required this.progress,
    required this.ringColor,
    required this.onTap,
  });

  final double? progress;
  final Color ringColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const size = 76.0;
    return CruPressable(
      onTap: onTap,
      semanticLabel: 'Capture the page now',
      builder: (context, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
            ),
            if (progress == null || progress! > 0)
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  color: ringColor,
                  backgroundColor: Colors.transparent,
                ),
              ),
            AnimatedOpacity(
              duration: CruMotion.of(context, CruMotion.fast),
              opacity: onTap == null ? 0.5 : 1,
              child: Container(
                width: size - 18,
                height: size - 18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The last page and how many there are; tap to finish.
class _DoneButton extends StatelessWidget {
  const _DoneButton({
    required this.page,
    required this.count,
    required this.onTap,
  });

  final CapturedPage page;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CruPressable(
      onTap: onTap,
      semanticLabel: count == 1 ? 'Done, 1 page' : 'Done, $count pages',
      builder: (context, _) => Container(
        height: 48,
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s4,
          CruSpace.s4,
          CruSpace.s12,
          CruSpace.s4,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(CruRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(CruRadius.full),
              child: Image.memory(
                page.thumb,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            Text(
              'Done · $count',
              style: MobileType.subhead
                  .tint(Colors.black)
                  .copyWith(fontFeatures: CruType.tabular),
            ),
          ],
        ),
      ),
    );
  }
}
